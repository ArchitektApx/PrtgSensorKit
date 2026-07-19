# Example sensors

Deploy-ready PRTG custom sensors that show the common PrtgSensorKit patterns. Each file is a
standalone **EXE/Script Advanced** sensor and doubles as a real-probe test case.

| File | Shows |
|------|-------|
| [01-basic-single-channel.ps1](01-basic-single-channel.ps1) | Minimal sensor: one channel + message via `Invoke-PrtgSensor`. |
| [02-multiple-channels-with-limits.ps1](02-multiple-channels-with-limits.ps1) | One channel per discovered item (disks) with warning/error limits. |
| [03-error-handling.ps1](03-error-handling.ps1) | A thrown error becomes a PRTG error response automatically. |
| [04-manual-output-api.ps1](04-manual-output-api.ps1) | The low-level API (`Clear`/`New`/`Add`/`Set`/`Write-PrtgOutput`) without the wrapper. |
| [05-sensor-parameters.ps1](05-sensor-parameters.ps1) | Accepting parameters from the PRTG sensor settings. |
| [06-relaunch-64bit-and-pwsh.ps1](06-relaunch-64bit-and-pwsh.ps1) | Relaunching into 64-bit PowerShell / pwsh before running. |
| [07-stored-secret-api.ps1](07-stored-secret-api.ps1) | Reading a DPAPI-protected API token with `Get-PrtgSecret`. |
| [08-channel-types-showcase.ps1](08-channel-types-showcase.ps1) | The range of channel units and options. |
| [09-value-lookups-and-status.ps1](09-value-lookups-and-status.ps1) | Value lookups: turn a number into an up/down / status channel. |
| [10-difference-mode-counters.ps1](10-difference-mode-counters.ps1) | `-Mode Difference` to chart the delta of a cumulative counter. |
| [11-rest-api-multichannel.ps1](11-rest-api-multichannel.ps1) | Query a JSON REST API (TLS 1.2) and map fields to channels. |
| [12-ping-latency.ps1](12-ping-latency.ps1) | Ping a host: average latency + packet loss with limits. |
| [13-windows-service-health.ps1](13-windows-service-health.ps1) | One up/down channel per Windows service, with a rolled-up message. |
| [14-stored-credential-sql.ps1](14-stored-credential-sql.ps1) | Use a stored `PSCredential` (user + password) to authenticate. |
| [15-set-output-advanced.ps1](15-set-output-advanced.ps1) | Advanced: replace the whole output with a pre-built object via `Set-PrtgOutput`. |

## Deploy to a PRTG probe

1. Install the PrtgSensorKit module on the probe machine (for all users, so the sensor account
   can load it).
2. Copy the chosen `.ps1` into
   `C:\Program Files (x86)\PRTG Network Monitor\Custom Sensors\EXEXML\`.
3. Add a sensor of type **EXE/Script Advanced**, pick the script, and (for `05`) set any
   **Parameters**.

## Test locally (without installing the module)

The built module under `Dist/` is a valid module directory, so add it to `PSModulePath` and run
an example directly:

```powershell
$env:PSModulePath = (Resolve-Path ./Dist).Path + [IO.Path]::PathSeparator + $env:PSModulePath
./Examples/01-basic-single-channel.ps1
```

The script prints the exact PRTG JSON it would return. Some examples (`02`, `07`) expect Windows /
a stored secret and will emit a PRTG *error* response elsewhere, which is itself valid output.
