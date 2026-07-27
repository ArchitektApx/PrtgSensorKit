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
> Secrets are stored under `%ProgramData%\PrtgSensorKit\Secrets`. Each secret FILE is ACL-locked
> to the account that saved it, Administrators, and SYSTEM. Windows only - for local development
> on non-Windows, add `-AllowUnprotected` to store the secret **obfuscated, not encrypted** (a
> warning is printed; never use it for real credentials).

## Multiple sensor accounts on one probe

The store folder is shared by every account that saves into it, and is deliberately left as an
ordinary directory - only the secret files inside it are locked down. That lets a probe run
sensors under several accounts (Local System plus one or more configured users) with each account
saving and reading its own secrets.

DPAPI already restricts decryption to the saving account, so the file ACL is defence in depth: it
stops another local non-admin from copying the encrypted blob, and hides the plain-text user name
that `Export-Clixml` stores next to the encrypted password of a `PSCredential`.

Secret names are a shared namespace. The first account to save a given name owns that file, and a
second account cannot overwrite it without administrator help, so give each account its own secret
names (or point it at its own `-Path`).

What an ordinary store folder means in practice: the default `%ProgramData%` permissions let any
local user list the folder, so secret **names** are visible to them (the values are not, they stay
DPAPI-encrypted and ACL-locked per file). A local user can also create a file there, which means a
hostile local account could occupy a secret name before your sensor account saves it. If untrusted
users can log on to the probe server, put the store somewhere only the sensor accounts can reach
and pass that folder to `-Path` on every `Save-PrtgSecret` and `Get-PrtgSecret` call.

> [!IMPORTANT]
> **Upgrading from 1.2.1 or earlier?** Those versions also ACL-locked the store FOLDER, to Local
> System, Administrators, and whichever account saved last. 1.3.0 does not undo that automatically.
>
> - **Sensors run as Local System only** (the PRTG default): nothing to do, the store keeps working.
> - **Another account needs the store:** it was already locked out before 1.3.0, and stays locked
>   out until the old folder ACL is cleared. As an administrator, once:
>
> ```powershell
> Remove-Item "$env:ProgramData\PrtgSensorKit\Secrets" -Recurse -Force   # as an admin
> # then re-run Save-PrtgSecret once as EACH sensor account
> ```
>
> New stores created by 1.3.0 and later never need this.

The only reliable test that a secret decrypts at runtime is running the script under the
sensor's real account. The sensor doctor reminds you when it sees `Get-PrtgSecret` usage
(check PSK0013).

Don't log secret values with `Write-PrtgLog`; nothing is redacted
(see [File logging](logging.md)).

See [07-stored-secret-api.ps1](../Examples/07-stored-secret-api.ps1) and
[14-stored-credential-sql.ps1](../Examples/14-stored-credential-sql.ps1).
