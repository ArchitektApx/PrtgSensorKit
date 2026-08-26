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

function Push-PrtgLogScope {
  <#
    .SYNOPSIS
      Points the session log directory and retention at one call's settings, and returns the
      token that puts them back.
    .DESCRIPTION
      The caller decides whether logging is on at all; this is only ever reached when it is.

      -LogPath and -MaxLogs are read as bound-or-not rather than by value, because an omitted
      -LogPath must leave the session directory alone while an explicit one that happens to
      match it must still be honored.

      A relative -LogPath anchors to the sensor script rather than to the working directory:
      PRTG starts sensors with an unhelpful one.
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Logging-internal scope switch, undone by Pop-PrtgLogScope; the public cmdlet contract is fire-and-forget.')]
  [CmdletBinding()]
  [OutputType([hashtable])]
  param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$LogPath,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, [int]::MaxValue)]
    [int]$MaxLogs
  )

  $token = @{
    Directory   = $script:PrtgLogDirectory
    MaxLogs     = $script:PrtgLogMaxLogs
    File        = $script:PrtgLogFile
    RestoreFile = $false
  }

  if ($PSBoundParameters.ContainsKey('LogPath')) {
    $resolved = $LogPath
    if (-not [System.IO.Path]::IsPathRooted($resolved)) {
      $callerScript = Get-PrtgLogCallerScriptPath
      $baseDirectory = if ($callerScript) { Split-Path -Parent $callerScript } else { (Get-Location).Path }
      $resolved = Join-Path $baseDirectory $resolved
    }
    $script:PrtgLogDirectory = $resolved

    # An earlier Write-PrtgLog call may have pinned this process's run file to another folder;
    # honor the explicit -LogPath by starting a new run file there.
    if ($script:PrtgLogFile -and (Split-Path -Parent $script:PrtgLogFile) -ne $resolved) {
      $script:PrtgLogFile = $null
      $token.RestoreFile = $true
    }
  }

  if ($PSBoundParameters.ContainsKey('MaxLogs')) { $script:PrtgLogMaxLogs = $MaxLogs }

  $token
}

function Pop-PrtgLogScope {
  <#
    .SYNOPSIS
      Restores what Push-PrtgLogScope saved.
    .DESCRIPTION
      A null token is a no-op, so the caller's restore is one unconditional line and cannot
      grow a second guard that disagrees with the push's.

      The run file restore is deliberately asymmetric with the directory and retention
      restores, and must stay that way. Only the push branch that DISCARDED the run file sets
      RestoreFile. Restoring unconditionally would null the run file this call itself created,
      and the script's next Write-PrtgLog would start a SECOND file instead of appending.
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Logging-internal scope restore paired with Push-PrtgLogScope; the public cmdlet contract is fire-and-forget.')]
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $false, Position = 0)]
    [AllowNull()]
    [hashtable]$Token
  )

  if ($null -eq $Token) { return }

  $script:PrtgLogDirectory = $Token.Directory
  $script:PrtgLogMaxLogs = $Token.MaxLogs
  if ($Token.RestoreFile) { $script:PrtgLogFile = $Token.File }
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
    # Prune only run files THIS script wrote (the full '<name>_<stamp>_<pid>.log' shape built
    # above). A -LogPath may be shared - two sensors in one folder, or a folder holding
    # unrelated application logs - and the sweep must never delete a file this module did not
    # create. [regex]::Escape guards script names containing regex metacharacters
    # ('sensor[1].ps1'); the '$' anchor also keeps the 8.3 short-name protection documented in
    # Remove-PrtgStaleTempFile.ps1. Retention is therefore per script name: run files of a
    # since-renamed script are never pruned.
    $ownRunFile = '^' + [regex]::Escape($scriptName) + '_\d{8}-\d{6}_\d+\.log$'
    $stale = @(Get-ChildItem -LiteralPath $directory -Filter '*.log' -File |
      Where-Object { $_.Name -match $ownRunFile } |
      Sort-Object -Property LastWriteTime -Descending |
      Select-Object -Skip $script:PrtgLogMaxLogs)
    foreach ($item in $stale) {
      try { Remove-Item -LiteralPath $item.FullName -Force }
      catch { Write-Verbose "New-PrtgLogFile: could not prune '$($item.FullName)'. ($($_.Exception.Message))" }
    }
  }

  $file
}
