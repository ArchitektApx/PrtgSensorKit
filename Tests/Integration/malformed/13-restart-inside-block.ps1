<#
.SYNOPSIS
  MALFORMED (PSK0003): Restart-* called inside the Invoke-PrtgSensor block.
.DESCRIPTION
  Restart-InPwsh relaunches the sensor as a child process, whose stdout is swallowed by the
  wrapper's output guard when called inside the block. Expected PRTG result: empty or
  corrupt output (no valid JSON reaches PRTG). Doctor: PSK0003 Error ('Restart-* inside the
  block'). Must run on a host where pwsh exists for the relaunch to actually happen; on a
  host without pwsh Restart-InPwsh warns and continues, still an invalid pattern to flag.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  Restart-InPwsh
  New-PrtgChannel -Channel 'Answer' -Value 42 | Add-PrtgChannel
  Set-PrtgMessage 'ok'
}
