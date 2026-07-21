<div align="center">

# 📡 PrtgSensorKit

**PowerShell framework for building [PRTG](https://www.paessler.com/) custom EXE/Script Advanced sensors — less boilerplate, valid JSON output every time.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/Version-1.1.0-green.svg)](CHANGELOG.md)
[![Platform](https://img.shields.io/badge/PowerShell-5.1%20|%207+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Built with ModuleBuilder](https://img.shields.io/badge/Built%20with-ModuleBuilder-8A2BE2.svg)](https://github.com/PoshCode/ModuleBuilder)

</div>

---

You write the logic that gathers your metrics; PrtgSensorKit handles building the channels,
formatting the JSON PRTG expects, capping channels/message length, and reporting errors.

## ✨ Why PrtgSensorKit

- 🧱 **No boilerplate** — build channels with one cmdlet, emit valid PRTG JSON with another, or wrap the whole sensor in [`Invoke-PrtgSensor`](Source/Public/Invoke-PrtgSensor.ps1).
- ✅ **Always-valid output** — enforces PRTG's rules for you (max 50 channels, no `#`, 2000-char messages, `0`/`1` flags).
- 🪆 **Pipe-friendly** — chain `New-PrtgChannel | Add-PrtgChannel` with no intermediate variables.
- 🔀 **Runtime helpers** — jump to 64-bit PowerShell or PowerShell 7+ when your sensor needs it.
- 🔐 **Secret storage** — keep API tokens and credentials out of your script with DPAPI-encrypted [`Save-PrtgSecret`](Source/Public/Save-PrtgSecret.ps1) / [`Get-PrtgSecret`](Source/Public/Get-PrtgSecret.ps1).
- 💾 **State between runs** - cache values and compute rates/deltas with [`Save-PrtgSensorState`](Source/Public/Save-PrtgSensorState.ps1) / [`Get-PrtgSensorState`](Source/Public/Get-PrtgSensorState.ps1), safe under overlapping scans.
- 🔁 **Built-in retries and TLS** - `-RetryCount` re-runs flaky blocks, `-ForceModernTls` fixes 5.1's web request defaults.
- 🩺 **Sensor doctor** - [`Invoke-PrtgSensorDoctor`](Source/Public/Invoke-PrtgSensorDoctor.ps1) finds the classic sensor-script mistakes before PRTG does; debug interactively with `-DryRun`.
- 📖 **Full built-in help** — every command is documented; `Get-Help <command> -Full`.

## 📦 Install

```powershell
Install-Module PrtgSensorKit
```

## 🧩 Where to install it (and your sensor's dependencies)

PRTG launches custom sensors in **32-bit Windows PowerShell 5.1**, so PrtgSensorKit has to be
available there. Install it **for all users** (the sensor runs as a service account, usually
Local System), from Windows PowerShell:

```powershell
# Run from Windows PowerShell 5.1 (elevated). The AllUsers module path is shared between the
# 32-bit and 64-bit hosts, so this one install covers both.
Install-Module PrtgSensorKit -Scope AllUsers
```

If your sensor uses `Restart-InPwsh`, also install PrtgSensorKit in **PowerShell 7+**, which has
its own module path:

```powershell
# Run from pwsh
Install-Module PrtgSensorKit -Scope AllUsers
```

`Import-Module PrtgSensorKit` works in every edition, so the module itself is never the problem —
but **the modules _your_ sensor imports must be installed in the host where your code actually
runs**, which depends on whether you call a `Restart-*` helper:

| Your sensor... | Install your dependency modules for |
| --- | --- |
| uses no `Restart-*` | 32-bit Windows PowerShell 5.1 (what PRTG starts) |
| calls `Restart-As64BitPowershell` | 64-bit Windows PowerShell 5.1 |
| calls `Restart-InPwsh` | PowerShell 7+ (pwsh) |

For Windows PowerShell the AllUsers/CurrentUser module folders are shared between the 32-bit and
64-bit hosts, so a normal `Install-Module` makes a script module visible to both but the bitness still matters for modules with **native/architecture-specific** components (e.g. `SqlServer`):

*always* run the install from a process of the matching bitness so the correct binaries are present!

Then *always* put your `Import-Module` lines **after** the `Restart-*` call (see the
*Running in 64-bit PowerShell or in PowerShell 7+* section below for more details).

## 🚀 Your first PRTG sensor

Save this as an `EXE/Script Advanced` sensor script in
`C:\Program Files (x86)\PRTG Network Monitor\Custom Sensors\EXEXML\`.

Put your channel-building logic in a script block and `Invoke-PrtgSensor` handles the rest —
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
> **Making web requests in your sensor?** Windows PowerShell 5.1 defaults can lack TLS 1.2,
> which makes HTTPS calls fail against modern endpoints. Add `-ForceModernTls` and
> `Invoke-PrtgSensor` enables TLS 1.2/1.3 for you before your block runs:
> `Invoke-PrtgSensor -ForceModernTls { ... }`
> See [22-force-modern-tls.ps1](Examples/22-force-modern-tls.ps1).

> [!WARNING]
> ⚠️ **Never write to the output stream in your sensor code.** PRTG reads the sensor result
> from the process **standard output**, which must contain **only** the JSON. A stray
> `Write-Host`, a bare `Write-Output`, or an un-captured command that returns objects (e.g.
> `Get-Process` on its own line) will corrupt the result. `Invoke-PrtgSensor` discards that
> output for you. **To debug, log to a file** — e.g.
> `"$(Get-Date -f o) checking disk" | Add-Content C:\Temp\mysensor.log` — never to output.

## 📊 Channels

`New-PrtgChannel` builds a single channel. Pipe each one to `Add-PrtgChannel`.
PRTG allows a **maximum of 50 channels** per sensor — adding a 51st throws.

```powershell
# Percentage with a float value and lower limits
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  New-PrtgChannel -Channel 'Disk Free %' -Value 25.0 -Unit Percent -Float `
    -LimitMinWarning 20 -LimitMinError 10 -LimitMode $true |
    Add-PrtgChannel

  # Response time with upper limits and a custom warning message
  New-PrtgChannel -Channel 'Response Time' -Value 120 -Unit TimeResponse `
    -LimitMaxWarning 100 -LimitMaxError 500 -LimitWarningMsg 'Slow' -LimitMode $true |
    Add-PrtgChannel

  # One channel per process
  Get-Process | ForEach-Object {
    New-PrtgChannel -Channel $_.ProcessName -Value $_.CPU -Float
  } | Add-PrtgChannel
}
```

Use `-Float` (or pass a decimal value) whenever the value is not a whole number, otherwise
PRTG may show `0`. See `Get-Help New-PrtgChannel -Full` for every unit, limit, and lookup
parameter.

## 🔀 Running in 64-bit PowerShell or in PowerShell 7+

PRTG starts custom sensors in **32-bit Windows PowerShell 5.1**. If you need 64-bit-only
modules or PowerShell 7+ features, call the matching helper right after import — it re-invokes
your script in the right host (keeping the original arguments) and exits, so the rest of your
script can assume the correct runtime. Both are no-ops when already in the target host.

```powershell
Import-Module PrtgSensorKit

Restart-As64BitPowershell   # ensure 64-bit
Restart-InPwsh              # ensure PowerShell 7+ (warns and continues if pwsh is absent)

Invoke-PrtgSensor {
  # Import the modules your sensor needs AFTER the restart, not before
  Import-Module SqlServer

  # your sensor code here
}
```

> [!WARNING]
> **Import the modules your sensor needs _after_ the `Restart-*` call, not before.** The
> 32-bit Windows PowerShell that PRTG starts cannot load 64-bit-only modules, and Windows
> PowerShell cannot load PowerShell 7 modules. If you `Import-Module` such a module _before_
> `Restart-As64BitPowershell` / `Restart-InPwsh`, the import fails in the wrong host before the
> relaunch ever happens. Call the `Restart-*` helper first; the script re-runs in the target
> host, and your `Import-Module` lines after it load the modules where they are actually
> visible. (`Import-Module PrtgSensorKit` itself is fine anywhere — it works in every edition.)

> [!WARNING]
> Never call the `Restart-*` helpers inside the `Invoke-PrtgSensor` script block.

## 🔐 Credentials and secrets

Don't put API tokens or passwords in your sensor script in plain text. `Save-PrtgSecret` stores a
secret encrypted with Windows DPAPI (via `Export-Clixml`), and `Get-PrtgSecret` reads it back —
so the secret lives on disk protected, not in your code. Works for a `SecureString` (API token)
or a full `PSCredential` (user + password).

```powershell
# Sensor code — no secret in the script:
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
> the Windows credentials of the parent device"* — in which case the Windows credentials set on
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
> Administrators, and SYSTEM. Windows only — for local development on non-Windows, add
> `-AllowUnprotected` to store the secret **obfuscated, not encrypted** (a warning is printed;
> never use it for real credentials).

## 💾 State between runs

Sensors often need yesterday's number to make sense of today's: rates from ever-growing
counters, caching an expensive lookup, or averaging the last hour of samples.
`Save-PrtgSensorState` appends a value (with a UTC timestamp) to a per-key history on
disk, and `Get-PrtgSensorState` reads it back on the next run:

```powershell
Invoke-PrtgSensor {
  $total = (Invoke-RestMethod -Uri $statsUrl).totalRequests

  # Last run's counter, or $null on the very first run / when the data is too old
  $previous = Get-PrtgSensorState -Key 'MySensor.Total' -MaxAge (New-TimeSpan -Minutes 15) -Latest

  if ($null -ne $previous) {
    New-PrtgChannel -Channel 'Delta' -Value ($total - $previous) | Add-PrtgChannel
  }

  Save-PrtgSensorState -Key 'MySensor.Total' -Value $total -MaxEntries 10
}
```

Details worth knowing:

- **Never throws for missing data** - the first run gets `-Default` (or `$null`), so no
  special-casing is needed.
- **Histories, not single values** - `Get-PrtgSensorState` returns `Value` + `Timestamp`
  entries newest first; `-Latest` shortcuts to the newest bare value. `-MaxEntries` on
  save and `Clear-PrtgSensorState -MaxAge` keep histories from growing forever.
- **Safe under overlapping scans** - reads and writes are serialized with a file lock.
  `-TimeoutSeconds` controls how long to wait for it, `-Force` bypasses it. A leftover
  zero-byte `<Key>.clixml.lock` file is normal; remove it with
  `Clear-PrtgSensorState -ClearLock` if it bothers you.
- **Keys are machine-global** - prefix them with your sensor name (`'MySensor.Total'`)
  to avoid collisions.
- **Plain data on disk** (`%ProgramData%\PrtgSensorKit\State`) - values are stored
  unencrypted. A `SecureString`/`PSCredential` inside a value does stay DPAPI-encrypted
  (that is how `Export-Clixml` works on Windows), but unlike the secret cmdlets the state
  cmdlets make no promises about protection: no checks, no ACL hardening, no guard off
  Windows. For secrets, prefer `Save-PrtgSecret`.

See [20-sensor-state-between-runs.ps1](Examples/20-sensor-state-between-runs.ps1) for a
full rate-from-counter sensor.

## 🔁 Retrying flaky data sources

If your sensor talks to an endpoint that occasionally hiccups, let `Invoke-PrtgSensor`
retry the block instead of alerting on the first transient failure. `-RetryCount N` re-runs
a throwing block up to N additional times (total attempts = N + 1), with an optional
`-RetryDelaySeconds` pause between attempts. Output state is cleared before every attempt,
so a failed partial attempt never leaks channels into the result.

```powershell
Invoke-PrtgSensor -RetryCount 2 -RetryDelaySeconds 5 {
  $health = Invoke-RestMethod -Uri 'https://api.example.com/health' -TimeoutSec 10
  New-PrtgChannel -Channel 'Latency' -Value $health.latencyMs -Unit TimeResponse | Add-PrtgChannel
  Set-PrtgMessage 'API healthy'
}
```

Retries are visible in PRTG: on success after retries the message becomes
`API healthy (1/2 retries attempted)`, and if every attempt fails the error text starts
with `unsuccessful after 2 retries:`.

> [!WARNING]
> Keep `(RetryCount + 1) * (block runtime + delay)` below the PRTG sensor timeout,
> otherwise PRTG kills the sensor before the retries finish.

See [19-retries-transient-failures.ps1](Examples/19-retries-transient-failures.ps1).

## 🧪 Debugging a sensor with -DryRun

`-DryRun` runs the block exactly like a real run but returns the result as a PowerShell
object instead of the PRTG JSON string, so you can inspect channels and message without
reading JSON. Errors are rethrown with full details instead of being flattened into a PRTG
error response.

```powershell
# In a normal console:
$result = .\MySensor.ps1        # the script calls Invoke-PrtgSensor -DryRun { ... }
$result.prtg.result | Format-Table
$result.prtg.text
```

> [!WARNING]
> Remove `-DryRun` before deploying: a deployed dry run does not emit valid PRTG JSON.

See [18-dry-run-debugging.ps1](Examples/18-dry-run-debugging.ps1).

## 🩺 Diagnosing a sensor

`Invoke-PrtgSensorDoctor` analyzes a sensor script (it parses, never executes) and checks
for the classic mistakes: `Restart-*` in the wrong place, manual output calls inside the
`Invoke-PrtgSensor` block, a leftover `-DryRun`, web requests without TLS setup, output
after the sensor response, and more. On Windows it also probes whether PrtgSensorKit and
your imported modules are actually installed in the hosts the sensor runs in (32-bit
PowerShell 5.1, 64-bit, pwsh).

```powershell
Invoke-PrtgSensorDoctor -ScriptPath 'C:\...\Custom Sensors\EXEXML\MySensor.ps1'
```

A colored summary is printed to the console, and every check comes back as an object
(`CheckId`, `Severity`, `Message`, `Line`, `Recommendation`) for scripted use:

```powershell
$findings = Invoke-PrtgSensorDoctor -ScriptPath .\MySensor.ps1 -SkipEnvironmentChecks
$findings | Where-Object Severity -eq 'Error'
```

See [21-sensor-doctor.ps1](Examples/21-sensor-doctor.ps1).

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
> `-Full` is the one to reach for while writing a sensor — it lists every unit, limit, and
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

## ❌ Custom errors and output control

`Invoke-PrtgSensor` sets **all errors** to **terminating**, catches the error/exception object, and returns it as a parsed error response to PRTG.

```plaintext
line:22 char:13
--- message: The remote server returned an error: (500) Internal Server Error.
--- line: $Response = Invoke-RestMethod -Method Get -Uri $URL -Headers $Header
```

If you just want **some** errors to be non-terminating, you can override this by using the `-ErrorAction` parameter on the cmdlet or by setting the `$ErrorActionPreference` to `'SilentlyContinue'` and then back to `'Stop'` when you want `Invoke-PrtgSensor` to handle errors again.

See [16-making-errors-nonterminating.ps1](Examples/16-making-errors-nonterminating.ps1) for a more detailed example on how to make some errors non-terminating.

If you want even more fine-grained control over errors and output, you can use the lower-level cmdlets yourself.

```powershell
Import-Module PrtgSensorKit

# Always call Clear-PrtgOutput before defining any channels or setting a message/error to
# generate an empty output object in the scope
Clear-PrtgOutput

$API_URL = 'https://api.example.com/data'
$Header = @{
  'Authorization' = 'Bearer 1234567890'
}

try {
  $Response = Invoke-RestMethod -Method Get -Uri $API_URL -Headers $Header -ErrorAction Stop
  New-PrtgChannel -Channel 'Response' -Value $Response.Status | Add-PrtgChannel
  Write-PrtgOutput
} catch {
  Write-PrtgError -ErrorString 'My custom error message'
}
```

When manually using the lower-level cmdlets, make sure to follow some **important limitations**:
- **Every** command's output has to be piped into a channel, assigned to a variable, or sent to `Out-Null` — there's no output guard here.
- **On your happy path**, call `Write-PrtgOutput` to emit the sensor JSON.
- **On your error path**, call `Write-PrtgError` to emit an error response.
- **`Write-PrtgOutput` and `Write-PrtgError` should always short-circuit the execution of your script**, otherwise the output will be corrupted.

See [04-manual-output-and-errors.ps1](Examples/04-manual-output-and-errors.ps1) for a more detailed example on how to use the lower-level cmdlets.

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