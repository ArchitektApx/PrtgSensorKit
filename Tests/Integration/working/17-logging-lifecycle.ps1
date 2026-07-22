<#
.SYNOPSIS
  WORKING: lifecycle logging to the default log folder (dogfoods -EnableLogging).
.DESCRIPTION
  Zero-config logging: no -LogPath, so the run files land in
  %ProgramData%\PrtgSensorKit\Logs\<scriptname>\. Expected PRTG result: Up with an
  'Uptime Ticks' channel. Validate on the probe that each scan adds one new
  '<scriptname>_<timestamp>_<PID>.log' file containing the 'sensor start' line, the
  custom 'collecting tick count' entry, and the 'sensor ok: 1 channels, ...' summary,
  and that no more than 30 files accumulate (default -MaxLogs pruning). Because the
  probe runs the sensor as Local System, this also validates that the default folder is
  writable under the real sensor account. No network.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor -EnableLogging {
  Write-PrtgLog 'collecting tick count'
  # TickCount, not TickCount64: the latter does not exist on .NET Framework (5.1 host).
  New-PrtgChannel -Channel 'Uptime Ticks' -Value ([Environment]::TickCount) | Add-PrtgChannel
  Set-PrtgMessage 'logged run'
}
