<#
.SYNOPSIS
  Relaunching into 64-bit PowerShell (or PowerShell 7) before running.
.DESCRIPTION
  PRTG often starts custom sensors in 32-bit Windows PowerShell. Call the relaunch helpers at the
  TOP LEVEL, before Invoke-PrtgSensor: they re-run the whole script in the target host and exit.
  Do NOT call them inside the block (the relaunched child's output would be discarded).

  Import any modules your sensor needs AFTER the relaunch. A 32-bit process cannot see modules
  installed for 64-bit PowerShell, so importing before the relaunch would fail.
.NOTES
  Requires the PrtgSensorKit module installed on the probe.
#>
Import-Module PrtgSensorKit

Restart-As64BitPowershell
# Restart-InPwsh   # uncomment if your sensor needs PowerShell 7+ features/modules

# Import other modules you depend on here, now that you are in the right host.

Invoke-PrtgSensor {
  New-PrtgChannel -Channel 'Is 64-bit' -Value ([int][Environment]::Is64BitProcess) `
    -ValueLookup 'prtg.standardlookups.boolean' |
    Add-PrtgChannel

  Set-PrtgMessage "Running in $([IntPtr]::Size * 8)-bit PowerShell"
}
