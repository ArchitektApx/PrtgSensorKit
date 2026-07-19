param(
  [switch]$PassThru
)

# Force Pester v5+. On Windows PowerShell 5.1 the built-in Pester 3.4 would otherwise load and
# New-PesterConfiguration would not exist, silently skipping the whole suite.
Remove-Module Pester -Force -ErrorAction SilentlyContinue
Import-Module Pester -MinimumVersion 5.0.0 -Force

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
