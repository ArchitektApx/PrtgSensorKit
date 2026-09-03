<#
.SYNOPSIS
  PSScriptAnalyzer over Source/: style and correctness, then WinPS 5.1 / pwsh 7 compatibility.
.DESCRIPTION
  Any finding, warning or error, fails the run.
.EXAMPLE
  ./tasks.ps1 lint
.EXAMPLE
  pwsh -File Tools/lint.ps1
#>

# Without this, a broken import leaves Invoke-ScriptAnalyzer unresolved and the script prints
# "No errors." over empty results.
$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
  Write-Host "Installing PSScriptAnalyzer..."
  Install-Module PSScriptAnalyzer -Force -Scope CurrentUser -SkipPublisherCheck -ErrorAction Stop
}
# The gate is the command being callable: a session can list PSScriptAnalyzer yet not expose
# Invoke-ScriptAnalyzer. No -Force, which throws 'Assembly with same name is already loaded'.
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
# Warnings fail too, like the compatibility check below.
$findings = Invoke-ScriptAnalyzer -Path ./Source -Recurse -Severity Warning, Error
if ($findings) {
  $findings | Format-Table -AutoSize ScriptName, Line, Severity, RuleName | Out-String | Write-Host
  throw ("PSScriptAnalyzer reported $($findings.Count) finding(s). Fix them, or add a targeted " +
    "[Diagnostics.CodeAnalysis.SuppressMessageAttribute] with a Justification.")
}
Write-Host "No errors or warnings."

Write-Host "--------------------------------"
Write-Host "Checking compatibility (WinPS 5.1 / pwsh 7)..."
Write-Host "--------------------------------"
$compat = Invoke-ScriptAnalyzer -Path ./Source -Recurse -Settings ./Tools/PSScriptAnalyzer.psd1
if ($compat) {
  $compat | Format-Table -AutoSize ScriptName, Line, RuleName, Message | Out-String | Write-Host
  throw "PSScriptAnalyzer reported $($compat.Count) compatibility finding(s)."
}
Write-Host "Compatibility: clean (5.1 + pwsh 7)."
