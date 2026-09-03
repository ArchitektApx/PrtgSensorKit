function Get-PrtgDoctorHostPath {
  <#
  .SYNOPSIS
    The powershell.exe path for the requested bitness.
  .DESCRIPTION
    Honors the WOW64 filesystem redirection of the current process: System32 is redirected
    for a 32-bit process, and Sysnative escapes the redirection.
  #>
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('x86', 'x64')]
    [string]$Bitness
  )

  $winPs = 'WindowsPowerShell\v1.0\powershell.exe'
  if (-not [System.Environment]::Is64BitOperatingSystem) {
    return (Join-Path $env:SystemRoot "System32\$winPs")
  }

  if ($Bitness -eq 'x86') {
    if ([System.Environment]::Is64BitProcess) { Join-Path $env:SystemRoot "SysWOW64\$winPs" }
    else { Join-Path $env:SystemRoot "System32\$winPs" }
  } else {
    if ([System.Environment]::Is64BitProcess) { Join-Path $env:SystemRoot "System32\$winPs" }
    else { Join-Path $env:SystemRoot "Sysnative\$winPs" }
  }
}
