# Runs the Pester suite against the BUILT module in Dist/ (build first). Throws on any test
# failure, so it can gate a release or a CI job.
#
# Usage (from the repo root):
#   ./tasks.ps1 test
#   pwsh -File Tools/tests.ps1 [-PassThru]

param(
  # Emit the Pester result object as well, for a caller that wants the counts.
  [switch]$PassThru
)

# Load exactly the pinned Pester and state which version resolved, so two runs can be compared.
# A floor would let the run use whatever arrived on the host first, including the built-in
# Pester 3.4 on Windows PowerShell 5.1, which has no New-PesterConfiguration and would silently
# skip the whole suite.
. (Join-Path $PSScriptRoot 'pester_pin.ps1')
Import-PinnedPester

# Join-Path's 3-argument form is PowerShell 7+ only; nest for Windows PowerShell 5.1.
$testPath = Join-Path (Join-Path $PSScriptRoot '..') 'Tests' | Resolve-Path -ErrorAction SilentlyContinue
if (-not $testPath -or -not (Get-ChildItem -Path $testPath -Filter '*.Tests.ps1' -Recurse -ErrorAction SilentlyContinue)) {
  throw "No *.Tests.ps1 files found under Tests/. Refusing to report success on an empty run."
}

$config = New-PesterConfiguration
$config.Run.Path = $testPath.Path
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Detailed'
$result = Invoke-Pester -Configuration $config

if (-not $result -or $result.FailedCount -gt 0) {
  throw "Tests failed ($($result.FailedCount) failed / $($result.TotalCount) total)."
}

if ($PassThru.IsPresent) {
  $result
}
