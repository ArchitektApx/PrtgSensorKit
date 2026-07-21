<#
.SYNOPSIS
  FAILING (clean): block throws, module emits a PRTG error response.
.DESCRIPTION
  The block throws. Invoke-PrtgSensor catches it and emits well-formed error JSON
  (prtg.error = 1). Expected PRTG result: Down (red) with a message containing
  'deliberate failure' plus the line/char details. This is correct error handling: the
  OUTPUT is still valid, the sensor is just Down. No network.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  New-PrtgChannel -Channel 'Never emitted' -Value 1 | Add-PrtgChannel
  throw 'deliberate failure to validate the PRTG error response'
}
