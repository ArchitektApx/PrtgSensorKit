<div align="center">

# 📡 PrtgSensorKit

**PowerShell framework for building [PRTG](https://www.paessler.com/) custom EXE/Script Advanced sensors - less boilerplate, valid JSON output every time.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/Version-1.2.0-green.svg)](CHANGELOG.md)
[![Platform](https://img.shields.io/badge/PowerShell-5.1%20|%207+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Built with ModuleBuilder](https://img.shields.io/badge/Built%20with-ModuleBuilder-8A2BE2.svg)](https://github.com/PoshCode/ModuleBuilder)

</div>

---

You write the logic that gathers your metrics; PrtgSensorKit handles building the channels,
formatting the JSON PRTG expects, capping channels/message length, and reporting errors.

## ✨ Why PrtgSensorKit

- 🧱 **No boilerplate** - build [channels](Docs/channels.md) with one cmdlet, emit valid PRTG JSON with another, or wrap the whole sensor in `Invoke-PrtgSensor`.
- ✅ **Always-valid output** - enforces PRTG's rules for you (max 50 channels, no `#`, 2000-char messages, `0`/`1` flags).
- 🪆 **Pipe-friendly** - chain `New-PrtgChannel | Add-PrtgChannel` with no intermediate variables.
- 🔀 **[Runtime helpers](Docs/runtime-hosts.md)** - jump to 64-bit PowerShell or PowerShell 7+ when your sensor needs it.
- 🔐 **[Secret storage](Docs/secrets.md)** - keep API tokens and credentials out of your script, DPAPI-encrypted.
- 💾 **[State between runs](Docs/state.md)** - cache values and compute rates/deltas, safe under overlapping scans.
- 🤝 **[Shared collection cache](Docs/shared-cache.md)** - many sensors share one expensive API/SQL/WMI call per interval, race-free.
- 🔁 **[Retries and TLS](Docs/resilience.md)** - `-RetryCount` re-runs flaky blocks, `-ForceModernTls` fixes 5.1's web request defaults.
- 📝 **[File logging](Docs/logging.md)** - per-run log files with full error details, without ever touching the sensor output.
- 🩺 **[Sensor doctor](Docs/debugging.md)** - finds the classic sensor-script mistakes before PRTG does; debug interactively with `-DryRun`.
- 📖 **Full built-in help** - every command is documented; `Get-Help <command> -Full`.

## 📦 Install

```powershell
# From Windows PowerShell 5.1 (elevated) - PRTG runs sensors there
Install-Module PrtgSensorKit -Scope AllUsers
```

PRTG launches sensors in **32-bit Windows PowerShell 5.1** as a service account, which decides
where PrtgSensorKit *and your sensor's dependency modules* must be installed. Details and the
host/bitness matrix: [Installation](Docs/installation.md).

## 🚀 Your first PRTG sensor

Save this as an `EXE/Script Advanced` sensor script in
`C:\Program Files (x86)\PRTG Network Monitor\Custom Sensors\EXEXML\`.

Put your channel-building logic in a script block and `Invoke-PrtgSensor` handles the rest -
it catches errors and turns them into a PRTG error response,
keeps stray output from corrupting the result (see the warning below), and emits exactly one
valid response:

```powershell
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  $cpuUsage = Get-Process |
    ForEach-Object { $_.CPU } |
    Measure-Object -Average |
    Select-Object -ExpandProperty Average

  New-PrtgChannel -Channel 'CPU Usage' -Value $cpuUsage -Unit Percent -Float | Add-PrtgChannel
  Set-PrtgMessage 'CPU usage average'
}
```

Your script's `param()` values and other script-scope variables are visible inside the block, so
sensors that take parameters work unchanged:

```powershell
param([string]$ApiUrl, [string]$ApiToken)

Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  $response = Invoke-RestMethod -Uri $ApiUrl -Headers @{ Authorization = "Bearer $ApiToken" }
  $response.data | ForEach-Object { New-PrtgChannel -Channel $_.name -Value $_.value -Unit $_.unit | Add-PrtgChannel }
  Set-PrtgMessage $response.message
}
```

> [!TIP]
> **Always quote placeholders in PRTG's "Parameters" field**: `-ApiUrl '%host'`, not
> `-ApiUrl %host`. A device name or placeholder value containing a space otherwise shifts
> every positional argument, and the sensor fails in ways that are hard to trace back.

> [!WARNING]
> ⚠️ **Never write to the output stream in your sensor code.** PRTG reads the sensor result
> from the process **standard output**, which must contain **only** the JSON. A stray
> `Write-Host`, a bare `Write-Output`, or an un-captured command that returns objects (e.g.
> `Get-Process` on its own line) will corrupt the result. `Invoke-PrtgSensor` discards that
> output for you. **To debug, log to a file** - add `-EnableLogging` to the
> `Invoke-PrtgSensor` call and use `Write-PrtgLog` (see [File logging](Docs/logging.md)) -
> never log to output.

Making web requests? Windows PowerShell 5.1 often lacks TLS 1.2 by default; add
`-ForceModernTls` (see [Resilience](Docs/resilience.md)).

Starting a new sensor? Copy
[01-basic-single-channel.ps1](Examples/01-basic-single-channel.ps1) as your template -
the numbered examples build up from there.

## 📚 Documentation

| Topic | What's in it |
| --- | --- |
| [Installation](Docs/installation.md) | Where the module and your dependencies go: hosts, bitness, AllUsers scope |
| [Channels](Docs/channels.md) | Units, floats, limits - and why limits only apply at sensor creation |
| [Runtime hosts](Docs/runtime-hosts.md) | `Restart-As64BitPowershell` / `Restart-InPwsh` and import ordering |
| [Credentials and secrets](Docs/secrets.md) | DPAPI storage, the account-binding trap, saving as Local System |
| [State between runs](Docs/state.md) | Rates, deltas, histories; locking and retention |
| [Shared collection cache](Docs/shared-cache.md) | One expensive call shared by many sensors, exactly one fetch per interval |
| [File logging](Docs/logging.md) | Per-run log files, lifecycle logging, retention |
| [Resilience](Docs/resilience.md) | Retries for flaky sources, modern TLS on 5.1 |
| [Diagnosing and debugging](Docs/debugging.md) | The sensor doctor and `-DryRun` |
| [Custom errors and low-level output](Docs/low-level-output.md) | Non-terminating errors, manual output control |

## ❓ Getting help on any command

Every command ships with full PowerShell comment-based help.
You don't need this README to look up a parameter; ask PowerShell directly:

```powershell
Get-Help New-PrtgChannel              # summary, syntax, and description
Get-Help New-PrtgChannel -Full        # every parameter explained, plus notes
Get-Help New-PrtgChannel -Examples    # just the runnable examples
Get-Help New-PrtgChannel -Parameter Unit   # help for one parameter
```

> [!TIP]
> `-Full` is the one to reach for while writing a sensor - it lists every unit, limit, and
> lookup parameter with a description. This works for all commands below.

## 🧰 Commands

### Main Commands

| Command | Purpose |
| --- | --- |
| [`Invoke-PrtgSensor`](Source/Public/Invoke-PrtgSensor.ps1) | Run a sensor block with boilerplate, error handling, and output hygiene handled |
| [`New-PrtgChannel`](Source/Public/New-PrtgChannel.ps1) | Build a channel object |
| [`Add-PrtgChannel`](Source/Public/Add-PrtgChannel.ps1) | Add a channel to the sensor output (max 50) |
| [`Set-PrtgMessage`](Source/Public/Set-PrtgMessage.ps1) | Set the sensor message |
| [`Get-PrtgMessage`](Source/Public/Get-PrtgMessage.ps1) | Get the current sensor message |
| [`Save-PrtgSecret`](Source/Public/Save-PrtgSecret.ps1) | Store an API token or credential, DPAPI-encrypted |
| [`Get-PrtgSecret`](Source/Public/Get-PrtgSecret.ps1) | Read a stored secret in a sensor |
| [`Save-PrtgSensorState`](Source/Public/Save-PrtgSensorState.ps1) | Persist a value between sensor runs |
| [`Get-PrtgSensorState`](Source/Public/Get-PrtgSensorState.ps1) | Read state saved by a previous run |
| [`Clear-PrtgSensorState`](Source/Public/Clear-PrtgSensorState.ps1) | Delete or prune stored sensor state |
| [`Use-PrtgCachedResult`](Source/Public/Use-PrtgCachedResult.ps1) | Share one expensive call across sensors (TTL cache, race-free) |
| [`Write-PrtgLog`](Source/Public/Write-PrtgLog.ps1) | Append a timestamped line to this run's log file |
| [`Restart-As64BitPowershell`](Source/Public/Restart-As64BitPowershell.ps1) | Re-launch the sensor in 64-bit PowerShell |
| [`Restart-InPwsh`](Source/Public/Restart-InPwsh.ps1) | Re-launch the sensor in PowerShell 7+ |
| [`Invoke-PrtgSensorDoctor`](Source/Public/Invoke-PrtgSensorDoctor.ps1) | Diagnose common issues in a sensor script |

### Lower-level Commands (advanced)

| Command | Purpose |
| --- | --- |
| [`Write-PrtgOutput`](Source/Public/Write-PrtgOutput.ps1) | Emit the sensor JSON |
| [`Write-PrtgError`](Source/Public/Write-PrtgError.ps1) | Emit a PRTG error response |
| [`Clear-PrtgOutput`](Source/Public/Clear-PrtgOutput.ps1) | Clear channels and message |
| [`Set-PrtgOutput`](Source/Public/Set-PrtgOutput.ps1) | Hand-roll your own sensor output object |

See [Custom errors and low-level output](Docs/low-level-output.md) before using the
lower-level commands directly.

## 🛠️ Building from source

```powershell
./tasks.ps1 install_dev_requirements   # ModuleBuilder, Configuration, Pester, PSScriptAnalyzer
./tasks.ps1 lint                       # PSScriptAnalyzer style + 5.1/7.0 compatibility checks
./tasks.ps1 build                      # builds to ./Dist, then runs the Pester suite
./tasks.ps1 test                       # runs the Pester suite against the built module
./tasks.ps1 prepare_release 1.1.0      # gates + changelog check, stamps version, verified rebuild
```

## 📄 License

Released under the [MIT License](LICENSE).
