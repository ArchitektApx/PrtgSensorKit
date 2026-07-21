function Get-PrtgStatePath {
  <#
  .SYNOPSIS
    Resolves the sensor state store folder and ensures it exists.
  .DESCRIPTION
    Returns the folder used by Save/Get/Clear-PrtgSensorState: an explicit -Path override,
    or '$env:ProgramData\PrtgSensorKit\State' on Windows and a temp folder elsewhere
    (same fallback pattern as the secret store). Creates the folder on first use. State is
    not secret, so unlike the secret store there is no DPAPI/ACL handling here.
  #>
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory = $false)]
    [string]$Path
  )

  if ([string]::IsNullOrEmpty($Path)) {
    $Path = if (Test-PrtgWindows) { Join-Path $env:ProgramData 'PrtgSensorKit\State' }
            else { Join-Path ([System.IO.Path]::GetTempPath()) 'PrtgSensorKit/State' }
  }

  if (-not (Test-Path -LiteralPath $Path)) {
    [void] (New-Item -ItemType Directory -Path $Path -Force)
  }

  $Path
}
