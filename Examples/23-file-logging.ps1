<#
.SYNOPSIS
  Debugging a deployed sensor with -EnableLogging and Write-PrtgLog.
.DESCRIPTION
  PRTG shows a failing sensor as one flattened error line. With -EnableLogging the
  wrapper writes the whole lifecycle to a log file instead: sensor start, every retry,
  a success summary, and on failure the FULL error details (exception type, message,
  script line, stack trace). Write-PrtgLog adds your own entries in between.

  Every sensor run gets its own file, '<scriptname>_<timestamp>_<PID>.log', so a failing
  run is one self-contained file and concurrent runs never interleave. Old run files are
  pruned automatically (-MaxLogs, default 30). Without -LogPath the files land in
  %ProgramData%\PrtgSensorKit\Logs\<scriptname>\ - fully zero-config: just add the
  switch to a misbehaving deployed sensor.

  Logging can never affect the sensor result: Write-PrtgLog never throws, never writes
  to the output stream, and a full disk or bad path just drops the entry. Do not log
  secret values; nothing is redacted.
.NOTES
  Requires the PrtgSensorKit module installed on the probe.
#>
Import-Module PrtgSensorKit

# -LogPath keeps the logs next to the script (relative paths resolve against the script
# folder, not PRTG's unhelpful CWD); drop it to use the default folder above.
Invoke-PrtgSensor -EnableLogging -LogPath "$PSScriptRoot\Logs" -MaxLogs 10 {
  Write-PrtgLog 'collecting running services'
  $running = @(Get-Service | Where-Object Status -eq 'Running')
  Write-PrtgLog -Level Debug "found $($running.Count) running services"

  New-PrtgChannel -Channel 'Running Services' -Value $running.Count | Add-PrtgChannel
  Set-PrtgMessage 'service scan ok'
}

# Reading the latest run afterwards:
#   Get-ChildItem "$PSScriptRoot\Logs" | Sort-Object LastWriteTime -Descending |
#     Select-Object -First 1 | Get-Content
