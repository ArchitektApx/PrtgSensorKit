function Get-PrtgDataPath {
  <#
  .SYNOPSIS
    Resolves the base folder for an on-disk store (State, Logs, Secrets).
  .DESCRIPTION
    Single definition of the platform fallback shared by the state, log, and secret stores:
    '$env:ProgramData\PrtgSensorKit\<Store>' on Windows, a temp folder elsewhere.
  #>
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Store
  )

  if (Test-PrtgWindows) { Join-Path $env:ProgramData "PrtgSensorKit\$Store" }
  else { Join-Path ([System.IO.Path]::GetTempPath()) "PrtgSensorKit/$Store" }
}

function Get-PrtgStatePath {
  <#
  .SYNOPSIS
    Resolves the sensor state store folder and ensures it exists.
  .DESCRIPTION
    Returns the folder used by Save/Get/Clear-PrtgSensorState: an explicit -Path override,
    or '$env:ProgramData\PrtgSensorKit\State' on Windows and a temp folder elsewhere (the same
    Get-PrtgDataPath fallback the log and secret stores use). Creates the folder on first use.
    State is not secret, so unlike the secret store there is no DPAPI/ACL handling here.
  #>
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory = $false)]
    [string]$Path
  )

  if ([string]::IsNullOrEmpty($Path)) {
    $Path = Get-PrtgDataPath -Store 'State'
  }

  # .NET resolves a relative path against the PROCESS working directory, not PowerShell's
  # current location (the trap Move-PrtgFileAtomic documents), and the lock sidecar goes
  # straight to [System.IO.FileStream]. Resolve once here so folder, state file, and lock agree.
  $Path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    [void] (New-Item -ItemType Directory -Path $Path -Force)
  }

  $Path
}
