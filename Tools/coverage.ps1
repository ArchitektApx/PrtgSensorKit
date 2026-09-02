# Builds the module, then runs the Pester suite with code coverage over the SOURCE files and
# prints a percentage per file plus every missed command, so a gap traces to a source line.
#
# Usage (from the repo root):
#   ./tasks.ps1 coverage [-MinimumPercent 90]
#   pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File Tools/coverage.ps1
#
# The target is forced to Source: coverage over the source files is only meaningful when the
# behaviour tests executed those files. Coverage is per host, and the relaunch cmdlets always
# read as missed (they run in a child process). Compare hosts before calling a line untested.

param(
  # Exit non-zero when coverage falls below this percentage. 0 disables the gate.
  [double]$MinimumPercent = 0
)

# $global:, not a bare assignment, here and around the Pester call below: see the same note in
# tests.ps1. A script-scoped copy shadows the global for every test block on Windows
# PowerShell 5.1.
$previousErrorAction = $global:ErrorActionPreference
$targetVariable = $null
$previousTarget = $null

# Everything that can throw runs inside the try, so the finally restores the caller's session
# after a failed build or a missing Pester pin just as it does after a failed run. try/catch/
# finally is not a scope in PowerShell, so the dot-sourced helpers below still land in this
# script's scope.
try {
  $global:ErrorActionPreference = 'Stop'

  . (Join-Path $PSScriptRoot 'module_info.ps1')

  # Build first so a run can never verify a stale artifact.
  . (Join-Path $PSScriptRoot 'build.ps1')

  $info = Get-ModuleInfo
  # '*.ps1' leaves the source loader out, which is wanted: it is not part of the built module.
  $sourceFiles = @(Get-ChildItem -Path $info.SourceRoot -Recurse -Filter '*.ps1' -File |
      ForEach-Object { $_.FullName })
  if (-not $sourceFiles.Count) { throw "No *.ps1 files under '$($info.SourceRoot)'." }

  # Load exactly the pinned Pester and state which version resolved. Pester versions change how
  # many commands a coverage run analyzes, so a coverage number is meaningless without the version
  # that produced it.
  . (Join-Path $PSScriptRoot 'pester_pin.ps1')
  Import-PinnedPester

  . (Join-Path $PSScriptRoot 'test_suite_path.ps1')

  $c = New-PesterConfiguration
  $c.Run.Path = Resolve-TestSuitePath
  $c.Run.PassThru = $true
  $c.Output.Verbosity = 'None'
  $c.CodeCoverage.Enabled = $true
  $c.CodeCoverage.Path = $sourceFiles

  $targetVariable = Get-TestTargetVariableName
  $previousTarget = [Environment]::GetEnvironmentVariable($targetVariable)

  # 'Stop' above guards this script's own setup only. The run itself needs 'Continue', or a
  # Write-Error inside a test terminates the function instead of reaching the error stream the
  # test reads.
  $global:ErrorActionPreference = 'Continue'
  [Environment]::SetEnvironmentVariable($targetVariable, 'Source')
  $r = Invoke-Pester -Configuration $c
} finally {
  if ($targetVariable) { [Environment]::SetEnvironmentVariable($targetVariable, $previousTarget) }
  $global:ErrorActionPreference = $previousErrorAction
}

$cc = $r.CodeCoverage
$pct = if ($cc.CommandsAnalyzedCount) { $cc.CommandsExecutedCount / $cc.CommandsAnalyzedCount * 100 } else { 0 }

Write-Host ("Tests: {0} passed, {1} failed" -f $r.PassedCount, $r.FailedCount)
Write-Host ("Coverage: {0}/{1} = {2:N1}%" -f $cc.CommandsExecutedCount, $cc.CommandsAnalyzedCount, $pct)
Write-Host "A covered line is not a tested input: this counts commands executed, not cases tried."

$perFile = @{}
foreach ($pair in @(@{ Set = $cc.CommandsExecuted; Hit = $true }, @{ Set = $cc.CommandsMissed; Hit = $false })) {
  foreach ($command in @($pair.Set)) {
    $name = Split-Path -Leaf $command.File
    if (-not $perFile.ContainsKey($name)) { $perFile[$name] = @{ Executed = 0; Analyzed = 0 } }
    $perFile[$name].Analyzed++
    if ($pair.Hit) { $perFile[$name].Executed++ }
  }
}

Write-Host "--- Per file ---"
foreach ($name in ($perFile.Keys | Sort-Object)) {
  $file = $perFile[$name]
  Write-Host ("  {0,6:N1}%  {1,4}/{2,-4} {3}" -f (($file.Executed / $file.Analyzed) * 100), $file.Executed, $file.Analyzed, $name)
}

if ($cc.CommandsMissed.Count) {
  Write-Host "--- Missed ---"
  $cc.CommandsMissed | Sort-Object File, Line | ForEach-Object {
    Write-Host ("  {0}:{1}: {2}" -f (Split-Path -Leaf $_.File), $_.Line, $_.Command)
  }
}

# throw, not exit: tasks.ps1 dot-sources this file, and an 'exit' in a dot-sourced script ends
# only that script, so the gate would print its verdict and still report success to the caller.
if ($r.FailedCount -gt 0) {
  throw "Tests failed ($($r.FailedCount) failed / $($r.TotalCount) total)."
}
if ($pct -lt $MinimumPercent) {
  throw ("Coverage {0:N1}% is below the {1:N1}% threshold." -f $pct, $MinimumPercent)
}
