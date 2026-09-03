function Test-PrtgWindows {
  <#
  .SYNOPSIS
    True on Windows.
  .DESCRIPTION
    $IsWindows is undefined on Windows PowerShell 5.1, where PSEdition 'Desktop' implies
    Windows; on PowerShell Core $IsWindows is authoritative.
  #>
  return (($PSVersionTable.PSEdition -eq 'Desktop') -or [bool]$IsWindows)
}
