function Restart-InPwsh {
  <#
  .SYNOPSIS
      Ensures the current script runs in PowerShell 7+ (pwsh).

  .DESCRIPTION
      PRTG runs custom sensors in Windows PowerShell 5.1 (Desktop edition). If your sensor needs
      PowerShell 7+ features or modules, call this early (after Import-Module PrtgSensorKit) to
      re-invoke the same command line under pwsh, then exit so the caller can rely on running in
      pwsh. No-op when already on PowerShell Core. Warns and continues if pwsh is not installed.

      Can be combined with Restart-As64BitPowershell.

  .EXAMPLE
      Import-Module PrtgSensorKit
      Restart-InPwsh
      # rest of your sensor runs under pwsh

  .LINK
      Restart-As64BitPowershell
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Non-interactive sensor bootstrap that relaunches the process; a -Confirm prompt would stall a PRTG probe.')]
  [CmdletBinding()]
  param()

  # Desktop edition == Windows PowerShell 5.1; Core == pwsh 6+, so only act on Desktop
  if ($PSVersionTable.PSEdition -eq 'Desktop') {
    $Pwsh = Get-Command -Name 'pwsh' -CommandType Application -ErrorAction SilentlyContinue |
      Select-Object -First 1
    if (-not $Pwsh) {
      Write-Warning "Restart-InPwsh: PowerShell 7+ (pwsh) not found; continuing in Windows PowerShell."
      return
    }

    try {
      # Relaunch the CALLING sensor script. From a module function, the caller's $MyInvocation is
      # not reachable via scope; take it from the call stack ([0] is this function, [1] the caller).
      $CallerInvocation = (Get-PSCallStack)[1].InvocationInfo
      Invoke-PrtgRelaunch -Executable $Pwsh.Source -Invocation $CallerInvocation
    } catch {
      throw "Restart-InPwsh: Failed to start PowerShell 7+: $_"
    }
  }
}
