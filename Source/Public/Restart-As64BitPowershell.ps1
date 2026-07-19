function Restart-As64BitPowershell {
  <#
  .SYNOPSIS
      Ensures the current script runs in 64-bit PowerShell.

  .DESCRIPTION
      PRTG and some hosts start PowerShell as a 32-bit (x86) Process. This function detects this and re-invokes
      the same command line in 64-bit PowerShell, then exits so the caller can rely on running in 64-bit.
      Call early in your script after importing the module (e.g. after Import-Module PrtgSensorKit).

  .EXAMPLE
      Import-Module PrtgSensorKit
      Restart-As64BitPowershell
      # rest of your sensor runs in 64-bit PowerShell

  .LINK
      Restart-InPwsh
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Non-interactive sensor bootstrap that relaunches the process; a -Confirm prompt would stall a PRTG probe.')]
  [CmdletBinding()]
  param()

  # Only restart when we're in 32-bit process on 64-bit Windows
  if (-not [Environment]::Is64BitProcess) {
    $Powershell64BitPath = "$env:WINDIR\sysnative\windowspowershell\v1.0\powershell.exe"
    if (-not (Test-Path -LiteralPath $Powershell64BitPath -PathType Leaf)) {
      Write-Warning "Restart-As64BitPowershell: 64-bit PowerShell not found at '$Powershell64BitPath'."
      return
    }

    try {
      # Relaunch the CALLING sensor script. From a module function, the caller's $MyInvocation is
      # not reachable via scope; take it from the call stack ([0] is this function, [1] the caller).
      $CallerInvocation = (Get-PSCallStack)[1].InvocationInfo
      Invoke-PrtgRelaunch -Executable $Powershell64BitPath -Invocation $CallerInvocation
    } catch {
      throw "Restart-As64BitPowershell: Failed to start 64-bit PowerShell: $_"
    }
  }
}
