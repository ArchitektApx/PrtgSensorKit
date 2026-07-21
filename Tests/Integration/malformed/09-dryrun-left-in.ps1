<#
.SYNOPSIS
  MALFORMED (PSK0010): -DryRun left in a deployed sensor.
.DESCRIPTION
  -DryRun makes Invoke-PrtgSensor return a PowerShell object instead of PRTG JSON. Deployed
  to PRTG, stdout is an object dump, not JSON. Expected PRTG result: XML/parse error (the
  sensor cannot be read). Doctor: PSK0010 Warning ('remove -DryRun before deploying').
  No network.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor -DryRun {
  New-PrtgChannel -Channel 'Answer' -Value 42 | Add-PrtgChannel
  Set-PrtgMessage 'this will not be valid PRTG JSON'
}
