<#
.SYNOPSIS
  Difference mode: chart the delta of an ever-increasing counter.
.DESCRIPTION
  -Mode Difference tells PRTG to display the change between runs instead of the absolute value.
  Feed it a raw cumulative counter (bytes received, requests served, ...) and PRTG does the
  subtraction, so you get a per-interval rate. Here: bytes received on the busiest interface.
.NOTES
  Requires the PrtgSensorKit module installed on the probe. Windows (uses Get-NetAdapterStatistics).
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  $busiest = Get-NetAdapterStatistics |
    Sort-Object ReceivedBytes -Descending |
    Select-Object -First 1

  New-PrtgChannel -Channel 'Bytes Received' -Value ([int64]$busiest.ReceivedBytes) `
    -Unit BytesBandwidth -Mode Difference -SpeedSize Byte -SpeedTime Second |
    Add-PrtgChannel

  Set-PrtgMessage "Throughput delta on $($busiest.Name)"
}
