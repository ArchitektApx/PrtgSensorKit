<#
.SYNOPSIS
  MALFORMED (PSK0007): more than one Invoke-PrtgSensor call.
.DESCRIPTION
  A sensor must emit exactly one response. Two Invoke-PrtgSensor calls write two JSON
  documents to stdout. Expected PRTG result: XML/parse error. Doctor: PSK0007 Error
  ('a sensor must emit exactly one response'). No network.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  New-PrtgChannel -Channel 'First' -Value 1 | Add-PrtgChannel
  Set-PrtgMessage 'first response'
}

Invoke-PrtgSensor {
  New-PrtgChannel -Channel 'Second' -Value 2 | Add-PrtgChannel
  Set-PrtgMessage 'second response'
}
