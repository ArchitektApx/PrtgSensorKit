<#
.SYNOPSIS
  MALFORMED (PSK0004): a dependency module imported BEFORE Restart-*.
.DESCRIPTION
  Restart-As64BitPowershell relaunches the sensor in the 64-bit host; any Import-Module of
  a bitness/edition-specific dependency must come AFTER the restart. Importing it before
  the restart runs the import in the wrong host, where it can fail before the relaunch ever
  happens. Expected PRTG result: Down or parse error from the failed import. Doctor: PSK0004
  Error ('Import-Module before Restart-*'). Deploy on a host where the named module is NOT
  installed so the pre-restart import actually fails; change 'SqlServer' to any module
  missing on your probe.
#>
Import-Module PrtgSensorKit
Import-Module SqlServer   # WRONG: runs before the restart, in the host PRTG starts
Restart-As64BitPowershell

Invoke-PrtgSensor {
  New-PrtgChannel -Channel 'Answer' -Value 42 | Add-PrtgChannel
  Set-PrtgMessage 'ok'
}
