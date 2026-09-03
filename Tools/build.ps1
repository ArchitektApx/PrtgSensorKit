<#
.SYNOPSIS
  Clears Dist/ and builds the module from Source/ with ModuleBuilder.
.DESCRIPTION
  The artifact tests, the fuzzer and the deploy script read the built module, so this runs
  before any of them. tests.ps1 and coverage.ps1 dot-source it themselves.
.EXAMPLE
  ./tasks.ps1 build
.EXAMPLE
  pwsh -File Tools/build.ps1
#>

. $(Join-Path $PSScriptRoot 'module_info.ps1')
$buildInfo = Get-ModuleInfo

Write-Host "--------------------------------"
Write-Host "Cleaning $($buildInfo.DistRoot)..."
Write-Host "--------------------------------"
if (Test-Path -LiteralPath $buildInfo.DistRoot) {
  Remove-Item -LiteralPath $buildInfo.DistRoot -Recurse -Force
}
Write-Host "Dist directory cleaned successfully"

Write-Host "--------------------------------"
Write-Host "Building $($buildInfo.ModuleName) $($buildInfo.SemVer)..."
Write-Host "--------------------------------"
# Build-Module finds build.psd1 relative to the working directory.
Push-Location $buildInfo.RepoRoot
try {
  Import-Module ModuleBuilder
  Build-Module
  Write-Host "Module built successfully"
} catch {
  Write-Host "Building module failed"
  throw "Building module failed. ($($_.Exception.Message))"
} finally {
  Pop-Location
}
