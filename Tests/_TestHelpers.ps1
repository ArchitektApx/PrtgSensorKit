# Shared by every *.Tests.ps1: target selection, import helpers and fixtures. Dot-sourced in
# BeforeAll, and at top level where a -Skip: expression needs it.
. (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'Tools') 'module_info.ps1')

# 'Source' or 'Dist', held in an environment variable so it reaches both discovery-time -Skip:
# expressions and the child PowerShell some tests spawn. Set by ./tasks.ps1 test -Target.
function Get-TestTarget {
  [OutputType([string])]
  param()
  $value = [Environment]::GetEnvironmentVariable((Get-TestTargetVariableName))
  if ($value -eq 'Dist') { 'Dist' } else { 'Source' }
}

# The manifest the behaviour tests run against. Also what a test that spawns a child PowerShell
# passes to that child, so the child tests the same tree.
function Get-ModuleUnderTestPath {
  [OutputType([string])]
  param()
  if ((Get-TestTarget) -eq 'Dist') { Get-BuiltManifestPath } else { (Get-ModuleInfo).SourceManifest }
}

function Import-ModuleUnderTest {
  Import-OneModule -Manifest (Get-ModuleUnderTestPath)
}

# For the artifact tests and the fuzzer: the build, whatever the target.
function Import-BuiltModule {
  Import-OneModule -Manifest (Get-BuiltManifestPath)
}

# Unload by name first: Import-Module -Force loads a second module beside one imported from
# another path, leaving two modules of one name with doubled exports.
function Import-OneModule {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Manifest
  )
  Remove-Module -Name (Get-ModuleInfo).ModuleName -Force -ErrorAction SilentlyContinue
  Import-Module $Manifest -Force
}

# $null when the build is fresh, otherwise the sentence the artifact test fails with. Catches
# Pester run by hand against yesterday's build; ./tasks.ps1 test builds first anyway.
function Get-StaleBuildReason {
  [OutputType([string])]
  param()
  $info = Get-ModuleInfo
  $built = Get-ChildItem -Path $info.DistRoot -Recurse -Filter "$($info.ModuleName).psm1" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $built) {
    return "No built module under '$($info.DistRoot)'. Run './tasks.ps1 build'."
  }
  $newest = Get-ChildItem -Path $info.SourceRoot -Recurse -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($newest -and $newest.LastWriteTime -gt $built.LastWriteTime) {
    return ("The built module is older than the source. '$($built.Name)' was built {0}, " -f $built.LastWriteTime.ToString('o')) +
      ("'$($newest.Name)' was changed {0}. Run './tasks.ps1 build'." -f $newest.LastWriteTime.ToString('o'))
  }
  $null
}

# The host check for -Skip: expressions, which Pester evaluates at DISCOVERY time: it runs
# before any BeforeAll, and on Windows PowerShell 5.1 where $IsWindows does not exist.
function Test-OnWindowsHost {
  [OutputType([bool])]
  param()
  ($PSVersionTable.PSEdition -eq 'Desktop') -or [bool]$IsWindows
}

# A store folder under TestDrive, unique per call so two tests never share one. Created by
# default; -NoCreate marks the sites whose subject needs the folder absent.
function New-TestStore {
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Test fixture creating a folder under TestDrive, which Pester removes; -WhatIf/-Confirm do not apply.')]
  [OutputType([string])]
  param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Tag,

    [switch]$NoCreate
  )

  # $TestDrive comes from the calling test scope; PowerShell resolves it up the call stack.
  $path = Join-Path $TestDrive "$Tag-$(Get-Random)"
  if (-not $NoCreate) { [void] (New-Item -ItemType Directory -Path $path -Force) }
  $path
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
