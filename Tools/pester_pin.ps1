# The single source of the Pester version this repo tests and measures against. Dot-source it;
# it defines $PesterRequiredVersion and Import-PinnedPester and does nothing else on its own.
#
# The pin exists because Pester versions change how many commands a coverage run analyzes, so a
# coverage number is only comparable between hosts running the same version.
#
# Changing the pin means changing it here, in the one line of Tools/README.md that echoes the
# number, and in the CI cache keys (.github/workflows/*.yml) that hash this file.
# Tools/install_dev_requirements.ps1 installs it, Tools/tests.ps1 and Tools/coverage.ps1 import it.

$PesterRequiredVersion = '6.1.0'

function Import-PinnedPester {
  <#
    .SYNOPSIS
      Loads exactly the pinned Pester and reports which version resolved.
    .DESCRIPTION
      Removes any Pester already in the session first: Windows PowerShell 5.1 ships the built-in
      Pester 3.4, which has no New-PesterConfiguration and would silently skip the whole suite.
      An exact -RequiredVersion excludes it for that same reason.

      A resolution failure ends the run rather than falling back, and names the pin and the script
      that installs it, so the fix is one command and not an investigation.
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
