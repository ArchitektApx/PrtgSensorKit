<#
.SYNOPSIS
  WORKING baseline: one static channel.
.DESCRIPTION
  Simplest valid sensor. Expected PRTG result: Up, one channel 'Answer' = 42, message 'ok'.
  No external dependencies, fully deterministic.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  New-PrtgChannel -Channel 'Answer' -Value 42 | Add-PrtgChannel
  Set-PrtgMessage 'ok'
}
