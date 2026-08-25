function Get-PrtgSecretPath {
  <#
  .SYNOPSIS
    Resolves the secret store folder. Does not create it.
  .DESCRIPTION
    Shared by Save-PrtgSecret and Get-PrtgSecret so the two cannot drift: an explicit -Path
    override, or '$env:ProgramData\PrtgSensorKit\Secrets' on Windows and a temp folder elsewhere.

    Pure on purpose. Only Save-PrtgSecret wants the folder created, so creation stays there:
    reading a secret must leave nothing behind when it fails.

    Unlike Get-PrtgStatePath, this does NOT resolve a relative path. That sibling has to, because
    its lock sidecar is opened through a raw [System.IO.FileStream], which resolves against the
    PROCESS working directory rather than PowerShell's current location. The secret store has no
    such consumer - every path user here goes through the PowerShell provider, and the atomic
    move resolves both of its own paths - so resolving here would only turn stored paths absolute
    and change the paths printed in the not-found and corrupt messages.
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
