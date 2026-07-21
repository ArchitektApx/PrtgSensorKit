<#
.SYNOPSIS
  Retrying a flaky data source with -RetryCount.
.DESCRIPTION
  -RetryCount re-runs the script block when it throws, up to N additional attempts, with an
  optional -RetryDelaySeconds pause between attempts. Output state is cleared before every
  attempt, so a failed partial attempt never leaks channels into the result.

  When the block succeeds after retries, the sensor message gets a suffix:
    'API healthy (1/2 retries attempted)'
  When every attempt fails, the error text is prefixed:
    'unsuccessful after 2 retries: <error details>'

  Keep (RetryCount + 1) * (block runtime + delay) below the PRTG sensor timeout, or PRTG
  kills the sensor before the retries finish.
.NOTES
  Requires the PrtgSensorKit module installed on the probe.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor -RetryCount 2 -RetryDelaySeconds 5 {
  # A momentarily unreachable endpoint throws here; the block is then retried.
  $health = Invoke-RestMethod -Uri 'https://api.example.com/health' -TimeoutSec 10

  New-PrtgChannel -Channel 'Response Time' -Value $health.latencyMs -Unit TimeResponse `
    -LimitMaxWarning 500 -LimitMaxError 2000 -LimitMode $true | Add-PrtgChannel
  New-PrtgChannel -Channel 'Queue Length' -Value $health.queueLength | Add-PrtgChannel

  Set-PrtgMessage 'API healthy'
}
