<#
.SYNOPSIS
  FAILING (clean): the secret was saved by a DIFFERENT account than the sensor runs as.
.DESCRIPTION
  The single most common PrtgSensorKit deployment mistake, reproduced on purpose. DPAPI binds
  a secret to the Windows account that saved it, so a secret saved from your interactive admin
  session cannot be decrypted by the Local System account PRTG runs the sensor as. It works
  perfectly when you test the script by hand and fails the moment PRTG runs it.

  Expected PRTG result: Down (red), NOT a parse error. Get-PrtgSecret throws, Invoke-PrtgSensor
  catches it and emits well-formed error JSON, so the message is the module's own guidance:

    Failed to decrypt secret 'IntegrationWrongAccount'. DPAPI-protected secrets can only be
    read by the same Windows account and machine that saved them; this is running as
    'NT AUTHORITY\SYSTEM'. Re-save the secret as that account.

  That named account in the message is the diagnostic: it tells you which account the sensor
  ACTUALLY runs as, which is what you need to re-save under.

  SETUP - deliberately save the secret as the WRONG account. Log on interactively as a normal
  user account (NOT the account the sensor runs as, so not Local System) and run:

    Import-Module PrtgSensorKit
    Save-PrtgSecret -Name 'IntegrationWrongAccount' -Secret (ConvertTo-SecureString 'wrong-owner' -AsPlainText -Force)

  Then point the sensor at this script while the device is configured to run as Local System.

  If instead you see 'Secret ... not found', the secret was never saved at all, which is a
  different (also clean) failure - the mismatch case needs the file to exist but be undecryptable.

  To turn this into the working case, re-save the same name as the sensor's own account; that
  is exactly what working/20-stored-secret.ps1 demonstrates.
.NOTES
  Requires the PrtgSensorKit module installed on the probe.
  Expected Doctor verdict: PSK0013 Info (Get-PrtgSecret usage detected), everything else Pass.
  The Doctor cannot detect this statically - only the running account can, which is the point.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  $token = Get-PrtgSecret -Name 'IntegrationWrongAccount' -AsPlainText

  New-PrtgChannel -Channel 'Never emitted' -Value $token.Length | Add-PrtgChannel
}
