<#
.SYNOPSIS
  Minimal sensor: one channel, one message.
.DESCRIPTION
  The smallest useful sensor. Invoke-PrtgSensor handles the boilerplate (clean state, error
  handling, single valid JSON response). Build channels with New-PrtgChannel | Add-PrtgChannel.
  Deploy as a PRTG "EXE/Script Advanced" sensor (drop into the probe's Custom Sensors\EXEXML folder).
.NOTES
  Requires the PrtgSensorKit module installed on the probe.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  $value = Get-Random -Minimum 1 -Maximum 100
  New-PrtgChannel -Channel 'Random Value' -Value $value | Add-PrtgChannel
  Set-PrtgMessage "Sampled $value"
}
