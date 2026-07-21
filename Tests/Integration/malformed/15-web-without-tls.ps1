<#
.SYNOPSIS
  MALFORMED (PSK0009): HTTPS request without -ForceModernTls.
.DESCRIPTION
  On Windows PowerShell 5.1 the default SecurityProtocol can lack TLS 1.2, so an HTTPS call
  to a modern-TLS-only endpoint fails the handshake. This is the negative counterpart to
  working/05 (same request WITH -ForceModernTls). Expected PRTG result: Down on 5.1 with a
  'could not create SSL/TLS secure channel' style error; if the probe's 5.1 already
  defaults to TLS 1.2 it may pass, which is worth recording. Doctor: PSK0009 Info
  ('web cmdlet without -ForceModernTls'). Needs outbound HTTPS.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  $response = Invoke-WebRequest -Uri 'https://www.paessler.com/robots.txt' -UseBasicParsing -TimeoutSec 15
  New-PrtgChannel -Channel 'Status' -Value ([int]$response.StatusCode) | Add-PrtgChannel
  Set-PrtgMessage 'https without forced TLS'
}
