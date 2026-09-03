<#
.SYNOPSIS
  FAILING (clean): a NON-terminating error inside the block fails the sensor.
.DESCRIPTION
  Invoke-PrtgSensor sets $ErrorActionPreference to 'Stop' where the block can see it, so a
  non-terminating error inside the block fails the sensor instead of being written to stderr
  and discarded.

  Expected PRTG result: Down (red), message containing 'Cannot find path'. Well-formed error
  JSON (prtg.error = 1), so this is a clean Down, not a parse error.

  Get-Item on a missing path is used as the stand-in because it is deterministic and needs no
  network. In real sensors this is a failing Get-CimInstance, Get-Counter, or Invoke-RestMethod.
.NOTES
  Requires the PrtgSensorKit module installed on the probe.
  Expected Doctor verdict: all Pass. The Doctor cannot detect this statically - the script
  looks fine and the failure only shows at runtime.
  Paired with working/23-error-opt-out.ps1, which opts a single command out.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  # Non-terminating in a default session; terminating inside Invoke-PrtgSensor.
  $missing = Get-Item 'C:\PrtgSensorKit-does-not-exist\nope.txt'

  # Never reached: the failure above ends the block.
  New-PrtgChannel -Channel 'Stale' -Value $missing.Length | Add-PrtgChannel
  Set-PrtgMessage 'this message proves the failure was swallowed'
}
