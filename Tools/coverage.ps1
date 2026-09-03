<#
.SYNOPSIS
  Builds the module, then runs the Pester suite with code coverage over the source files.
.DESCRIPTION
  Prints a total, a percentage per file and every missed command as '<file>:<line>: <command>'.
  The target is forced to Source, since coverage over the source files only counts when the
  behaviour tests executed those files. Coverage is per host, and the relaunch cmdlets always
  read as missed because they run in a child process.
.PARAMETER MinimumPercent
  Exit non-zero when coverage falls below this percentage. 0 disables the gate.
#>

param(
  [double]$MinimumPercent = 0
)

# $global:, not a bare assignment, here and around the Pester call below: on Windows PowerShell
# 5.1 a script-scoped copy sits in the scope chain of every test block and shadows the global.
$previousErrorAction = $global:ErrorActionPreference
$targetVariable = $null
$previousTarget = $null

try {
  $global:ErrorActionPreference = 'Stop'

  . (Join-Path $PSScriptRoot 'module_info.ps1')

  # Build first so a run can never verify a stale artifact.
  . (Join-Path $PSScriptRoot 'build.ps1')

  $info = Get-ModuleInfo
  # '*.ps1' leaves the source loader out; it is not part of the built module.
  $sourceFiles = @(Get-ChildItem -Path $info.SourceRoot -Recurse -Filter '*.ps1' -File |
      ForEach-Object { $_.FullName })
  if (-not $sourceFiles.Count) { throw "No *.ps1 files under '$($info.SourceRoot)'." }

  # Only the pinned Pester runs the suite; the pin lives in pester_pin.ps1.
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

  # 'Stop' guards setup only; the run needs 'Continue', or a Write-Error inside a test
  # terminates the function.
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

# tasks.ps1 dot-sources this file, and an 'exit' in a dot-sourced script ends only that script,
# so the gate would still report success to the caller.
if ($r.FailedCount -gt 0) {
  throw "Tests failed ($($r.FailedCount) failed / $($r.TotalCount) total)."
}
if ($pct -lt $MinimumPercent) {
  throw ("Coverage {0:N1}% is below the {1:N1}% threshold." -f $pct, $MinimumPercent)
}
