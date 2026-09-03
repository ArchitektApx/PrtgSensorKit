function Test-PrtgDoctorEnvironment {
  <#
  .SYNOPSIS
    Runs the environment Doctor checks (PSK0101-PSK0104) for a sensor script.
  .DESCRIPTION
    Verifies that PrtgSensorKit (and the script's statically imported dependency modules)
    are resolvable in the hosts the sensor actually runs in: 32-bit Windows PowerShell 5.1
    (what PRTG starts), 64-bit Windows PowerShell when Restart-As64BitPowershell is used,
    and pwsh when Restart-InPwsh is used. Windows-only; the caller decides about skipping.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $false)][bool]$UsesRestart64Bit = $false,
    [Parameter(Mandatory = $false)][bool]$UsesRestartInPwsh = $false,
    [Parameter(Mandatory = $false)][string[]]$StaticModuleNames = @()
  )

  $findings = [System.Collections.Generic.List[object]]::new()

  # Resolved once; PSK0103 and PSK0104 both need it when Restart-InPwsh is used.
  $pwshCommand = $null
  if ($UsesRestartInPwsh) {
    $pwshCommand = Get-Command -Name 'pwsh' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  }

  # The effective target host, pwsh over 64-bit over 32-bit. $targetExe and $targetName feed
  # PSK0104 only; PSK0101-PSK0103 probe fixed hosts.
  $targetExe = $null
  $targetName = ''
  if ($UsesRestartInPwsh) {
    if ($pwshCommand) { $targetExe = $pwshCommand.Source; $targetName = 'pwsh (PowerShell 7+)' }
  } elseif ($UsesRestart64Bit) {
    $targetExe = Get-PrtgDoctorHostPath -Bitness 'x64'; $targetName = '64-bit Windows PowerShell 5.1'
  } else {
    $targetExe = Get-PrtgDoctorHostPath -Bitness 'x86'; $targetName = '32-bit Windows PowerShell 5.1'
  }

  # --- PSK0101: kit resolvable in 32-bit Windows PowerShell 5.1 -------------------------
  $ps32 = Get-PrtgDoctorHostPath -Bitness 'x86'
  if (Invoke-PrtgDoctorModuleProbe -Executable $ps32 -ModuleName 'PrtgSensorKit') {
    $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0101' -Severity 'Pass' `
      -Message 'PrtgSensorKit is resolvable in 32-bit Windows PowerShell 5.1 (the host PRTG starts).'))
  } else {
    $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0101' -Severity 'Error' `
      -Message 'PrtgSensorKit is NOT resolvable in 32-bit Windows PowerShell 5.1, the host PRTG starts sensors in.' `
      -Recommendation "Install it for all users from Windows PowerShell: 'Install-Module PrtgSensorKit -Scope AllUsers'."))
  }

  # --- PSK0102: kit resolvable in 64-bit Windows PowerShell (when restarted into it) ----
  if (-not $UsesRestart64Bit) {
    $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0102' -Severity 'Pass' -Message 'Restart-As64BitPowershell not used; 64-bit check not applicable.'))
  } else {
    $ps64 = Get-PrtgDoctorHostPath -Bitness 'x64'
    if (Invoke-PrtgDoctorModuleProbe -Executable $ps64 -ModuleName 'PrtgSensorKit') {
      $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0102' -Severity 'Pass' -Message 'PrtgSensorKit is resolvable in 64-bit Windows PowerShell.'))
    } else {
      $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0102' -Severity 'Error' `
        -Message 'Restart-As64BitPowershell is used, but PrtgSensorKit is NOT resolvable in 64-bit Windows PowerShell.' `
        -Recommendation "Install it for all users: 'Install-Module PrtgSensorKit -Scope AllUsers' (the AllUsers path is shared between bitnesses; check a custom PSModulePath if this still fails)."))
    }
  }

  # --- PSK0103: pwsh present and kit resolvable there (when restarted into it) ----------
  if (-not $UsesRestartInPwsh) {
    $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0103' -Severity 'Pass' -Message 'Restart-InPwsh not used; pwsh check not applicable.'))
  } else {
    if (-not $pwshCommand) {
      $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0103' -Severity 'Error' `
        -Message 'Restart-InPwsh is used, but pwsh (PowerShell 7+) was not found on PATH.' `
        -Recommendation 'Install PowerShell 7+ on the probe, or remove Restart-InPwsh.'))
    } elseif (Invoke-PrtgDoctorModuleProbe -Executable $pwshCommand.Source -ModuleName 'PrtgSensorKit') {
      $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0103' -Severity 'Pass' -Message 'pwsh is available and PrtgSensorKit is resolvable there.'))
    } else {
      $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0103' -Severity 'Error' `
        -Message 'Restart-InPwsh is used, but PrtgSensorKit is NOT resolvable in pwsh (PowerShell 7+ has its own module path).' `
        -Recommendation "Install it from pwsh: 'Install-Module PrtgSensorKit -Scope AllUsers'."))
    }
  }

  # --- PSK0104: dependency modules resolvable in the effective target host --------------
  $dependencies = @($StaticModuleNames | Where-Object { $_ -and $_ -ne 'PrtgSensorKit' } | Select-Object -Unique)
  if ($dependencies.Count -eq 0) {
    $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0104' -Severity 'Pass' -Message 'No statically imported dependency modules to check.'))
  } else {
    if ($null -eq $targetExe) {
      $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0104' -Severity 'Warning' `
        -Message 'Dependency modules could not be checked: the target host (pwsh) is missing.' `
        -Recommendation 'Fix PSK0103 first, then re-run the Doctor.'))
    } else {
      $missing = @($dependencies | Where-Object { -not (Invoke-PrtgDoctorModuleProbe -Executable $targetExe -ModuleName $_) })
      if ($missing.Count -eq 0) {
        $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0104' -Severity 'Pass' `
          -Message "All statically imported modules ($($dependencies -join ', ')) are resolvable in $targetName."))
      } else {
        $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0104' -Severity 'Warning' `
          -Message "Module(s) $($missing -join ', ') are NOT resolvable in $targetName, where this sensor's code runs." `
          -Recommendation "Install them for that host (run Install-Module from a matching process), or check PSModulePath. Dynamic imports are not analyzed."))
      }
    }
  }

  $findings.ToArray()
}
