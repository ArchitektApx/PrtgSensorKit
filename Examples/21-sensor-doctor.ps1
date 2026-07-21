<#
.SYNOPSIS
  Diagnosing a sensor script with Invoke-PrtgSensorDoctor.
.DESCRIPTION
  The Doctor parses a sensor script (never runs it) and checks for common mistakes:
  misplaced Restart-* calls, manual output commands inside the Invoke-PrtgSensor block,
  a leftover -DryRun, missing TLS setup for web cmdlets, and more. On Windows it also
  probes whether PrtgSensorKit and the script's imported modules are actually resolvable
  in the hosts the sensor runs in (32-bit PowerShell 5.1, 64-bit, pwsh).

  Run this interactively on the PRTG probe - it is a development/troubleshooting tool,
  not a sensor.
.NOTES
  Requires the PrtgSensorKit module installed on the probe.
#>
Import-Module PrtgSensorKit

# Analyze another sensor script; a summary is printed and findings come back as objects.
$findings = Invoke-PrtgSensorDoctor -ScriptPath (Join-Path $PSScriptRoot '01-basic-single-channel.ps1')

# The objects make scripted follow-ups easy:
$errors = @($findings | Where-Object Severity -eq 'Error')
if ($errors.Count -gt 0) {
  Write-Warning "This sensor has $($errors.Count) blocking issue(s)."
}

# Skip the environment probing (e.g. on a dev machine that is not the probe):
# Invoke-PrtgSensorDoctor -ScriptPath .\MySensor.ps1 -SkipEnvironmentChecks
