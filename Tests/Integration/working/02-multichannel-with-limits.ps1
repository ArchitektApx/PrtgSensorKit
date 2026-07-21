<#
.SYNOPSIS
  WORKING: multiple channels with limits, built in a loop.
.DESCRIPTION
  One channel per fixed disk with warning/error limits. Expected PRTG result: Up, N
  channels (one per volume with a size), message names the volume count. Uses only local
  CIM data, no network.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  $disks = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 3' | Where-Object { $_.Size -gt 0 })
  foreach ($disk in $disks) {
    $freePct = [math]::Round($disk.FreeSpace / $disk.Size * 100, 1)
    New-PrtgChannel -Channel "Free % $($disk.DeviceID)" -Value $freePct -Unit Percent -Float `
      -LimitMinWarning 15 -LimitMinError 5 -LimitMode $true | Add-PrtgChannel
  }
  Set-PrtgMessage "$($disks.Count) fixed volume(s) checked"
}
