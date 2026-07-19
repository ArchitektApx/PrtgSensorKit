<#
.SYNOPSIS
  Automatic error reporting.
.DESCRIPTION
  Any terminating error inside the Invoke-PrtgSensor block is turned into a PRTG error response
  ({ prtg: { error: 1, text: ... } }) automatically. No try/catch needed. This example queries an
  endpoint that fails, so PRTG shows the sensor in a Down state with the error text.
.NOTES
  Requires the PrtgSensorKit module installed on the probe.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  $endpoint = 'https://does-not-exist.invalid/health'

  # This throws; Invoke-PrtgSensor catches it and emits a PRTG error response instead of channels.
  $null = Invoke-RestMethod -Uri $endpoint -TimeoutSec 5

  New-PrtgChannel -Channel 'Up' -Value 1 | Add-PrtgChannel
}
