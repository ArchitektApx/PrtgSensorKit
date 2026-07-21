<#
.SYNOPSIS
  MALFORMED (PSK0005): Write-PrtgOutput called inside the Invoke-PrtgSensor block.
.DESCRIPTION
  The wrapper owns the single response; calling Write-PrtgOutput inside the block emits a
  second JSON document (once from the manual call, once from the wrapper). Expected PRTG
  result: XML/parse error from the doubled output. Doctor: PSK0005 Error ('manual output
  command inside the block is not supported'). No network.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  New-PrtgChannel -Channel 'Answer' -Value 42 | Add-PrtgChannel
  Write-PrtgOutput
}
