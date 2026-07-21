function Get-PrtgDoctorHostPath {
  # Resolves the powershell.exe path for the requested bitness, honoring the WOW64
  # filesystem redirection of the CURRENT process (System32 is redirected for 32-bit
  # processes; Sysnative escapes the redirection).
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('x86', 'x64')]
    [string]$Bitness
  )

  $winPs = 'WindowsPowerShell\v1.0\powershell.exe'
  if (-not [System.Environment]::Is64BitOperatingSystem) {
    return (Join-Path $env:SystemRoot "System32\$winPs")
  }

  if ($Bitness -eq 'x86') {
    if ([System.Environment]::Is64BitProcess) { Join-Path $env:SystemRoot "SysWOW64\$winPs" }
    else { Join-Path $env:SystemRoot "System32\$winPs" }
  } else {
    if ([System.Environment]::Is64BitProcess) { Join-Path $env:SystemRoot "System32\$winPs" }
    else { Join-Path $env:SystemRoot "Sysnative\$winPs" }
  }
}

function Invoke-PrtgDoctorModuleProbe {
  # Asks another PowerShell host whether it can resolve a module. Out-of-process on
  # purpose: each host has its own PSModulePath and the Doctor must never guess it.
  # Isolated in its own function so tests can mock it.
  [CmdletBinding()]
  [OutputType([bool])]
  param(
    [Parameter(Mandatory = $true)][string]$Executable,
    [Parameter(Mandatory = $true)][string]$ModuleName
  )

  # SECURITY GATE: $ModuleName comes from string literals parsed out of the ANALYZED
  # sensor script and is spliced into a child-process command line below. Without this
  # allowlist, a crafted literal (embedded quote) would execute arbitrary code in the
  # child - breaking the Doctor's guarantee that it never executes the analyzed script.
  # Real module names match this pattern; anything else is reported as not resolvable.
  if ($ModuleName -notmatch '^[A-Za-z0-9._-]+$') {
    Write-Verbose "Invoke-PrtgDoctorModuleProbe: refusing to probe suspicious module name '$ModuleName'."
    return $false
  }

  try {
    # Membership test against a marker string, not a scalar comparison: stray extra
    # stdout lines from the child host (banners, console hooks) must not turn a
    # resolvable module into a false 'not resolvable'.
    $output = & $Executable -NoProfile -NonInteractive -Command "if ([bool](Get-Module -ListAvailable -Name '$ModuleName')) { 'PSK_MODULE_FOUND' }" 2>$null
    return [bool](@($output) | Where-Object { "$_".Trim() -eq 'PSK_MODULE_FOUND' })
  } catch {
    return $false
  }
}

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
    $targetExe = $null
    $targetName = ''
    if ($UsesRestartInPwsh) {
      if ($pwshCommand) { $targetExe = $pwshCommand.Source; $targetName = 'pwsh (PowerShell 7+)' }
    } elseif ($UsesRestart64Bit) {
      $targetExe = Get-PrtgDoctorHostPath -Bitness 'x64'; $targetName = '64-bit Windows PowerShell 5.1'
    } else {
      $targetExe = Get-PrtgDoctorHostPath -Bitness 'x86'; $targetName = '32-bit Windows PowerShell 5.1'
    }

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
