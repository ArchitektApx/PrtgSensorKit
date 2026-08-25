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
