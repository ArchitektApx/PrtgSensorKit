# Static analysis: general style/correctness (fail on Error) + cross-version/platform
# compatibility (fail on any finding). Run from the repo root (via tasks.ps1).

if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
  Write-Host "Installing PSScriptAnalyzer..."
  Install-Module PSScriptAnalyzer -Force -Scope CurrentUser -SkipPublisherCheck -ErrorAction Stop
}
Import-Module PSScriptAnalyzer -Force

Write-Host "--------------------------------"
Write-Host "Analyzing (style / correctness)..."
Write-Host "--------------------------------"
$findings = Invoke-ScriptAnalyzer -Path ./Source -Recurse -Severity Warning, Error
if ($findings) { $findings | Format-Table -AutoSize ScriptName, Line, Severity, RuleName | Out-String | Write-Host }
$errors = @($findings | Where-Object Severity -eq 'Error')
if ($errors.Count) { throw "PSScriptAnalyzer reported $($errors.Count) error(s)." }
Write-Host "No errors."

Write-Host "--------------------------------"
Write-Host "Checking compatibility (WinPS 5.1 / pwsh 7)..."
Write-Host "--------------------------------"
$compat = Invoke-ScriptAnalyzer -Path ./Source -Recurse -Settings ./Tools/PSScriptAnalyzer.psd1
if ($compat) {
  $compat | Format-Table -AutoSize ScriptName, Line, RuleName, Message | Out-String | Write-Host
  throw "PSScriptAnalyzer reported $($compat.Count) compatibility finding(s)."
}
Write-Host "Compatibility: clean (5.1 + pwsh 7)."
