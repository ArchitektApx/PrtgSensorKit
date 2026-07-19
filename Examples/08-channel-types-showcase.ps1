<#
.SYNOPSIS
  Showcase of channel units and options.
.DESCRIPTION
  One sensor exercising the range of channel types: counts, percentages, temperature, response
  time with limits, bandwidth with speed prefixes, disk volume size, a custom unit, a value
  lookup, and change notification. Useful as a visual reference on a real PRTG probe.
.NOTES
  Requires the PrtgSensorKit module installed on the probe.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  New-PrtgChannel -Channel 'Count'         -Value 42                                  | Add-PrtgChannel
  New-PrtgChannel -Channel 'Percentage'    -Value 63.5 -Unit Percent -Float           | Add-PrtgChannel
  New-PrtgChannel -Channel 'Temperature'   -Value 41.2 -Unit Temperature -Float       | Add-PrtgChannel

  New-PrtgChannel -Channel 'Response Time' -Value 128 -Unit TimeResponse `
    -LimitMode $true -LimitMaxWarning 200 -LimitMaxError 500 | Add-PrtgChannel

  New-PrtgChannel -Channel 'Throughput'    -Value 1250000 -Unit BytesBandwidth `
    -SpeedSize Mega -SpeedTime Second | Add-PrtgChannel

  New-PrtgChannel -Channel 'Disk Size'     -Value 500 -Unit BytesDisk -VolumeSize Giga | Add-PrtgChannel
  New-PrtgChannel -Channel 'Custom Unit'   -Value 7 -Unit Custom -CustomUnit 'req/s'   | Add-PrtgChannel

  New-PrtgChannel -Channel 'Online'        -Value 1 `
    -ValueLookup 'prtg.standardlookups.boolean' -NotifyChanged | Add-PrtgChannel

  Set-PrtgMessage 'Showcase of channel types and units'
}
