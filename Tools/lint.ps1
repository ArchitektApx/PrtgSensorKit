# Static analysis: general style/correctness (fail on Error) + cross-version/platform
# compatibility (fail on any finding). Run from the repo root (via tasks.ps1).

# Fail loudly: without this, a broken import leaves Invoke-ScriptAnalyzer unresolved and
# the script would happily print "No errors." over empty results.
$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
  Write-Host "Installing PSScriptAnalyzer..."
  Install-Module PSScriptAnalyzer -Force -Scope CurrentUser -SkipPublisherCheck -ErrorAction Stop
}
# Gate on the COMMAND being callable, not on the module being listed: a session can have
# PSScriptAnalyzer in Get-Module yet not expose Invoke-ScriptAnalyzer (a half-finished
# import, or an editor that loaded it into another state), and a module-presence check
# would then skip the repairing import and fail at the first Invoke-ScriptAnalyzer call.
# No -Force: on an already-working module it would throw 'Assembly with same name is
# already loaded'; when the command is missing, a plain Import-Module brings it back.
if (-not (Get-Command Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue)) {
  Import-Module PSScriptAnalyzer
}

# Warn when the loaded PSScriptAnalyzer is older than the newest installed version; the
# in-session assembly cannot be swapped out, so its rules may differ from a clean run.
$loadedPssa = (Get-Command Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue).Module
if ($loadedPssa) {
  $newestPssa = Get-Module -ListAvailable PSScriptAnalyzer |
    Sort-Object Version -Descending | Select-Object -First 1
  if ($newestPssa -and $loadedPssa.Version -lt $newestPssa.Version) {
    Write-Warning ("lint: session has PSScriptAnalyzer $($loadedPssa.Version) loaded but $($newestPssa.Version) is installed. " +
      "Results may differ from a clean run; start a fresh PowerShell session to lint with the newer version.")
  }
}

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
