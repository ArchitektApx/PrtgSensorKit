# The single source of the Pester version this repo tests and measures against; Pester versions
# change how many commands a coverage run analyzes. Tools/README.md echoes the number.

$PesterRequiredVersion = '6.1.0'

function Import-PinnedPester {
  <#
    .SYNOPSIS
      Loads exactly the pinned Pester and reports which version resolved.
    .DESCRIPTION
      Removes any Pester already in the session first, because Windows PowerShell 5.1 ships
      Pester 3.4. Fails loudly, naming the pin and its installer, when the pin cannot resolve.
  #>
  [CmdletBinding()]
  param()

  Remove-Module Pester -Force -ErrorAction SilentlyContinue
  try {
    Import-Module Pester -RequiredVersion $PesterRequiredVersion -Force -ErrorAction Stop
  } catch {
    throw ("Pester $PesterRequiredVersion is not available on this host, and no other version is " +
      "acceptable: a coverage or test number produced by a different version is not comparable " +
      "with any other host's. Install it with './tasks.ps1 install_dev_requirements' " +
      "(Tools/install_dev_requirements.ps1), which holds the same pin. ($($_.Exception.Message))")
  }

  $resolved = @(Get-Module Pester | Where-Object { $_.Version -eq [version]$PesterRequiredVersion })
  if ($resolved.Count -ne 1) {
    $loaded = @(Get-Module Pester | ForEach-Object { $_.Version }) -join ', '
    throw ("Pester loaded as '$loaded' but the pin is $PesterRequiredVersion. Install the " +
      "pinned version with './tasks.ps1 install_dev_requirements' " +
      "(Tools/install_dev_requirements.ps1).")
  }

  Write-Host "Pester: $PesterRequiredVersion (pinned)"
}
