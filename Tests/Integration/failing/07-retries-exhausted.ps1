<#
.SYNOPSIS
  FAILING (clean): all retry attempts fail.
.DESCRIPTION
  The block always throws with -RetryCount 2, so all three attempts fail. Expected PRTG
  result: Down with error text starting 'unsuccessful after 2 retries:' followed by the
  last error. Validates the retry-exhaustion decoration end to end. Total runtime is
  ~2 seconds of delay (2 retries x 1s); stays well under any sensor timeout. No network.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor -RetryCount 2 -RetryDelaySeconds 1 {
  throw 'still failing'
}
