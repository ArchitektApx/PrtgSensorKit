<#
.SYNOPSIS
  Letting some errors inside Invoke-PrtgSensor be non-terminating.
.DESCRIPTION
  Invoke-PrtgSensor sets $ErrorActionPreference to 'Stop', so any error inside the block is
  terminating and gets caught and reported to PRTG automatically. If part of your script has a
  command that's allowed to fail without ending the sensor, set $ErrorActionPreference to
  'SilentlyContinue' or 'Continue' around it, then set it back to 'Stop' so Invoke-PrtgSensor resumes handling errors
  for the rest of the block.
.NOTES
  Requires the PrtgSensorKit module installed on the probe.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  # Any error here is terminating and caught by Invoke-PrtgSensor.
  $primary = Invoke-RestMethod -Uri 'https://api.example.com/primary' -TimeoutSec 5

  # On Cmdlets that support the -ErrorAction parameter, you can set it to 'SilentlyContinue' to let the command fail silently.
  $optional0 = Invoke-RestMethod -Uri 'https://somedomain.com' -TimeoutSec 5 -ErrorAction SilentlyContinue

  # On Cmdlets that do not support the -ErrorAction parameter, you can set scopes $ErrorActionPreference to 'SilentlyContinue'
  $ErrorActionPreference = 'SilentlyContinue'
  # This command is optional; failures here are not caught by Invoke-PrtgSensor and won't fail the sensor.
  $optional1 = Some-CommandThatMightFailButItsOk -Parameter $Parameter

  # Back to 'Stop' so Invoke-PrtgSensor handles errors again for the rest of the block.
  $ErrorActionPreference = 'Stop'

  New-PrtgChannel -Channel 'Primary' -Value $primary.count | Add-PrtgChannel
}
