# Clean Dist directory
Write-Host "--------------------------------"
Write-Host "Cleaning Dist directory..."
Write-Host "--------------------------------"
if (Test-Path -Path "Dist") {
  Remove-Item -Path "Dist" -Recurse -Force
}
Write-Host "Dist directory cleaned successfully"

# Build the module first: the tests import the BUILT module from Dist, so it must exist before
# they run.
Write-Host "--------------------------------"
Write-Host "Building module..."
Write-Host "--------------------------------"
try {
  Import-Module ModuleBuilder
  Build-Module
  Write-Host "Module built successfully"
} catch {
  Write-Host "Building module failed"
  throw "Building module failed"
}