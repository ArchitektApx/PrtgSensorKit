<#
.SYNOPSIS
  Dev task runner.
.PARAMETER Task
  build, test, lint, fuzz, coverage, install_dev_requirements or prepare_release.
.PARAMETER Version
  Release version for prepare_release.
.PARAMETER MinimumPercent
  coverage only: fail the run when coverage drops below this percentage.
.PARAMETER Target
  test only: tree the behaviour tests import. The artifact tests always read the build.
.PARAMETER Path
  test only: one test file or folder instead of the whole test folder.
#>

param(
  # Task and Version both declare a Position: once one parameter does, the others stop binding
  # positionally, and './tasks.ps1 test' silently runs the default task.
  [Parameter(Position = 0)]
  [ValidateSet('build', 'test', 'lint', 'fuzz', 'coverage', 'install_dev_requirements', 'prepare_release')]
  [string]$Task = 'build',

  [Parameter(Position = 1)]
  [string]$Version,

  [double]$MinimumPercent = 0,

  [ValidateSet('Source', 'Dist')]
  [string]$Target = 'Source',

  [string]$Path
)

switch ($Task) {
  'build' {
    . $(Join-Path "Tools" "build.ps1")
    break
  }
  'test' {
    # Splatted so an unset -Path falls through to the whole test folder, not an empty string.
    $testArgs = @{ Target = $Target }
    if ($Path) { $testArgs.Path = $Path }
    . $(Join-Path "Tools" "tests.ps1") @testArgs
    break
  }
  'lint' {
    . $(Join-Path "Tools" "lint.ps1")
    break
  }
  'fuzz' {
    . $(Join-Path "Tools" "fuzz.ps1") 4>$null 3>$null
    break
  }
  'coverage' {
    . $(Join-Path "Tools" "coverage.ps1") -MinimumPercent $MinimumPercent
    break
  }
  'install_dev_requirements' {
    . $(Join-Path "Tools" "install_dev_requirements.ps1")
    break
  }
  'prepare_release' {
    if (-not $Version) {
      # The process must exit non-zero, so CI cannot mistake a botched invocation for a
      # prepared release.
      throw "prepare_release needs a version: ./tasks.ps1 prepare_release <x.y.z>"
    }
    . $(Join-Path "Tools" "prepare_release.ps1") -Version $Version
    break
  }
  default {
    Write-Error "Invalid task: $Task"
    break
  }
}
