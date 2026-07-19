param(
  [ValidateSet('build', 'test', 'lint', 'install_dev_requirements')]
  [string]$Task = 'build'
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
  'install_dev_requirements' {
    . $(Join-Path "Tools" "install_dev_requirements.ps1")
    break
  }
  default {
    Write-Error "Invalid task: $Task"
    break
  }
}
