<#
.SYNOPSIS
  MALFORMED (PSK0001): deliberate syntax error.
.DESCRIPTION
  The block has an unclosed 'if' condition, so the script does not parse. Expected PRTG
  result: the sensor fails to run at all (PowerShell parse error, nothing valid on stdout).
  Doctor: PSK0001 Error, reported with a line number, and the Doctor still runs its
  remaining checks where possible. No network.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  if ($true {
    New-PrtgChannel -Channel 'Answer' -Value 42 | Add-PrtgChannel
  }
  Set-PrtgMessage 'never parses'
}
