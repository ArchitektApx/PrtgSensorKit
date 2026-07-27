# Shared by every *.Tests.ps1: import the BUILT module from Dist (NOT the source).
# ModuleBuilder only exports the public functions in the built module, so tests must run
# against the build output, the same artifact a user installs.
function Get-BuiltPrtgManifest {
  $repo = Split-Path -Parent $PSScriptRoot
  $manifest = Get-ChildItem -Path (Join-Path $repo 'Dist') -Recurse -Filter 'PrtgSensorKit.psd1' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
  if (-not $manifest) {
    throw "Built module not found under Dist/. Run '.\tasks.ps1 build' (or Build-Module) first."
  }
  $manifest
}

function Import-BuiltPrtgModule {
  Import-Module (Get-BuiltPrtgManifest) -Force
}

# Single definition of the host check used by -Skip: expressions, which Pester evaluates at
# DISCOVERY time - so this must work before any BeforeAll runs, and on Windows PowerShell 5.1
# where $IsWindows does not exist.
function Test-OnWindowsHost {
  [OutputType([bool])]
  param()
  ($PSVersionTable.PSEdition -eq 'Desktop') -or [bool]$IsWindows
}

# Opens the exclusive lock handle the way the module does, to simulate a concurrent run.
# Shared by the state and cache test files so both always test the same lock semantics.
function Get-TestLockHandle([string]$LockFile) {
  [System.IO.FileStream]::new(
    $LockFile,
    [System.IO.FileMode]::OpenOrCreate,
    [System.IO.FileAccess]::ReadWrite,
    [System.IO.FileShare]::None)
}
