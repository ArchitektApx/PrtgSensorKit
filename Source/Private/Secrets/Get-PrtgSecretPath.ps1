function Get-PrtgSecretPath {
  <#
  .SYNOPSIS
    Resolves the secret store folder. Does not create it.
  .DESCRIPTION
    Returns an explicit -Path override, or '$env:ProgramData\PrtgSensorKit\Secrets' on Windows
    and a temp folder elsewhere. Pure: only Save-PrtgSecret creates the folder. A relative path
    is left as-is, unlike Get-PrtgStatePath, which has a FileStream consumer.
  #>
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory = $false)]
    [string]$Path
  )

  if ([string]::IsNullOrEmpty($Path)) { return (Get-PrtgDataPath -Store 'Secrets') }

  $Path
}
