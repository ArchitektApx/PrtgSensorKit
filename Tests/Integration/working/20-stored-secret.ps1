<#
.SYNOPSIS
  WORKING: reads a DPAPI-protected secret saved by the sensor's own account.
.DESCRIPTION
  Exercises the Save-PrtgSecret / Get-PrtgSecret round trip inside a real probe, which the
  Pester suite cannot: DPAPI binds a secret to the Windows ACCOUNT that saved it, and under
  PRTG that account is whatever the sensor runs as, not the account you were logged in as
  when you wrote the script.

  Expected PRTG result: Up, one channel 'Secret Length' = 11 (the length of 'integration'),
  message 'secret read as <account>'. The channel value proves the secret decrypted; the
  message names the account so a mismatch is obvious at a glance.

  SETUP - REQUIRED BEFORE THE FIRST SCAN. Save the secret ONCE as the exact account this
  sensor runs as, or the sensor goes Down with a decrypt error (which is what the paired
  failing/21-secret-wrong-account.ps1 sensor demonstrates on purpose).

  A PRTG EXE/Script sensor runs as either Local System or the Windows credentials set on the
  device/group/probe. Check the device's "Credentials for Windows Systems" to find out which.

    # Local System (the PRTG default) - run from an elevated console, PsExec from Sysinternals:
    PsExec.exe -s -i powershell.exe
    Import-Module PrtgSensorKit
    Save-PrtgSecret -Name 'IntegrationDemo' -Secret (ConvertTo-SecureString 'integration' -AsPlainText -Force)

    # Or, for a configured Windows user - log on interactively AS that user, then:
    Import-Module PrtgSensorKit
    Save-PrtgSecret -Name 'IntegrationDemo' -Secret (ConvertTo-SecureString 'integration' -AsPlainText -Force)

  Verify from the same account before adding the sensor:

    Get-PrtgSecret -Name 'IntegrationDemo' -AsPlainText    # -> integration

  The secret store is shared: every sensor account can save into it, and each secret file
  stays readable only by the account that wrote it.
.NOTES
  Requires the PrtgSensorKit module installed on the probe.
  Expected Doctor verdict: PSK0013 Info (Get-PrtgSecret usage detected), everything else Pass.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  $token = Get-PrtgSecret -Name 'IntegrationDemo' -AsPlainText

  New-PrtgChannel -Channel 'Secret Length' -Value $token.Length -Unit Count | Add-PrtgChannel
  Set-PrtgMessage "secret read as $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
}
