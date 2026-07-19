<#
.SYNOPSIS
  Low-level API without the Invoke-PrtgSensor wrapper.
.DESCRIPTION
  When you need full control, build the output by hand: Clear-PrtgOutput to start clean, add
  channels, set the message, then Write-PrtgOutput exactly once. Wrap it in try/catch and route
  failures through Write-PrtgError yourself. Most sensors should prefer Invoke-PrtgSensor (see the
  other examples); this shows what it does under the hood.
.NOTES
  Requires the PrtgSensorKit module installed on the probe.
#>
Import-Module PrtgSensorKit

try {
  Clear-PrtgOutput

  New-PrtgChannel -Channel 'Items'  -Value 3            | Add-PrtgChannel
  New-PrtgChannel -Channel 'Errors' -Value 0 -Warning   | Add-PrtgChannel

  Set-PrtgMessage 'Manual build complete'
  Write-PrtgOutput
} catch {
  $_ | Write-PrtgError
}
