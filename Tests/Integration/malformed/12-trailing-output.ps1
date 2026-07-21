<#
.SYNOPSIS
  MALFORMED (PSK0008): output-producing statement after Invoke-PrtgSensor.
.DESCRIPTION
  Anything written to stdout after the sensor JSON corrupts the result PRTG reads. Here a
  bare Get-Date pipeline runs after Invoke-PrtgSensor and appends text. Expected PRTG
  result: XML/parse error (extra text after the JSON). Doctor: PSK0008 Warning
  ('statement after Invoke-PrtgSensor could write to the output stream'). No network.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  New-PrtgChannel -Channel 'Answer' -Value 42 | Add-PrtgChannel
  Set-PrtgMessage 'ok'
}

# Stray output after the response corrupts stdout.
Get-Date
