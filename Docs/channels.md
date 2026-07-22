# 📊 Channels

`New-PrtgChannel` builds a single channel. Pipe each one to `Add-PrtgChannel`.
PRTG allows a **maximum of 50 channels** per sensor - adding a 51st throws.

```powershell
# Percentage with a float value and lower limits
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  New-PrtgChannel -Channel 'Disk Free %' -Value 25.0 -Unit Percent -Float `
    -LimitMinWarning 20 -LimitMinError 10 -LimitMode $true |
    Add-PrtgChannel

  # Response time with upper limits and a custom warning message
  New-PrtgChannel -Channel 'Response Time' -Value 120 -Unit TimeResponse `
    -LimitMaxWarning 100 -LimitMaxError 500 -LimitWarningMsg 'Slow' -LimitMode $true |
    Add-PrtgChannel

  # One channel per process
  Get-Process | ForEach-Object {
    New-PrtgChannel -Channel $_.ProcessName -Value $_.CPU -Float
  } | Add-PrtgChannel
}
```

Use `-Float` (or pass a decimal value) whenever the value is not a whole number, otherwise
PRTG may show `0`. See `Get-Help New-PrtgChannel -Full` for every unit, limit, and lookup
parameter.

> [!IMPORTANT]
> **Channel limits are a creation-time snapshot.** PRTG copies `Limit*` values into the
> channel settings only when the sensor is **first created**. Editing the limit values in
> the script later has no effect on an existing sensor - change the channel settings in
> the PRTG UI instead, or delete and recreate the sensor. The sensor doctor reminds you
> about this (check PSK0012).

See [02-multiple-channels-with-limits.ps1](../Examples/02-multiple-channels-with-limits.ps1),
[08-channel-types-showcase.ps1](../Examples/08-channel-types-showcase.ps1), and
[09-value-lookups-and-status.ps1](../Examples/09-value-lookups-and-status.ps1).
