param(
  [ValidateSet('build', 'test', 'lint', 'fuzz', 'install_dev_requirements', 'prepare_release')]
  [string]$Task = 'build',

  # Only used by prepare_release: ./tasks.ps1 prepare_release 1.1.0
  [string]$Version
)

switch ($Task) {
  'build' {
    . $(Join-Path "Tools" "build.ps1")
    break
  }
  'test' {
    . $(Join-Path "Tools" "tests.ps1")
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
