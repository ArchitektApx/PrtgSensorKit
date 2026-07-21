<#
.SYNOPSIS
  Debugging a sensor with -DryRun.
.DESCRIPTION
  With -DryRun, Invoke-PrtgSensor returns the sensor result as a PowerShell object instead
  of the PRTG JSON string, so you can capture it in a variable and inspect channels and
  message directly. Errors are rethrown with full details instead of being flattened into
  a PRTG error response. Run this script in a normal console:

    $result = .\18-dry-run-debugging.ps1
    $result.prtg.result | Format-Table
    $result.prtg.text

  Remove -DryRun before deploying the sensor to PRTG - a deployed dry run would not emit
  valid PRTG JSON. Invoke-PrtgSensorDoctor flags a leftover -DryRun for you.
.NOTES
  Requires the PrtgSensorKit module installed on the probe.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor -DryRun {
  $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -gt 0 }

  foreach ($drive in $drives) {
    $usedPct = [math]::Round($drive.Used / ($drive.Used + $drive.Free) * 100, 1)
    New-PrtgChannel -Channel "Used % $($drive.Name)" -Value $usedPct -Unit Percent -Float | Add-PrtgChannel
  }

  Set-PrtgMessage "$(@($drives).Count) volumes checked"
}
