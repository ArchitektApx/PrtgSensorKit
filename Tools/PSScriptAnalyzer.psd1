@{
  # Compatibility-focused ruleset for the dedicated CI compatibility step. General style rules
  # are handled by the separate lint job; here we only check cross-version / cross-platform use.
  IncludeRules = @(
    'PSUseCompatibleSyntax'
    'PSUseCompatibleCommands'
  )
  Rules = @{
      PSUseCompatibleSyntax = @{
          Enable         = $true
          # Windows PowerShell 5.1 (the PRTG runtime) and PowerShell 7 (Windows/Linux/macOS).
          TargetVersions = @('5.1', '7.0')
      }
      PSUseCompatibleCommands = @{
          Enable         = $true
          TargetProfiles = @(
              'win-8_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework',
              'ubuntu_x64_18.04_7.0.0_x64_3.1.2_core'
          )
      }
  }
}
