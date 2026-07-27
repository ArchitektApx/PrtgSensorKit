<#
.SYNOPSIS
  FAILING (clean): a NON-terminating error inside the block fails the sensor (1.3.0 change).
.DESCRIPTION
  This is the sensor that demonstrates the one breaking change in 1.3.0. Before 1.3.0,
  Invoke-PrtgSensor documented that it set $ErrorActionPreference to 'Stop' for your block,
  but it did not actually reach your block. A non-terminating error was therefore written to
  stderr and DISCARDED, and the sensor went Up (green) with whatever channels happened to be
  added - stale or missing data reported as healthy. Silent monitoring blindness.

  From 1.3.0 the preference is applied where the block can actually see it, so the same
  script now fails loudly.

  Expected PRTG result: Down (red), message containing 'Cannot find path'. Well-formed error
  JSON (prtg.error = 1), so this is a clean Down, not a parse error.

  ON A PRE-1.3.0 MODULE THIS SAME SCRIPT SHOWS UP (GREEN) WITH A 'Stale' CHANNEL = 1. That
  contrast is the whole point of this sensor: if you are validating the upgrade, run it once
  against the old module and once against the new one.

  Get-Item on a missing path is used as the stand-in because it is deterministic and needs no
  network. In real sensors this is a failing Get-CimInstance, Get-Counter, or Invoke-RestMethod.
.NOTES
  Requires the PrtgSensorKit module installed on the probe.
  Expected Doctor verdict: all Pass. The Doctor cannot detect this statically - the whole
  point is that the script LOOKS fine and its behavior changed underneath it.
  Paired with working/23-error-opt-out.ps1, which keeps the old behavior deliberately.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  # Non-terminating in a default session; terminating inside Invoke-PrtgSensor from 1.3.0 on.
  $missing = Get-Item 'C:\PrtgSensorKit-does-not-exist\nope.txt'

  # Never reached from 1.3.0. Before 1.3.0 this ran and the sensor reported Up with bad data.
  New-PrtgChannel -Channel 'Stale' -Value $missing.Length | Add-PrtgChannel
  Set-PrtgMessage 'this message proves the failure was swallowed'
}
