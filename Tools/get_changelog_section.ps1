# Extracts the body of a '## [<Heading>]' section from CHANGELOG.md (up to the next
# '## ' heading, the link-reference footer, or end of file). Prints an empty string when
# the section is missing; callers decide whether that is an error. Single source of truth
# for the changelog section format - used by Tools/prepare_release.ps1 and
# .github/workflows/release.yml.
#
# Usage:
#   ./Tools/get_changelog_section.ps1 -Heading 1.1.0
#   ./Tools/get_changelog_section.ps1 -Heading Unreleased -ChangelogPath ./CHANGELOG.md

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
