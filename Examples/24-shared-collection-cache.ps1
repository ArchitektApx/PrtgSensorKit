<#
.SYNOPSIS
  Sharing one expensive call across several sensors with Use-PrtgCachedResult.
.DESCRIPTION
  PRTG launches every sensor as its own process each interval, so eight sensors reading
  the same API mean eight identical calls. Use-PrtgCachedResult makes them share one:
  the first sensor to find the cache stale runs the block and stores the result; every
  other sensor gets the stored value. Sensors firing at the same moment wait briefly for
  the first one's fetch and read its result - exactly one fetch per expiry.

  Deploy this script as several sensors (or several scripts sharing the same -Key), each
  charting a different slice of the same response, with independent intervals, limits,
  and notifications per metric.

  Rules of thumb:
  - -MaxAge slightly below the scan interval (55 s for a 60 s interval), otherwise
    every interval refetches.
  - -TimeoutSeconds (default 30) above the slowest expected fetch.
  - Treat the result as plain data: it keeps its properties but not its methods. Live
    handles (sockets, sessions) cannot be cached.
  - Cache entries are ordinary sensor state: inspect with Get-PrtgSensorState, clear
    with Clear-PrtgSensorState.
.NOTES
  Requires the PrtgSensorKit module installed on the probe.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor -ForceModernTls {
  $stats = Use-PrtgCachedResult -Key 'AcmeApi.Stats' -MaxAge (New-TimeSpan -Seconds 55) {
    # The expensive part: runs once per interval machine-wide, no matter how many
    # sensors share the key. A thrown error here propagates as the sensor error and
    # keeps any stale entry for the next run to retry.
    Invoke-RestMethod -Uri 'https://api.example.com/stats' -TimeoutSec 10
  }

  New-PrtgChannel -Channel 'Queue Depth' -Value $stats.queueDepth | Add-PrtgChannel
  New-PrtgChannel -Channel 'Active Workers' -Value $stats.workers | Add-PrtgChannel
  Set-PrtgMessage 'ok (collection shared across sensors)'
}
