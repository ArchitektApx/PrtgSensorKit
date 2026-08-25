# Installs the modules the other tools need (CurrentUser scope), skipping any already present.
# Run this once per host - including once per EDITION on a machine that tests both Windows
# PowerShell and pwsh, since they do not share a module path.
#
# Usage (from the repo root):
#   ./tasks.ps1 install_dev_requirements
#   pwsh -File Tools/install_dev_requirements.ps1
#
# Pester carries a RequiredVersion rather than a floor: a floor is satisfied by whatever version
# arrived first, and Pester versions change how many commands a coverage run analyzes. The exact
# pin still excludes the built-in Pester 3.4 that Windows PowerShell 5.1 ships. The other three
# modules are deliberately unpinned.
#
# The pin itself lives in Tools/pester_pin.ps1, which the test and coverage runners import.
. (Join-Path $PSScriptRoot 'pester_pin.ps1')

$RequiredModules = @(
  @{ Name = 'ModuleBuilder' }                    # builds the module from Source
  @{ Name = 'Configuration' }                    # required by ModuleBuilder
  # SkipPublisherCheck: Windows PowerShell 5.1 ships a Microsoft-signed Pester 3.4, and installing
  # the differently-signed v5+ side-by-side otherwise fails with a PublishersMismatch error.
  @{ Name = 'Pester'; RequiredVersion = $PesterRequiredVersion; SkipPublisherCheck = $true } # runs the tests (v5 API)
  @{ Name = 'PSScriptAnalyzer'; SkipPublisherCheck = $true }                  # lint / compatibility checks
)

Write-Host "Installing required modules..."
Write-Host "--------------------------------"

foreach ($Module in $RequiredModules) {
  $available = Get-Module -Name $Module.Name -ListAvailable
  if ($Module.RequiredVersion) {
    $available = $available | Where-Object { $_.Version -eq [version]$Module.RequiredVersion }
  }

  if (-not $available) {
    $pin = if ($Module.RequiredVersion) { " ($($Module.RequiredVersion))" } else { '' }
    Write-Host "Installing $($Module.Name)$pin..."
    try {
      $params = @{ Name = $Module.Name; Scope = 'CurrentUser'; Force = $true; ErrorAction = 'Stop' }
      if ($Module.RequiredVersion) { $params.RequiredVersion = $Module.RequiredVersion }
      if ($Module.SkipPublisherCheck) { $params.SkipPublisherCheck = $true }
      Install-Module @params
    } catch {
      Write-Host "Installing $($Module.Name) failed"
      throw "Installing $($Module.Name) failed. ($($_.Exception.Message))"
    }
    Write-Host "$($Module.Name) installed successfully"
  } else {
    Write-Host "$($Module.Name) is already installed"
  }
}
Write-Host "--------------------------------"
Write-Host "All required modules are installed"
