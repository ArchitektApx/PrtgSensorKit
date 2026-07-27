<#
.SYNOPSIS
  WORKING: opting a single command out of the 1.3.0 terminating-error behavior.
.DESCRIPTION
  The escape hatch for the 1.3.0 change demonstrated by failing/22-nonterminating-error.ps1.
  When a command inside the block is genuinely allowed to fail - an optional data source, a
  probe that is not always present - opt THAT command out and keep the rest of the block
  protected.

  Two supported ways, both used below:
    1. -ErrorAction SilentlyContinue on the individual command (preferred: narrowest scope).
    2. Assigning $ErrorActionPreference INSIDE the block, which is block-local and shadows
       the wrapper's setting. Set it back to 'Stop' afterwards so the rest of the block stays
       protected.

  Expected PRTG result: Up, two channels - 'Optional Present' = 0 (the optional source was
  missing but did not fail the sensor) and 'Required' = 1 - message 'optional source absent,
  continuing'. Same script, same missing path as sensor 22, opposite outcome.

  NOTE: setting $ErrorActionPreference at the TOP OF THE SCRIPT (outside the block) does NOT
  work as an opt-out. PRTG runs sensors as 'powershell.exe -f sensor.ps1', where the script's
  top-level scope IS the global scope that Invoke-PrtgSensor overrides. It must be inside the
  block, or per-command via -ErrorAction.
.NOTES
  Requires the PrtgSensorKit module installed on the probe.
  Expected Doctor verdict: all Pass.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  # Way 1: per-command opt-out, the narrowest and preferred form.
  $optional = Get-Item 'C:\PrtgSensorKit-does-not-exist\nope.txt' -ErrorAction SilentlyContinue
  New-PrtgChannel -Channel 'Optional Present' -Value ([int][bool]$optional) | Add-PrtgChannel

  # Way 2: block-local preference for a command that has no -ErrorAction of its own.
  $ErrorActionPreference = 'SilentlyContinue'
  $alsoOptional = Get-Item 'C:\PrtgSensorKit-does-not-exist\other.txt'
  $ErrorActionPreference = 'Stop'

  # Back under protection: a failure from here on still fails the sensor.
  New-PrtgChannel -Channel 'Required' -Value 1 | Add-PrtgChannel
  Set-PrtgMessage 'optional source absent, continuing'
}
