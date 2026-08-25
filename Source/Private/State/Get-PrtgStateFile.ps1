function Get-PrtgStateFile {
  <#
  .SYNOPSIS
    Resolves the folder, entry file, and lock sidecar for a state or cache key.
  .DESCRIPTION
    Shared by Save/Get/Clear-PrtgSensorState and Use-PrtgCachedResult, which all address the
    same store. One definition so the four can never disagree on where a key lives or what its
    lock is called.
  #>
  [CmdletBinding()]
  [OutputType([PSCustomObject])]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Key,

    [Parameter(Mandatory = $false)]
    [string]$Path
  )

  $folder = Get-PrtgStatePath -Path $Path
  $file = Join-Path $folder "$Key.clixml"

  [PSCustomObject]@{
    Folder   = $folder
    File     = $file
    LockFile = "$file.lock"
  }
}
