# Dot-sourced by both runners; defines Resolve-TestSuitePath and nothing else. Kept out of
# pester_pin.ps1 because the CI cache keys hash that file.

function Resolve-TestSuitePath {
  <#
    .SYNOPSIS
      Returns the resolved test path, or throws when it holds no test files.
    .DESCRIPTION
      Defaults to the Tests folder, located relative to this script rather than the working
      directory. A missing, empty or mis-pathed path throws: Pester reports zero passed and zero
      failed for it, which reads as green.
  #>
  [CmdletBinding()]
  [OutputType([string])]
  param(
    # A test file or a folder. Relative paths resolve against the caller's working directory.
    [string]$Path
  )

  # Join-Path's 3-argument form is PowerShell 7+ only; nest for Windows PowerShell 5.1.
  $requested = if ($Path) { $Path } else { Join-Path (Join-Path $PSScriptRoot '..') 'Tests' }
  $testPath = Resolve-Path -Path $requested -ErrorAction SilentlyContinue
  if (-not $testPath) {
    throw "Test path '$requested' does not exist. Refusing to report success on an empty run."
  }

  $found = if (Test-Path -LiteralPath $testPath.Path -PathType Container) {
    Get-ChildItem -Path $testPath.Path -Filter '*.Tests.ps1' -Recurse -ErrorAction SilentlyContinue
  } else {
    Get-Item -LiteralPath $testPath.Path -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*.Tests.ps1' }
  }
  if (-not $found) {
    throw "No *.Tests.ps1 files found under '$($testPath.Path)'. Refusing to report success on an empty run."
  }

  $testPath.Path
}
