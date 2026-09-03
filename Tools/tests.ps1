<#
.SYNOPSIS
  Builds the module, then runs the Pester suite. Throws on any test failure.
.PARAMETER Target
  Tree the behaviour tests import. The artifact tests always read the build.
.PARAMETER Path
  One test file or folder. Defaults to the whole test directory.
.PARAMETER PassThru
  Emit the Pester result object as well.
#>

param(
  [ValidateSet('Source', 'Dist')]
  [string]$Target = 'Source',

  [string]$Path,

  [switch]$PassThru
)

# $global:, not a bare assignment, here and around the Pester call below: on Windows PowerShell
# 5.1 a script-scoped copy sits in the scope chain of every test block and shadows the global.
$previousErrorAction = $global:ErrorActionPreference
$targetVariable = $null
$previousTarget = $null

try {
  $global:ErrorActionPreference = 'Stop'

  . (Join-Path $PSScriptRoot 'module_info.ps1')

  # Build first so a run can never verify a stale artifact.
  . (Join-Path $PSScriptRoot 'build.ps1')

  # Only the pinned Pester runs the suite; the pin lives in pester_pin.ps1.
  . (Join-Path $PSScriptRoot 'pester_pin.ps1')
  Import-PinnedPester

  . (Join-Path $PSScriptRoot 'test_suite_path.ps1')
  $testPath = Resolve-TestSuitePath -Path $Path

  $config = New-PesterConfiguration
  $config.Run.Path = $testPath
  # The result object is how this script decides its own exit status. Run.Exit stays off: it
  # kills the caller's whole session instead of letting the throw below propagate.
  $config.Run.PassThru = $true
  $config.Output.Verbosity = 'Detailed'

  $targetVariable = Get-TestTargetVariableName
  $previousTarget = [Environment]::GetEnvironmentVariable($targetVariable)

  # 'Stop' guards setup only; the run needs 'Continue', or a Write-Error inside a test
  # terminates the function.
  $global:ErrorActionPreference = 'Continue'
  [Environment]::SetEnvironmentVariable($targetVariable, $Target)
  $result = Invoke-Pester -Configuration $config
} finally {
  if ($targetVariable) { [Environment]::SetEnvironmentVariable($targetVariable, $previousTarget) }
  $global:ErrorActionPreference = $previousErrorAction
}

if (-not $result -or $result.FailedCount -gt 0) {
  throw "Tests failed ($($result.FailedCount) failed / $($result.TotalCount) total)."
}

if ($PassThru.IsPresent) {
  $result
}
