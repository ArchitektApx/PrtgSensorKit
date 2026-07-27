# Builds the module from Source/ into Dist/ with ModuleBuilder, clearing the previous build
# first. The tests, the fuzzer, and the deploy script all import the BUILT module, so this has
# to run before any of them.
#
# Usage (from the repo root):
#   ./tasks.ps1 build
#   pwsh -File Tools/build.ps1

Write-Host "--------------------------------"
Write-Host "Cleaning Dist directory..."
Write-Host "--------------------------------"
if (Test-Path -Path "Dist") {
  Remove-Item -Path "Dist" -Recurse -Force
}
Write-Host "Dist directory cleaned successfully"

Write-Host "--------------------------------"
Write-Host "Building module..."
Write-Host "--------------------------------"
try {
  Import-Module ModuleBuilder
  Build-Module
  Write-Host "Module built successfully"
} catch {
  Write-Host "Building module failed"
  throw "Building module failed. ($($_.Exception.Message))"
}
