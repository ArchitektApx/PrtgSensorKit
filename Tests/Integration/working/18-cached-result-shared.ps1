<#
.SYNOPSIS
  WORKING: one collection shared across sensors (dogfoods Use-PrtgCachedResult).
.DESCRIPTION
  The block stores a collection timestamp; 'Collection Age' reports how old the cached
  collection is. Deploy this script as TWO OR MORE sensors on the same probe with a
  60 s interval. Expected PRTG result: all sensors Up and showing the SAME age
  progression (0-60 s sawtooth), because only one of them refreshes the cache per
  expiry; the 2-second collection pause is paid once per interval machine-wide, not
  once per sensor. Writes to %ProgramData%\PrtgSensorKit\State. No network.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  $collected = Use-PrtgCachedResult -Key 'Integration.SharedClock' -MaxAge (New-TimeSpan -Seconds 55) {
    # Stand-in for the expensive shared collection (API/SQL/WMI sweep).
    Start-Sleep -Seconds 2
    [DateTime]::UtcNow.ToString('o')
  }

  $collectedUtc = [DateTime]::Parse($collected, [System.Globalization.CultureInfo]::InvariantCulture,
    [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
  $ageSeconds = [math]::Round(([DateTime]::UtcNow - $collectedUtc).TotalSeconds, 1)
  New-PrtgChannel -Channel 'Collection Age' -Value $ageSeconds -Float | Add-PrtgChannel
  Set-PrtgMessage "collection from $collected"
}
