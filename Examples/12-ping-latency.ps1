<#
.SYNOPSIS
  Ping a host: average latency and packet loss, with limits.
.DESCRIPTION
  Sends a few ICMP echoes and reports average round-trip time and packet loss as two channels,
  each with warning/error limits so PRTG alerts on its own. Target and count come from sensor
  parameters (set them in PRTG under "Parameters", e.g. -Target 10.0.0.1 -Count 5).
.NOTES
  Requires the PrtgSensorKit module installed on the probe.
#>
[CmdletBinding()]
param(
  [string]$Target = '8.8.8.8',
  [int]$Count = 4
)

Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  $replies  = @(Test-Connection -ComputerName $Target -Count $Count -ErrorAction SilentlyContinue)
  $received = $replies.Count
  $lossPct  = [math]::Round((($Count - $received) / $Count) * 100, 0)
  $avgMs    = 0
  if ($received) {
    $avgMs = [math]::Round(($replies | Measure-Object -Property ResponseTime -Average).Average, 0)
  }

  New-PrtgChannel -Channel 'Avg Latency' -Value $avgMs -Unit TimeResponse `
    -LimitMode $true -LimitMaxWarning 100 -LimitMaxError 300 |
    Add-PrtgChannel

  New-PrtgChannel -Channel 'Packet Loss' -Value $lossPct -Unit Percent `
    -LimitMode $true -LimitMaxWarning 1 -LimitMaxError 50 |
    Add-PrtgChannel

  Set-PrtgMessage "Ping $Target : $received/$Count replies"
}
