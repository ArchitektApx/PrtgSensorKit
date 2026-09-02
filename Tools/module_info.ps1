# Single source of truth for "which module does this repo build, and where does it land?".
# build.psd1 is the authority, because ModuleBuilder reads the same file; every other tool asks
# here instead of walking Dist/ or hardcoding the name. Dot-source it; it defines functions and
# does nothing else on its own.
#
# Usage:
#   . $(Join-Path $PSScriptRoot 'module_info.ps1')
#   $info = Get-ModuleInfo

function Get-ModuleInfo {
  <#
    .SYNOPSIS
      Repository root, module name, source manifest, source root, build output root and version.
  #>
  [OutputType([hashtable])]
  param(
    # Repo root. Defaults to the parent of Tools/, which is where this script lives, so callers
    # in Tests/ or .github/ get the right answer without passing anything.
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
  )

  $buildConfigPath = Join-Path $RepoRoot 'build.psd1'
  if (-not (Test-Path -LiteralPath $buildConfigPath)) {
    throw "build.psd1 not found at '$buildConfigPath'."
  }
  $buildConfig = Import-PowerShellDataFile -LiteralPath $buildConfigPath

  foreach ($key in 'ModuleManifest', 'OutputDirectory', 'SemVer') {
    if (-not $buildConfig.$key) { throw "build.psd1 has no '$key' entry." }
  }

  # build.psd1 ships Windows-style separators (ModuleBuilder's own convention). Normalise them
  # so the paths also resolve under pwsh on Linux and macOS.
  $sep = [IO.Path]::DirectorySeparatorChar
  $sourceManifest = Join-Path $RepoRoot ($buildConfig.ModuleManifest -replace '\\', $sep)
  $sourceRoot = Split-Path -Parent $sourceManifest

  # OutputDirectory is relative to the MANIFEST, not to the repo root. GetFullPath only collapses
  # the '..' segments here; the input is already absolute.
  $distRoot = [IO.Path]::GetFullPath((Join-Path $sourceRoot ($buildConfig.OutputDirectory -replace '\\', $sep)))

  @{
    RepoRoot          = $RepoRoot
    ModuleName        = [IO.Path]::GetFileNameWithoutExtension($sourceManifest)
    SourceManifest    = $sourceManifest
    SourceRoot        = $sourceRoot
    SourceDirectories = @($buildConfig.SourceDirectories)
    DistRoot          = $distRoot
    SemVer            = $buildConfig.SemVer
  }
}

function Get-TestTargetVariableName {
  <#
    .SYNOPSIS
      Name of the environment variable that tells the test suite which tree to import.
    .DESCRIPTION
      An environment variable rather than a parameter: it reaches every test file, and the child
      PowerShell processes some tests spawn, without a parameter block or container data in each
      file. Derived from the module name so a rename carries it.
  #>
  [OutputType([string])]
  param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
  )

  $name = (Get-ModuleInfo -RepoRoot $RepoRoot).ModuleName -replace '[^A-Za-z0-9]', '_'
  "$($name.ToUpperInvariant())_TEST_TARGET"
}

function Get-BuiltManifestPath {
  <#
    .SYNOPSIS
      Path to the most recently built manifest under the build output root.
    .DESCRIPTION
      Throws rather than returning nothing, so a run without a build says which command makes one
      instead of failing later on a missing command.
  #>
  [OutputType([string])]
  param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
  )

  $info = Get-ModuleInfo -RepoRoot $RepoRoot
  $manifest = Get-ChildItem -Path $info.DistRoot -Recurse -Filter "$($info.ModuleName).psd1" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName

  if (-not $manifest) {
    throw "Built module not found under '$($info.DistRoot)'. Run './tasks.ps1 build' first."
  }
  $manifest
}
