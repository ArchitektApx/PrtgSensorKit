# Module-scope logging state. One run file per process: the first Write-PrtgLog call creates
# it and caches its path here, and every later call in the same process appends.
$script:PrtgLogFile = $null
$script:PrtgLogDirectory = $null
$script:PrtgLogMaxLogs = 30
# UTF-8 with BOM on Windows PowerShell 5.1 (5.1-native tools read BOM-less files as
# ANSI), plain UTF-8 on PowerShell 7+. Constant per process, so built once.
$script:PrtgLogEncoding = [System.Text.UTF8Encoding]::new($PSVersionTable.PSEdition -eq 'Desktop')

function Get-PrtgLogCallerScriptPath {
  <#
    .SYNOPSIS
      Full path of the first non-module script on the call stack, or $null when interactive.
  #>
  [CmdletBinding()]
  [OutputType([string])]
  param()

  # A module frame is recognised by folder (ModuleBase), not by file name: the build is one
  # file, an import from Source/ is many.
  $moduleRoot = $ExecutionContext.SessionState.Module.ModuleBase + [IO.Path]::DirectorySeparatorChar
  $casing = if (Test-PrtgWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
  $frame = Get-PSCallStack | Where-Object {
    $_.ScriptName -and -not $_.ScriptName.StartsWith($moduleRoot, $casing)
  } | Select-Object -First 1
  if ($frame) { return $frame.ScriptName }
  return $null
}

function Get-PrtgLogScriptName {
  <#
    .SYNOPSIS
      File name without extension of the invoking script; 'console' when interactive.
  #>
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
      -LogPath and -MaxLogs are read bound-or-not, so an omitted -LogPath leaves the session
      directory alone. A relative -LogPath anchors to the sensor script.
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
      A null token is a no-op. The run file is restored only when Push discarded it; an
      unconditional restore would split one run into two files.
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
  <#
    .SYNOPSIS
      Creates this invocation's run log file with its first entry and prunes old run files.
    .DESCRIPTION
      Exceptions propagate to the caller.
  #>
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

  # The PID disambiguates two sibling sensors starting in the same second. Invariant culture:
  # the default would render non-Gregorian years on probes with those OS cultures.
  $stamp = [DateTime]::Now.ToString('yyyyMMdd-HHmmss', [System.Globalization.CultureInfo]::InvariantCulture)
  $file = Join-Path $directory ('{0}_{1}_{2}.log' -f $scriptName, $stamp, $PID)
  [System.IO.File]::WriteAllText($file, $FirstLine, $script:PrtgLogEncoding)

  # Keep the newest MaxLogs run files (the new one counts); 0 = keep all. Delete failures
  # are swallowed: concurrent sensors pruning the same folder race harmlessly.
  if ($script:PrtgLogMaxLogs -gt 0) {
    # The sweep prunes only this script's own run-file pattern, because a -LogPath may be
    # shared. [regex]::Escape guards script names holding regex metacharacters.
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
