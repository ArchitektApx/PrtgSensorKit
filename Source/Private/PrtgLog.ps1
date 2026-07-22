# Module-scope logging state. One log file per sensor invocation (process): the first
# Write-PrtgLog call creates the run file and caches its path here; every later call in
# the same process appends to it. Invoke-PrtgSensor -EnableLogging sets the directory and
# retention for the duration of the call and restores them afterwards.
$script:PrtgLogFile = $null
$script:PrtgLogDirectory = $null
$script:PrtgLogMaxLogs = 30
# UTF-8 with BOM on Windows PowerShell 5.1 (5.1-native tools read BOM-less files as
# ANSI), plain UTF-8 on PowerShell 7+. Constant per process, so built once.
$script:PrtgLogEncoding = [System.Text.UTF8Encoding]::new($PSVersionTable.PSEdition -eq 'Desktop')

function Get-PrtgLogCallerScriptPath {
  # Full path of the first non-module script on the call stack, or $null when invoked
  # interactively. Anchors the run-file name and relative -LogPath resolution to the
  # user's sensor script instead of this module or the process CWD (PRTG starts sensors
  # with an unhelpful CWD).
  [CmdletBinding()]
  [OutputType([string])]
  param()

  $frame = Get-PSCallStack | Where-Object {
    $_.ScriptName -and $_.ScriptName -notmatch '[\\/]PrtgSensorKit\.psm1$'
  } | Select-Object -First 1
  if ($frame) { return $frame.ScriptName }
  return $null
}

function Get-PrtgLogScriptName {
  # File name (no extension) of the invoking script; 'console' when interactive. Used
  # for the default log folder and the run-file name.
  [CmdletBinding()]
  [OutputType([string])]
  param()

  $callerScript = Get-PrtgLogCallerScriptPath
  if ($callerScript) { return [System.IO.Path]::GetFileNameWithoutExtension($callerScript) }
  return 'console'
}

function New-PrtgLogFile {
  # Creates this invocation's run log file (writing the first entry) and prunes old run
  # files beyond the retention count. Callers handle exceptions; Write-PrtgLog wraps
  # everything in its never-throw guard.
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Logging-internal file creation; the public cmdlet contract is fire-and-forget.')]
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory = $true)]
    [string]$FirstLine
  )

  $scriptName = Get-PrtgLogScriptName
  $directory = $script:PrtgLogDirectory
  if ([string]::IsNullOrEmpty($directory)) {
    # Default location, consistent with the state store.
    $directory = Join-Path (Get-PrtgDataPath -Store 'Logs') $scriptName
  }
  if (-not (Test-Path -LiteralPath $directory)) {
    [void] (New-Item -ItemType Directory -Path $directory -Force)
  }

  # The PID disambiguates two sibling sensors starting in the same second. Invariant
  # culture: default formatting would render non-Gregorian years (Buddhist, Hijri) on
  # probes with those OS cultures.
  $stamp = [DateTime]::Now.ToString('yyyyMMdd-HHmmss', [System.Globalization.CultureInfo]::InvariantCulture)
  $file = Join-Path $directory ('{0}_{1}_{2}.log' -f $scriptName, $stamp, $PID)
  [System.IO.File]::WriteAllText($file, $FirstLine, $script:PrtgLogEncoding)

  # Keep the newest MaxLogs run files (the new one counts); 0 = keep all. Delete failures
  # are swallowed: concurrent sensors pruning the same folder race harmlessly.
  if ($script:PrtgLogMaxLogs -gt 0) {
    $stale = @(Get-ChildItem -LiteralPath $directory -Filter '*.log' -File |
      Sort-Object -Property LastWriteTime -Descending |
      Select-Object -Skip $script:PrtgLogMaxLogs)
    foreach ($item in $stale) {
      try { Remove-Item -LiteralPath $item.FullName -Force }
      catch { Write-Verbose "New-PrtgLogFile: could not prune '$($item.FullName)'. ($($_.Exception.Message))" }
    }
  }

  $file
}
