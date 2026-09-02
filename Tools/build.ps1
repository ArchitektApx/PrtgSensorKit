# Builds the module from Source/ into Dist/ with ModuleBuilder, clearing the previous build
# first. The artifact tests, the fuzzer and the deploy script read the built module, so this has
# to run before any of them; tests.ps1 and coverage.ps1 dot-source it themselves.
#
# Usage (from the repo root):
#   ./tasks.ps1 build
#   pwsh -File Tools/build.ps1

. $(Join-Path $PSScriptRoot 'module_info.ps1')
$buildInfo = Get-ModuleInfo

Write-Host "--------------------------------"
Write-Host "Cleaning $($buildInfo.DistRoot)..."
Write-Host "--------------------------------"
# Guarded: on a fresh clone there is no Dist/ yet, and an unguarded Remove-Item would fail the
# very first build.
if (Test-Path -LiteralPath $buildInfo.DistRoot) {
  Remove-Item -LiteralPath $buildInfo.DistRoot -Recurse -Force
}
Write-Host "Dist directory cleaned successfully"

Write-Host "--------------------------------"
Write-Host "Building $($buildInfo.ModuleName) $($buildInfo.SemVer)..."
Write-Host "--------------------------------"
# Build-Module finds build.psd1 relative to the working directory, so pin it to the repo root
# instead of relying on where the caller happened to be.
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
