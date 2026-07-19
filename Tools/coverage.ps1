# Runs the Pester suite with code coverage against the BUILT module and prints missed lines.
# Launch with the injected flags so Get-PrtgRelaunchArgs' dedup branches are exercised:
#   pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Tools/coverage.ps1
param(
  [double]$MinimumPercent = 0
)

$repo = Split-Path -Parent $PSScriptRoot
$psm1 = (Get-ChildItem -Path (Join-Path $repo 'Dist') -Recurse -Filter 'PrtgSensorKit.psm1' -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
if (-not $psm1) { throw "Built module not found under Dist/. Build first." }

Remove-Module Pester -Force -ErrorAction SilentlyContinue
Import-Module Pester -MinimumVersion 5.0.0 -Force

$c = New-PesterConfiguration
$c.Run.Path = Join-Path $repo 'Tests'
$c.Run.PassThru = $true
$c.Output.Verbosity = 'None'
$c.CodeCoverage.Enabled = $true
$c.CodeCoverage.Path = $psm1

$r = Invoke-Pester -Configuration $c
$cc = $r.CodeCoverage
$pct = if ($cc.CommandsAnalyzedCount) { $cc.CommandsExecutedCount / $cc.CommandsAnalyzedCount * 100 } else { 0 }

Write-Host ("Tests: {0} passed, {1} failed" -f $r.PassedCount, $r.FailedCount)
Write-Host ("Coverage: {0}/{1} = {2:N1}%" -f $cc.CommandsExecutedCount, $cc.CommandsAnalyzedCount, $pct)
if ($cc.CommandsMissed.Count) {
  Write-Host "--- Missed ---"
  $cc.CommandsMissed | ForEach-Object { Write-Host ("  {0}: {1}" -f $_.Line, $_.Command) }
}

if ($r.FailedCount -gt 0) { exit 1 }
if ($pct -lt $MinimumPercent) {
  Write-Host ("Coverage {0:N1}% is below the {1:N1}% threshold." -f $pct, $MinimumPercent)
  exit 1
}
