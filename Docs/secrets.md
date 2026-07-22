# 🔐 Credentials and secrets

Don't put API tokens or passwords in your sensor script in plain text. `Save-PrtgSecret` stores a
secret encrypted with Windows DPAPI (via `Export-Clixml`), and `Get-PrtgSecret` reads it back -
so the secret lives on disk protected, not in your code. Works for a `SecureString` (API token)
or a full `PSCredential` (user + password).

```powershell
# Sensor code - no secret in the script:
Invoke-PrtgSensor {
  $token = Get-PrtgSecret -Name 'AcmeApi' -AsPlainText
  $data  = Invoke-RestMethod -Uri $url -Headers @{ Authorization = "Bearer $token" }
  New-PrtgChannel -Channel 'Items' -Value $data.count | Add-PrtgChannel
}
```

> [!IMPORTANT]
> DPAPI ties the encryption to **the Windows account and machine that saved the secret**. By
> default a PRTG sensor runs under the **probe service account** (usually **Local System**). It
> only runs as a different user if the sensor's **Security Context** setting is changed to *"Use
> the Windows credentials of the parent device"* - in which case the Windows credentials set on
> the device (or inherited from the group/probe) are used. Either way you must **save the secret
> once while running as whatever account the sensor actually uses**, or it can't decrypt it at
> runtime. For Local System, run the save under Local System (e.g. `PsExec -s powershell`); for a
> configured user, run the save as that user:
>
> ```powershell
> # one-time, as the sensor's account:
> Save-PrtgSecret -Name 'AcmeApi' -Secret (Read-Host -AsSecureString)
> Save-PrtgSecret -Name 'SqlLogin' -Credential (Get-Credential)   # user + password
> ```
>
> Secrets are stored under `%ProgramData%\PrtgSensorKit\Secrets`, ACL-locked to that account,
> Administrators, and SYSTEM. Windows only - for local development on non-Windows, add
> `-AllowUnprotected` to store the secret **obfuscated, not encrypted** (a warning is printed;
> never use it for real credentials).

The only reliable test that a secret decrypts at runtime is running the script under the
sensor's real account. The sensor doctor reminds you when it sees `Get-PrtgSecret` usage
(check PSK0013).

Don't log secret values with `Write-PrtgLog`; nothing is redacted
(see [File logging](logging.md)).

See [07-stored-secret-api.ps1](../Examples/07-stored-secret-api.ps1) and
[14-stored-credential-sql.ps1](../Examples/14-stored-credential-sql.ps1).
