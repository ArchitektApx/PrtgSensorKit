<#
.SYNOPSIS
  Accepting parameters from the PRTG sensor settings.
.DESCRIPTION
  Declare a param() block at the top of the script. In PRTG, set the values under the sensor's
  "Parameters" field, e.g.  -WarnAbove 70 -ErrorAbove 90. The bound values are visible inside the
  Invoke-PrtgSensor block because the block shares the script's scope.
.NOTES
  Requires the PrtgSensorKit module installed on the probe.
#>
[CmdletBinding()]
param(
  [int]$WarnAbove = 80,
  [int]$ErrorAbove = 95
)

Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  $cpu = Get-Random -Minimum 1 -Maximum 100

  New-PrtgChannel -Channel 'CPU' -Value $cpu -Unit Percent `
    -LimitMode $true -LimitMaxWarning $WarnAbove -LimitMaxError $ErrorAbove |
    Add-PrtgChannel

  Set-PrtgMessage "CPU at $cpu% (warn > $WarnAbove, error > $ErrorAbove)"
}
