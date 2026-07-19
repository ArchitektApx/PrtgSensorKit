<#
.SYNOPSIS
  Using a stored secret (API token) without plaintext in the sensor.
.DESCRIPTION
  Keep tokens/credentials out of the script and out of PRTG's config. Save the secret ONCE as the
  same Windows account the sensor runs as (DPAPI ties it to that account + machine), then read it
  at sensor time with Get-PrtgSecret.

  One-time setup on the probe, as the sensor's account (for Local System, run via 'PsExec -s'):
    Save-PrtgSecret -Name 'AcmeApi' -Secret (Read-Host -AsSecureString)
.NOTES
  Requires the PrtgSensorKit module installed on the probe. Windows only (DPAPI).
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  $token = Get-PrtgSecret -Name 'AcmeApi' -AsPlainText

  $headers = @{ Authorization = "Bearer $token" }
  $data = Invoke-RestMethod -Uri 'https://api.example.com/v1/metrics' -Headers $headers -TimeoutSec 15

  New-PrtgChannel -Channel 'Queue Depth' -Value ([int]$data.queueDepth) `
    -LimitMode $true -LimitMaxError 1000 |
    Add-PrtgChannel

  Set-PrtgMessage 'Fetched from Acme API'
}
