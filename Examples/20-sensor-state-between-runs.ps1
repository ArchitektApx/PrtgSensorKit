<#
.SYNOPSIS
  Persisting data between sensor runs with Save/Get-PrtgSensorState.
.DESCRIPTION
  Computes a rate from an ever-growing counter by comparing it with the value stored on
  the previous run. Get-PrtgSensorState never throws for missing data, so the very first
  run simply falls back to -Default. -MaxAge protects against computing a rate across a
  long gap (probe reboot, paused sensor). State is stored under
  %ProgramData%\PrtgSensorKit\State and survives reboots.

  Sensor state is plain data on disk. SecureStrings/PSCredentials inside a value are
  still DPAPI-encrypted by Export-Clixml on Windows, but the state cmdlets make no
  promises about protection (no checks, no ACL hardening, no guard off Windows) - for
  secrets, prefer Save-PrtgSecret.
.NOTES
  Requires the PrtgSensorKit module installed on the probe.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  # An ever-growing counter from your data source (requests served, bytes processed, ...)
  $stats = Invoke-RestMethod -Uri 'https://api.example.com/stats' -TimeoutSec 10
  $totalRequests = [long]$stats.totalRequests

  # Previous run's counter and timestamp; entries come back newest first.
  $previous = Get-PrtgSensorState -Key 'MySensor.TotalRequests' -MaxAge (New-TimeSpan -Minutes 15)

  if ($null -ne $previous) {
    $prevEntry = $previous | Select-Object -First 1
    $seconds = ([DateTime]::UtcNow - $prevEntry.Timestamp.ToUniversalTime()).TotalSeconds
    $requestsPerSecond = [math]::Round(($totalRequests - $prevEntry.Value) / $seconds, 2)
    New-PrtgChannel -Channel 'Requests/s' -Value $requestsPerSecond -Float | Add-PrtgChannel
    Set-PrtgMessage 'ok'
  } else {
    # First run (or the stored value is too old to be meaningful): no rate yet.
    Set-PrtgMessage 'baseline stored, rate available on the next run'
  }

  New-PrtgChannel -Channel 'Total Requests' -Value $totalRequests | Add-PrtgChannel

  # Store the current counter for the next run; keep a small history only.
  Save-PrtgSensorState -Key 'MySensor.TotalRequests' -Value $totalRequests -MaxEntries 10
}
