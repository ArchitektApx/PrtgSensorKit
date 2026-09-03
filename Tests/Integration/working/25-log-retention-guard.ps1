<#
.SYNOPSIS
  WORKING: log retention never deletes files this module did not create.
.DESCRIPTION
  Zero-config logging (no -LogPath) with -MaxLogs 1, so the retention sweep runs on every
  single scan instead of only after 30 runs. Before the sensor block, two decoy files are
  planted in this script's own default log folder and back-dated to 2020 so any sweep
  sorting by LastWriteTime targets them FIRST:

    unrelated-application.log            - a foreign application log
    <scriptname>_extra_<stamp>_<pid>.log - a run file belonging to a DIFFERENT script whose
                                           name happens to start with this one's

  Expected PRTG result: Up on every scan, 'Foreign Logs Intact' = 2 and 'Own Run Files' = 1.
  If either decoy is gone the sensor goes Down and names the file, so data loss in someone
  else's log folder is loud rather than silent.

  'Own Run Files' = 1 is the other half: the fix must not "work" by disabling retention.

  Self-seeding, so there is no manual setup - but it deliberately LEAVES the decoys behind
  (they have to survive to be tested). Remove them when done, see Integration/README.md.
  No network.
#>
Import-Module PrtgSensorKit

# Seeded BEFORE Invoke-PrtgSensor: the lifecycle 'sensor start' entry is this run's first
# Write-PrtgLog, and that call creates the run file and prunes the folder.
$sensorName = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$logDir = if (Test-Path Env:\ProgramData) { Join-Path $env:ProgramData "PrtgSensorKit\Logs\$sensorName" }
          else { Join-Path ([System.IO.Path]::GetTempPath()) "PrtgSensorKit/Logs/$sensorName" }
if (-not (Test-Path -LiteralPath $logDir)) { [void] (New-Item -ItemType Directory -Path $logDir -Force) }

$decoys = @{
  'unrelated-application.log'                = 'not written by PrtgSensorKit'
  "${sensorName}_extra_20200101-000000_4242.log" = 'run file of a DIFFERENT script'
}
foreach ($decoy in $decoys.GetEnumerator()) {
  $decoyPath = Join-Path $logDir $decoy.Key
  if (-not (Test-Path -LiteralPath $decoyPath)) {
    Set-Content -LiteralPath $decoyPath -Value $decoy.Value
  }
  # Re-stamped every run: the sweep is ordered by LastWriteTime, so the decoys must stay the
  # oldest files in the folder for the test to mean anything.
  (Get-Item -LiteralPath $decoyPath).LastWriteTime = [DateTime]'2020-01-01'
}

Invoke-PrtgSensor -EnableLogging -MaxLogs 1 {
  Write-PrtgLog "verifying retention left $($decoys.Count) foreign file(s) in '$logDir' alone"

  $missing = @($decoys.Keys | Where-Object { -not (Test-Path -LiteralPath (Join-Path $logDir $_)) })
  if ($missing.Count -gt 0) {
    throw "log retention deleted $($missing.Count) file(s) it did not create: $($missing -join ', ')"
  }

  $ownPattern = '^' + [regex]::Escape($sensorName) + '_\d{8}-\d{6}_\d+\.log$'
  $ownRunFiles = @(Get-ChildItem -LiteralPath $logDir -Filter '*.log' -File |
    Where-Object { $_.Name -match $ownPattern })

  New-PrtgChannel -Channel 'Foreign Logs Intact' -Value $decoys.Count `
    -LimitMinError $decoys.Count -LimitMode $true | Add-PrtgChannel
  New-PrtgChannel -Channel 'Own Run Files' -Value $ownRunFiles.Count `
    -LimitMaxError 3 -LimitMode $true | Add-PrtgChannel

  Set-PrtgMessage "foreign logs intact, $($ownRunFiles.Count) own run file(s) kept"
}
