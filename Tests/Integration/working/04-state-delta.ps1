<#
.SYNOPSIS
  WORKING: state persisted between runs (dogfoods Save/Get-PrtgSensorState).
.DESCRIPTION
  Stores a UTC tick count each run and, on later runs, reports the elapsed time since the
  previous run as a channel. Expected PRTG result: FIRST scan is Up with message
  'baseline stored' and no delta channel; every scan after that is Up with an 'Elapsed ms'
  channel. Writes to %ProgramData%\PrtgSensorKit\State. Run the sensor at least twice to
  see the delta path. No network.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  $now = [DateTime]::UtcNow.Ticks
  $previous = Get-PrtgSensorState -Key 'Integration.Clock' -Latest -Default $null

  if ($null -ne $previous) {
    $elapsedMs = [math]::Round(($now - [int64]$previous) / 10000)
    New-PrtgChannel -Channel 'Elapsed ms' -Value $elapsedMs | Add-PrtgChannel
    Set-PrtgMessage 'delta since last run'
  } else {
    Set-PrtgMessage 'baseline stored, delta available next run'
  }

  Save-PrtgSensorState -Key 'Integration.Clock' -Value $now -MaxEntries 5
}
