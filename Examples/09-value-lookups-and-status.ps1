<#
.SYNOPSIS
  Value lookups: turn a number into an up/down (or status) channel.
.DESCRIPTION
  A value lookup maps a numeric channel value to text/state in PRTG. Use a built-in lookup such as
  'prtg.standardlookups.boolean' (0 = down/false, 1 = up/true), or a custom lookup you define in
  PRTG. Combine with -NotifyChanged so PRTG can trigger a notification when the state flips.
.NOTES
  Requires the PrtgSensorKit module installed on the probe. Windows (uses Get-Service).
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  $svc = Get-Service -Name 'Spooler'
  $isRunning = [int]($svc.Status -eq 'Running')

  New-PrtgChannel -Channel 'Spooler Running' -Value $isRunning `
    -ValueLookup 'prtg.standardlookups.boolean' -NotifyChanged |
    Add-PrtgChannel

  if ($isRunning) { Set-PrtgMessage 'Print Spooler OK' }
  else { Set-PrtgMessage 'Print Spooler is NOT running' }
}
