<#
.SYNOPSIS
  WORKING: HTTPS request with -ForceModernTls.
.DESCRIPTION
  Fetches a small public HTTPS resource after forcing TLS 1.2/1.3. Expected PRTG result:
  Up with a 'Status' channel = 200 when the probe has outbound internet. This is the
  positive counterpart to malformed/15 (same request WITHOUT -ForceModernTls). Needs
  outbound HTTPS; if the probe is offline, this sensor legitimately goes Down and that is
  expected. Doctor: PSK0009 Pass (TLS is forced).
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor -ForceModernTls -RetryCount 2 -RetryDelaySeconds 3 {
  $response = Invoke-WebRequest -Uri 'https://www.paessler.com/robots.txt' -UseBasicParsing -TimeoutSec 15
  New-PrtgChannel -Channel 'Status' -Value ([int]$response.StatusCode) | Add-PrtgChannel
  New-PrtgChannel -Channel 'Body Length' -Value ([int]$response.RawContentLength) -Unit BytesFile | Add-PrtgChannel
  Set-PrtgMessage 'https reachable with modern TLS'
}
