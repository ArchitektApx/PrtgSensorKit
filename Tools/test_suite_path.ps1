# Dot-sourced by both runners; defines Resolve-TestSuitePath and nothing else. Kept out of
# pester_pin.ps1 because the CI cache keys hash that file.

function Resolve-TestSuitePath {
  <#
    .SYNOPSIS
      Returns the resolved Tests folder, or throws when it holds no test files.
    .DESCRIPTION
      Located relative to this script, not the working directory. An empty or mis-pathed
      folder throws: Pester reports zero passed and zero failed for it, which reads as green.
  #>
  [CmdletBinding()]
  [OutputType([string])]
  param()

  # Join-Path's 3-argument form is PowerShell 7+ only; nest for Windows PowerShell 5.1.
  $testPath = Join-Path (Join-Path $PSScriptRoot '..') 'Tests' | Resolve-Path -ErrorAction SilentlyContinue
  if (-not $testPath -or -not (Get-ChildItem -Path $testPath -Filter '*.Tests.ps1' -Recurse -ErrorAction SilentlyContinue)) {
    throw "No *.Tests.ps1 files found under Tests/. Refusing to report success on an empty run."
  }

  $testPath.Path
}
