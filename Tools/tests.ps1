# Builds the module, then runs the Pester suite. The behaviour tests import the tree -Target
# names; the artifact tests under Tests/Artifact always read the build this script just made.
# Throws on any test failure, so it can gate a release or a CI job.
#
# Usage (from the repo root):
#   ./tasks.ps1 test
#   ./tasks.ps1 test -Target Dist -Path Tests/Artifact
#   pwsh -File Tools/tests.ps1 [-Target Source|Dist] [-Path <tests>] [-PassThru]

param(
  # Which tree the behaviour suite imports. The artifact tests always read the build output.
  [ValidateSet('Source', 'Dist')]
  [string]$Target = 'Source',

  # Which tests to run, a file or a directory. Defaults to the whole test directory.
  [string]$Path,

  # Emit the Pester result object as well, for a caller that wants the counts.
  [switch]$PassThru
)

# $global:, not a bare assignment, here and around the Pester call below. A bare assignment
# creates a script-scoped copy of the preference, and on Windows PowerShell 5.1 that copy sits in
# the scope chain of every test block and shadows the global. Invoke-PrtgSensor sets the global
# to 'Stop' for the block it runs, so three of its tests would read the shadowed 'Continue'.
$previousErrorAction = $global:ErrorActionPreference
$targetVariable = $null
$previousTarget = $null

# Everything that can throw runs inside the try, so the finally restores the caller's session
# after a failed build, a missing Pester pin or an unresolvable -Path just as it does after a
# failed run. try/catch/finally is not a scope in PowerShell, so the dot-sourced helpers below
# still land in this script's scope.
try {
  $global:ErrorActionPreference = 'Stop'

  . (Join-Path $PSScriptRoot 'module_info.ps1')

  # Build first so a run can never verify a stale artifact.
  . (Join-Path $PSScriptRoot 'build.ps1')

  # Load exactly the pinned Pester and state which version resolved, so two runs can be compared.
  # A floor would let the run use whatever arrived on the host first, including the built-in
  # Pester 3.4 on Windows PowerShell 5.1, which has no New-PesterConfiguration and would silently
  # skip the whole suite.
  . (Join-Path $PSScriptRoot 'pester_pin.ps1')
  Import-PinnedPester

  . (Join-Path $PSScriptRoot 'test_suite_path.ps1')
  $testPath = Resolve-TestSuitePath -Path $Path

  $config = New-PesterConfiguration
  $config.Run.Path = $testPath
  # Always PassThru: the result object is how this script decides its own exit status. Run.Exit is
  # deliberately left off, because it would kill the caller's whole session rather than letting the
  # throw below propagate.
  $config.Run.PassThru = $true
  $config.Output.Verbosity = 'Detailed'

  $targetVariable = Get-TestTargetVariableName
  $previousTarget = [Environment]::GetEnvironmentVariable($targetVariable)

  # 'Stop' guards this script's own setup only. The run itself needs 'Continue', or a Write-Error
  # inside a test terminates the function instead of reaching the error stream the test reads;
  # Tests/Harness.Tests.ps1 is the regression test for that.
  $global:ErrorActionPreference = 'Continue'
  [Environment]::SetEnvironmentVariable($targetVariable, $Target)
  $result = Invoke-Pester -Configuration $config
} finally {
  if ($targetVariable) { [Environment]::SetEnvironmentVariable($targetVariable, $previousTarget) }
  $global:ErrorActionPreference = $previousErrorAction
}

if (-not $result -or $result.FailedCount -gt 0) {
  throw "Tests failed ($($result.FailedCount) failed / $($result.TotalCount) total)."
}

if ($PassThru.IsPresent) {
  $result
}
