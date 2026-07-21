# Prepares a release: gates on lint/build/test, verifies the changelog has content for
# the release, stamps the new version into README.md and build.psd1, then rebuilds and
# verifies the built module actually carries the new version.
#
# Usage (from anywhere):
#   ./Tools/prepare_release.ps1 -Version 1.1.0
#
# On success the working tree contains the stamped files (including the CHANGELOG
# '[Unreleased]' section promoted to the version) and a fresh Dist build; review, commit,
# and tag.

param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidatePattern('^\d+\.\d+\.\d+$')]
  [string]$Version
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$Text) {
  Write-Host "--------------------------------"
  Write-Host $Text
  Write-Host "--------------------------------"
}

# Everything below assumes the repo root as working directory (like tasks.ps1 does).
$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
  # --- 1) Quality gates: lint, build, test - any failure aborts ------------------------
  Write-Step "prepare_release ${Version}: lint"
  ./tasks.ps1 lint

  Write-Step "prepare_release ${Version}: build"
  ./tasks.ps1 build

  Write-Step "prepare_release ${Version}: test"
  ./tasks.ps1 test

  # --- 2) Changelog must contain the release's changes ---------------------------------
  Write-Step "prepare_release ${Version}: changelog check"
  if (-not (Test-Path -LiteralPath 'CHANGELOG.md')) {
    throw "CHANGELOG.md not found. Write the changelog before preparing a release."
  }
  $changelog = Get-Content -LiteralPath 'CHANGELOG.md' -Raw

  # Section extraction is delegated to get_changelog_section.ps1 - the single source of
  # truth for the changelog format, shared with .github/workflows/release.yml.
  $getSection = Join-Path $PSScriptRoot 'get_changelog_section.ps1'
  # 'Content' = at least one list item or sub-heading, not just blank lines.
  function Test-ChangelogSectionContent([string]$Body) {
    [bool]($Body -and $Body -match '(?m)^\s*(?:[-*]\s+\S|###\s+\S)')
  }

  $versionBody = [string](& $getSection -Heading $Version)
  $unreleasedBody = [string](& $getSection -Heading 'Unreleased')

  if (Test-ChangelogSectionContent $versionBody) {
    Write-Host "CHANGELOG.md: '[$Version]' section found with content."
  } elseif (Test-ChangelogSectionContent $unreleasedBody) {
    # Promote the Unreleased section to this release.
    $today = Get-Date -Format 'yyyy-MM-dd'
    $changelog = $changelog -replace '(?m)^## \[Unreleased\][^\r\n]*', "## [$Version] - $today"

    # Keep a Changelog link refs: repoint [Unreleased] at the new tag and add the
    # release's compare link below it. Best-effort - warn when the pattern is absent.
    $linkPattern = '(?m)^\[Unreleased\]:\s*(?<base>\S+)/compare/v(?<prev>\S+)\.\.\.HEAD\s*$'
    $linkMatch = [regex]::Match($changelog, $linkPattern)
    if ($linkMatch.Success) {
      $base = $linkMatch.Groups['base'].Value
      $prev = $linkMatch.Groups['prev'].Value
      $newLinks = "[Unreleased]: $base/compare/v$Version...HEAD`n" +
                  "[$Version]: $base/compare/v$prev...v$Version"
      $changelog = [regex]::Replace($changelog, $linkPattern, $newLinks)
    } else {
      Write-Warning "CHANGELOG.md: no '[Unreleased]: .../compare/v<prev>...HEAD' link found; compare links not updated."
    }

    Set-Content -LiteralPath 'CHANGELOG.md' -Value $changelog -NoNewline
    Write-Host "CHANGELOG.md: '[Unreleased]' promoted to '[$Version] - $today'."
  } else {
    throw "CHANGELOG.md has no content under '## [$Version]' or '## [Unreleased]'. Document the changes before preparing a release."
  }

  # --- 3) Stamp the version badge in README.md -----------------------------------------
  Write-Step "prepare_release ${Version}: stamp README.md"
  $readme = Get-Content -LiteralPath 'README.md' -Raw
  $badgePattern = 'Version-\d+\.\d+\.\d+-green\.svg'
  if ($readme -notmatch $badgePattern) {
    throw "README.md: version badge (Version-x.y.z-green.svg) not found."
  }
  $newReadme = [regex]::Replace($readme, $badgePattern, "Version-$Version-green.svg")
  if ($newReadme -ne $readme) {
    Set-Content -LiteralPath 'README.md' -Value $newReadme -NoNewline
    Write-Host "README.md: version badge set to $Version."
  } else {
    Write-Host "README.md: version badge already at $Version."
  }

  # --- 4) Stamp SemVer in build.psd1 ----------------------------------------------------
  Write-Step "prepare_release ${Version}: stamp build.psd1"
  $buildConfig = Get-Content -LiteralPath 'build.psd1' -Raw
  $semverPattern = '(?m)^(\s*SemVer\s*=\s*)"[^"]*"'
  if ($buildConfig -notmatch $semverPattern) {
    throw "build.psd1: SemVer entry not found."
  }
  $newBuildConfig = [regex]::Replace($buildConfig, $semverPattern, ('${1}"' + $Version + '"'))
  if ($newBuildConfig -ne $buildConfig) {
    Set-Content -LiteralPath 'build.psd1' -Value $newBuildConfig -NoNewline
    Write-Host "build.psd1: SemVer set to $Version."
  } else {
    Write-Host "build.psd1: SemVer already at $Version."
  }

  # --- 5) Rebuild and verify the built module carries the new version -------------------
  Write-Step "prepare_release ${Version}: rebuild with new version"
  ./tasks.ps1 build

  $builtManifest = Join-Path (Join-Path (Join-Path 'Dist' 'PrtgSensorKit') $Version) 'PrtgSensorKit.psd1'
  if (-not (Test-Path -LiteralPath $builtManifest)) {
    throw "Rebuild verification failed: '$builtManifest' does not exist. The build did not pick up SemVer $Version."
  }
  $manifestInfo = Test-ModuleManifest -Path $builtManifest
  if ($manifestInfo.Version.ToString() -ne $Version) {
    throw "Rebuild verification failed: built manifest reports version '$($manifestInfo.Version)', expected '$Version'."
  }

  Write-Step "prepare_release ${Version}: done"
  Write-Host "Built module verified at $builtManifest (ModuleVersion $($manifestInfo.Version))."
  Write-Host "Next: deploy the Tests/Integration sensors to a real PRTG probe and confirm each matches its expected result in Tests/Integration/README.md, then review the diff, commit, tag v$Version."
} finally {
  Pop-Location
}
