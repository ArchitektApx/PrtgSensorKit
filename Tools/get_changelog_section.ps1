<#
.SYNOPSIS
  Extracts the body of a '## [<Heading>]' section from CHANGELOG.md.
.DESCRIPTION
  The body runs to the next '## ' heading, the link-reference footer, or end of file. A missing
  section prints an empty string and callers decide whether that is an error. Single source of
  truth for the changelog section format, shared with .github/workflows/release.yml.
.PARAMETER Heading
  Section heading without the brackets, a version or 'Unreleased'.
.EXAMPLE
#>

param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$Heading,

  [Parameter(Mandatory = $false)]
  [string]$ChangelogPath = 'CHANGELOG.md'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ChangelogPath)) {
  throw "Changelog not found at '$ChangelogPath'."
}

$changelog = Get-Content -LiteralPath $ChangelogPath -Raw
$pattern = "(?ms)^## \[$([regex]::Escape($Heading))\][^\r\n]*\r?\n(.*?)(?=^## |^\[[^\]]+\]:\s*\S+\s*$|\z)"
$match = [regex]::Match($changelog, $pattern)

if ($match.Success) { $match.Groups[1].Value } else { '' }
