param(
  # Positions are explicit on purpose: as soon as ONE parameter declares a Position, the others
  # stop binding positionally, and './tasks.ps1 test' would silently run the default task.
  [Parameter(Position = 0)]
  [ValidateSet('build', 'test', 'lint', 'fuzz', 'coverage', 'install_dev_requirements', 'prepare_release')]
  [string]$Task = 'build',

  # Only used by prepare_release: ./tasks.ps1 prepare_release 1.1.0
  [Parameter(Position = 1)]
  [string]$Version,

  # Only used by coverage: fail the run when coverage drops below this percentage.
  [double]$MinimumPercent = 0,

  # Only used by test: which tree the behaviour tests import. The artifact tests always read
  # the build.
  [ValidateSet('Source', 'Dist')]
  [string]$Target = 'Source',

  # Only used by test: a single test file or folder instead of the whole test folder.
  [string]$Path
)

switch ($Task) {
  'build' {
    . $(Join-Path "Tools" "build.ps1")
    break
  }
  'test' {
    # Splatted so an unset -Path falls through to the whole test folder rather than an empty
    # string.
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
      # throw, not Write-Error: the process must exit non-zero so CI cannot mistake a
      # botched invocation for a prepared release.
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
