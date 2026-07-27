# Installs the modules the other tools need (CurrentUser scope), skipping any already present.
# Run this once per host - including once per EDITION on a machine that tests both Windows
# PowerShell and pwsh, since they do not share a module path.
#
# Usage (from the repo root):
#   ./tasks.ps1 install_dev_requirements
#   pwsh -File Tools/install_dev_requirements.ps1
#
# Pester is pinned to v5+ because Windows PowerShell 5.1 ships the incompatible built-in
# Pester 3.4, which a plain -ListAvailable check would wrongly accept.
$RequiredModules = @(
  @{ Name = 'ModuleBuilder' }                    # builds the module from Source
  @{ Name = 'Configuration' }                    # required by ModuleBuilder
  # SkipPublisherCheck: Windows PowerShell 5.1 ships a Microsoft-signed Pester 3.4, and installing
  # the differently-signed v5 side-by-side otherwise fails with a PublishersMismatch error.
  @{ Name = 'Pester'; MinimumVersion = '5.0.0'; SkipPublisherCheck = $true } # runs the tests (v5 API)
  @{ Name = 'PSScriptAnalyzer'; SkipPublisherCheck = $true }                 # lint / compatibility checks
)

Write-Host "Installing required modules..."
Write-Host "--------------------------------"

foreach ($Module in $RequiredModules) {
  $available = Get-Module -Name $Module.Name -ListAvailable
  if ($Module.MinimumVersion) {
    $available = $available | Where-Object { $_.Version -ge [version]$Module.MinimumVersion }
  }

  if (-not $available) {
    $min = if ($Module.MinimumVersion) { " (>= $($Module.MinimumVersion))" } else { '' }
    Write-Host "Installing $($Module.Name)$min..."
    try {
      $params = @{ Name = $Module.Name; Scope = 'CurrentUser'; Force = $true; ErrorAction = 'Stop' }
      if ($Module.MinimumVersion) { $params.MinimumVersion = $Module.MinimumVersion }
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
