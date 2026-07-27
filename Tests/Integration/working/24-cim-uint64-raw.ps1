<#
.SYNOPSIS
  WORKING: raw CIM UInt64 values passed straight to New-PrtgChannel (1.3.0 change).
.DESCRIPTION
  Before 1.3.0, -Value accepted only int, int64, float, double, and decimal, so every UInt64
  that CIM and WMI return - Win32_LogicalDisk.FreeSpace, Win32_OperatingSystem
  .FreePhysicalMemory, Get-Volume.SizeRemaining - was REJECTED unless the caller cast it. The
  usual workaround was [math]::Round(...), which happens to return a double; that is what
  working/02-multichannel-with-limits.ps1 does.

  From 1.3.0 every built-in numeric type is accepted, so CIM values go straight in. This
  sensor deliberately does NO casting anywhere.

  Expected PRTG result: Up, one 'Free <drive>' and one 'Size <drive>' channel per fixed
  volume in bytes, plus a 'Large Value' channel, message naming the volume count.

  WORTH CHECKING IN THE PRTG UI, because only a real probe can show it: 'Large Value' is
  9007199254740993, which is 2^53 + 1. The module emits that exact integer (integers are not
  cast on the way out, so they are not rounded). If PRTG DISPLAYS 9007199254740992 instead,
  that is PRTG's own JSON parser using a double, not a module bug - but it is worth recording,
  because it tells you the practical ceiling for byte counters on very large storage. Note
  the value down either way.

  Do not add -Float to these channels: it converts to double and would reintroduce exactly
  the precision loss this sensor exists to check.
.NOTES
  Requires the PrtgSensorKit module installed on the probe. Uses only local CIM data, no network.
  Expected Doctor verdict: all Pass.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  $disks = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 3' | Where-Object { $_.Size -gt 0 })

  foreach ($disk in $disks) {
    # $disk.FreeSpace and $disk.Size are [UInt64]. No cast, no rounding.
    New-PrtgChannel -Channel "Free $($disk.DeviceID)" -Value $disk.FreeSpace -Unit BytesDisk -VolumeSize Giga |
      Add-PrtgChannel
    New-PrtgChannel -Channel "Size $($disk.DeviceID)" -Value $disk.Size -Unit BytesDisk -VolumeSize Giga |
      Add-PrtgChannel
  }

  # 2^53 + 1: the smallest integer a double cannot represent exactly.
  New-PrtgChannel -Channel 'Large Value' -Value ([uint64]9007199254740993) -Unit BytesDisk -VolumeSize Tera |
    Add-PrtgChannel

  Set-PrtgMessage "$($disks.Count) fixed volume(s), raw UInt64 values"
}
