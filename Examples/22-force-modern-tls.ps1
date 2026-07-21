<#
.SYNOPSIS
  Web requests on Windows PowerShell 5.1 with -ForceModernTls.
.DESCRIPTION
  PRTG runs custom sensors in Windows PowerShell 5.1, whose default protocol set can lack
  TLS 1.2 - HTTPS requests against modern endpoints then fail with
  'The underlying connection was closed'. -ForceModernTls switches the process to
  TLS 1.2 (plus TLS 1.3 when the OS supports it) before the block runs, so no manual
  [Net.ServicePointManager] one-liner is needed.
.NOTES
  Requires the PrtgSensorKit module installed on the probe.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor -ForceModernTls {
  $status = Invoke-RestMethod -Uri 'https://api.example.com/status' -TimeoutSec 10

  New-PrtgChannel -Channel 'Active Sessions' -Value $status.sessions | Add-PrtgChannel
  New-PrtgChannel -Channel 'Error Rate' -Value $status.errorRate -Unit Percent -Float `
    -LimitMaxWarning 1 -LimitMaxError 5 -LimitMode $true | Add-PrtgChannel

  Set-PrtgMessage $status.summary
}
