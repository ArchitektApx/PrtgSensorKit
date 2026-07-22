function Invoke-PrtgSensorDoctor {
  <#
  .SYNOPSIS
    Diagnoses common problems in a PrtgSensorKit sensor script.

  .DESCRIPTION
    Analyzes a sensor script WITHOUT executing it (it only parses the script) and checks the
    machine's environment, then prints a summary and returns one finding object per check.

    Script checks (run everywhere):
    - PSK0001 script parses without syntax errors
    - PSK0002 Import-Module PrtgSensorKit present before the first kit command
    - PSK0003 no Restart-* call inside the Invoke-PrtgSensor block
    - PSK0004 Restart-* before Invoke-PrtgSensor and before other Import-Module calls
    - PSK0005 no Write-PrtgOutput / Write-PrtgError / Clear-PrtgOutput inside the block
    - PSK0006 Invoke-PrtgSensor present (Info when running low-level instead)
    - PSK0007 at most one Invoke-PrtgSensor call
    - PSK0008 no output-producing statements after Invoke-PrtgSensor
    - PSK0009 web cmdlets have TLS set up (-ForceModernTls or manual)
    - PSK0010 no -DryRun left in the script
    - PSK0011 source encoding is safe for Windows PowerShell 5.1 (all-ASCII or BOM)
    - PSK0012 reminder that channel limits are snapshotted at sensor creation
    - PSK0013 reminder that DPAPI secrets are bound to the sensor's account

    Environment checks (Windows only, skipped elsewhere; see -SkipEnvironmentChecks):
    - PSK0101 PrtgSensorKit resolvable in 32-bit Windows PowerShell 5.1 (PRTG's host)
    - PSK0102 PrtgSensorKit resolvable in 64-bit PowerShell when Restart-As64BitPowershell is used
    - PSK0103 pwsh present and PrtgSensorKit resolvable there when Restart-InPwsh is used
    - PSK0104 statically imported dependency modules resolvable in the effective target host

    Findings are objects with CheckId, Severity (Pass/Info/Warning/Error), Message, Line,
    and Recommendation, so they can be filtered and processed; the console summary is
    printed to the host stream and does not pollute the pipeline.

  .PARAMETER ScriptPath
    Path to the sensor script (.ps1) to analyze. The script is parsed, never run.

  .PARAMETER SkipEnvironmentChecks
    Skip the PSK01xx environment checks (module/host probing). Script checks always run.
    Environment checks are also skipped automatically on non-Windows hosts.

  .EXAMPLE
    Invoke-PrtgSensorDoctor -ScriptPath 'C:\Program Files (x86)\PRTG Network Monitor\Custom Sensors\EXEXML\MySensor.ps1'

    Analyzes a deployed sensor script and prints the findings.

  .EXAMPLE
    $findings = Invoke-PrtgSensorDoctor -ScriptPath .\MySensor.ps1 -SkipEnvironmentChecks
    $findings | Where-Object Severity -eq 'Error'

    Captures the findings for scripted processing and filters for errors.

  .OUTPUTS
    PSCustomObject. One finding per check (CheckId, Severity, Message, Line, Recommendation).

  .LINK
    Invoke-PrtgSensor
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'The human-readable summary is deliberately host-only so the pipeline carries nothing but the finding objects.')]
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$ScriptPath,

    [Parameter(Mandatory = $false)]
    [switch]$SkipEnvironmentChecks
  )

  $resolved = (Resolve-Path -LiteralPath $ScriptPath -ErrorAction Stop).ProviderPath
  $parsed = Get-PrtgDoctorAst -ScriptPath $resolved

  $findings = [System.Collections.Generic.List[object]]::new()
  $findings.AddRange(@(Test-PrtgDoctorScript -Parsed $parsed))

  # --- Environment checks (or the reason they were skipped) -----------------------------
  if ($SkipEnvironmentChecks) {
    $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0100' -Severity 'Info' `
      -Message 'Environment checks skipped (-SkipEnvironmentChecks).'))
  } elseif (-not (Test-PrtgWindows)) {
    $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0100' -Severity 'Info' `
      -Message 'Environment checks skipped: not running on Windows. Run the Doctor on the PRTG probe for the full picture.'))
  } elseif ($null -ne $parsed.Ast) {
    $commandAsts = @($parsed.CommandAsts)
    $uses64 = @($commandAsts | Where-Object { $_.GetCommandName() -eq 'Restart-As64BitPowershell' }).Count -gt 0
    $usesPwsh = @($commandAsts | Where-Object { $_.GetCommandName() -eq 'Restart-InPwsh' }).Count -gt 0
    $staticModules = Get-PrtgDoctorImportedModuleName -Parsed $parsed
    $findings.AddRange(@(Test-PrtgDoctorEnvironment -UsesRestart64Bit $uses64 -UsesRestartInPwsh $usesPwsh -StaticModuleNames $staticModules))
  }

  # --- Host summary ----------------------------------------------------------------------
  $severityOrder = @{ 'Error' = 0; 'Warning' = 1; 'Info' = 2; 'Pass' = 3 }
  $severityColor = @{ 'Error' = 'Red'; 'Warning' = 'Yellow'; 'Info' = 'Cyan'; 'Pass' = 'Green' }

  Write-Host ''
  Write-Host "PrtgSensorKit Doctor: $resolved" -ForegroundColor Cyan
  Write-Host ''

  foreach ($finding in ($findings | Sort-Object -Property { $severityOrder[$_.Severity] }, CheckId)) {
    $location = if ($null -ne $finding.Line) { " (line $($finding.Line))" } else { '' }
    Write-Host "  [$($finding.CheckId)] $($finding.Severity)$($location): $($finding.Message)" -ForegroundColor $severityColor[$finding.Severity]
    if ($finding.Recommendation) {
      Write-Host "            fix: $($finding.Recommendation)" -ForegroundColor DarkGray
    }
  }

  $errors = @($findings | Where-Object Severity -eq 'Error').Count
  $warnings = @($findings | Where-Object Severity -eq 'Warning').Count
  $infos = @($findings | Where-Object Severity -eq 'Info').Count
  $passed = @($findings | Where-Object Severity -eq 'Pass').Count

  $verdictColor = if ($errors -gt 0) { 'Red' } elseif ($warnings -gt 0) { 'Yellow' } else { 'Green' }
  Write-Host ''
  Write-Host "  $errors error(s), $warnings warning(s), $infos info, $passed passed" -ForegroundColor $verdictColor
  Write-Host ''

  $findings.ToArray()
}
