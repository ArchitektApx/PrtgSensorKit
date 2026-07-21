<#
.SYNOPSIS
  FAILING (clean): more than 50 channels.
.DESCRIPTION
  PRTG allows at most 50 channels; Add-PrtgChannel throws on the 51st. The throw is caught
  by Invoke-PrtgSensor and turned into a PRTG error response. Expected PRTG result: Down
  with an error message about the 50-channel limit. Validates that the channel cap fires
  as a clean error, not corrupt output. No network.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  1..51 | ForEach-Object {
    New-PrtgChannel -Channel "Channel $_" -Value $_ | Add-PrtgChannel
  }
  Set-PrtgMessage 'should never be reached'
}
