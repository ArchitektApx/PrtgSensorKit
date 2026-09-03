<#
.SYNOPSIS
  Installs the modules the other tools need, CurrentUser scope, skipping any already present.
.DESCRIPTION
  Run once per host and once per edition: Windows PowerShell and pwsh do not share a module
  path. Pester carries the exact pin from Tools/pester_pin.ps1; the other modules are unpinned.
.EXAMPLE
  ./tasks.ps1 install_dev_requirements
.EXAMPLE
  pwsh -File Tools/install_dev_requirements.ps1
#>

. (Join-Path $PSScriptRoot 'pester_pin.ps1')

$RequiredModules = @(
  @{ Name = 'ModuleBuilder' }                    # builds the module from Source
  @{ Name = 'Configuration' }                    # required by ModuleBuilder
  # SkipPublisherCheck: Windows PowerShell 5.1 ships a Microsoft-signed Pester 3.4, and the
  # differently-signed v5+ fails to install side-by-side with a PublishersMismatch error.
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
