function Test-PrtgWindows {
  # True on Windows. On Windows PowerShell 5.1 $IsWindows is undefined, so PSEdition 'Desktop'
  # implies Windows; on PowerShell Core $IsWindows is authoritative.
  return (($PSVersionTable.PSEdition -eq 'Desktop') -or [bool]$IsWindows)
}
