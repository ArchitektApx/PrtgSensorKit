<#
.SYNOPSIS
  WORKING: block fails once, succeeds on retry.
.DESCRIPTION
  The block throws on its first attempt and succeeds on the second, so -RetryCount kicks
  in. Expected PRTG result: Up, channel 'Attempts' = 2, message ends
  '(1/3 retries attempted)'. The counter is a script-scope variable that survives across
  attempts within a single run (Clear-PrtgOutput between attempts does not touch it).
  Deterministic, no network.
#>
Import-Module PrtgSensorKit

$script:AttemptCount = 0

Invoke-PrtgSensor -RetryCount 3 {
  $script:AttemptCount++
  if ($script:AttemptCount -lt 2) {
    throw "transient failure on attempt $script:AttemptCount"
  }
  New-PrtgChannel -Channel 'Attempts' -Value $script:AttemptCount | Add-PrtgChannel
  Set-PrtgMessage 'recovered'
}
