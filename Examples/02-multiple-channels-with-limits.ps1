<#
.SYNOPSIS
  Multiple channels built in a loop, with warning/error limits.
.DESCRIPTION
  Reports free space per fixed disk as its own channel and attaches PRTG limits so the sensor
  turns yellow/red on its own. Shows the common "one channel per discovered item" loop pattern
  and per-channel LimitMode / LimitMinWarning / LimitMinError / limit messages.
.NOTES
  Requires the PrtgSensorKit module installed on the probe. Windows (uses Win32_LogicalDisk).
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  # DriveType 3 = local fixed disk
  foreach ($disk in Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType = 3') {
    $freePct = [math]::Round($disk.FreeSpace / $disk.Size * 100, 1)

    New-PrtgChannel -Channel "Free % $($disk.DeviceID)" -Value $freePct -Unit Percent -Float `
      -LimitMode $true -LimitMinWarning 15 -LimitMinError 5 `
      -LimitWarningMsg 'Low disk space' -LimitErrorMsg 'Critical disk space' |
      Add-PrtgChannel
  }

  Set-PrtgMessage 'Free space per fixed disk'
}
