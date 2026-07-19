<#
.SYNOPSIS
  Query a JSON REST API and map fields to multiple channels.
.DESCRIPTION
  A common real-world sensor: call an HTTPS JSON endpoint and turn response fields into channels,
  with limits on the ones that matter. Enable TLS 1.2 first on Windows PowerShell 5.1, or the
  HTTPS request fails.
.NOTES
  Requires the PrtgSensorKit module installed on the probe.
#>
Import-Module PrtgSensorKit

# Windows PowerShell 5.1 does not negotiate TLS 1.2 by default.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Invoke-PrtgSensor {
  $data = Invoke-RestMethod -Uri 'https://api.example.com/v1/status' -TimeoutSec 15

  New-PrtgChannel -Channel 'Active Users' -Value ([int]$data.activeUsers)       | Add-PrtgChannel
  New-PrtgChannel -Channel 'Requests/min' -Value ([int]$data.requestsPerMinute) | Add-PrtgChannel

  New-PrtgChannel -Channel 'Error Rate %' -Value ([double]$data.errorRate) -Unit Percent -Float `
    -LimitMode $true -LimitMaxWarning 1 -LimitMaxError 5 |
    Add-PrtgChannel

  Set-PrtgMessage "API status: $($data.status)"
}
