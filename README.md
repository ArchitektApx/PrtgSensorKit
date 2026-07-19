<div align="center">

# 📡 PrtgSensorKit

**PowerShell framework for building [PRTG](https://www.paessler.com/) custom EXE/Script Advanced sensors — less boilerplate, valid JSON output every time.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/Version-1.0.0-green.svg)](CHANGELOG.md)
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

If your sensor uses `Restart-InPwsh`, also install it in **PowerShell 7+**, which has its own
module path:

```powershell
# Run from pwsh
Install-Module PrtgSensorKit -Scope AllUsers
```

`Import-Module PrtgSensorKit` works in every edition, so the module itself is never the problem —
but **the modules _your_ sensor imports must be installed in the host where your code actually
runs**, which depends on whether you call a `Restart-*` helper:

| Your sensor... |  Install your dependency modules for |
| --- | --- |
| uses no `Restart-*` | 32-bit Windows PowerShell 5.1 (what PRTG starts)
| calls `Restart-As64BitPowershell` | 64-bit Windows PowerShell 5.1
| calls `Restart-InPwsh` | PowerShell 7+ (pwsh)

For Windows PowerShell the AllUsers/CurrentUser module folders are shared between the 32-bit and
64-bit hosts, so a normal `Install-Module` makes a script module visible to both but the bitness still matters for modules with **native/architecture-specific** components (e.g. `SqlServer`): 

*always* run the install from a process of the matching bitness so the correct binaries are present!

Then *always* put your `Import-Module` lines **after** the `Restart-*` call (see the
*Running in 64-bit PowerShell or in PowerShell 7+* section below for more details).

## 🚀 Your first PRTG sensor

Save this as an `EXE/Script Advanced` sensor script in
`C:\Program Files (x86)\PRTG Network Monitor\Custom Sensors\EXEXML\`:

```powershell
# Stop on the first error so the trap below catches it (required for the trap pattern)
$ErrorActionPreference = 'Stop'

Import-Module PrtgSensorKit

# Report any unhandled error to PRTG as a sensor error, then stop
trap {
  $_ | Write-PrtgError
  return
}

# Your code to gather metrics here
# Example:
$cpuUsage = Get-Process | 
  ForEach-Object { $_.CPU } | 
  Measure-Object -Average | 
  Select-Object -ExpandProperty Average

# Add one or more channels
New-PrtgChannel -Channel 'CPU Usage' -Value $cpuUsage -Unit Percent | Add-PrtgChannel

# Optional sensor message
Set-PrtgMessage 'CPU usage average'

# Emit the JSON PRTG reads
Write-PrtgOutput
```

> **Making web requests in your sensor?** On Windows PowerShell 5.1, enable TLS 1.2 first:
> `[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12`

## 🎁 Batteries-included: `Invoke-PrtgSensor`

New to this? Skip the boilerplate. Put your channel-building logic in a script block and
`Invoke-PrtgSensor` handles the rest — it sets `$ErrorActionPreference`, catches errors and
turns them into a PRTG error response, keeps stray output from corrupting the result (see the
warning below), and emits exactly one valid response:

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

Inside the block, build channels and set the message — **do not** call `Write-PrtgOutput` or
`Write-PrtgError` yourself; the wrapper emits the single response.

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

> ⚠️ **Never write to the output stream in your sensor code.** PRTG reads the sensor result
> from the process **standard output**, which must contain **only** the JSON. A stray
> `Write-Host`, a bare `Write-Output`, or an un-captured command that returns objects (e.g.
> `Get-Process` on its own line) will corrupt the result. `Invoke-PrtgSensor` discards that
> output for you; with the manual pattern, make sure every command's output is piped into a
> channel, assigned to a variable, or sent to `Out-Null`. **To debug, log to a file** — e.g.
> `"$(Get-Date -f o) checking disk" | Add-Content C:\Temp\mysensor.log` — never to output.

## 📊 Channels

`New-PrtgChannel` builds a single channel. Pipe each one to `Add-PrtgChannel`.
PRTG allows a **maximum of 50 channels** per sensor — adding a 51st throws.

```powershell
# Percentage with a float value and lower limits
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

Write-PrtgOutput
```

Use `-Float` (or pass a decimal value) whenever the value is not a whole number, otherwise
PRTG may show `0`. See `Get-Help New-PrtgChannel -Full` for every unit, limit, and lookup
parameter.

## ❌ Returning errors to PRTG

A PRTG error response replaces all channel data with a single error message.

```powershell
# Simple message
Write-PrtgError -ErrorString 'My error message'

# From a try/catch (includes line/char/message)
try {
  # your code here
} catch {
  $_ | Write-PrtgError
}
```

The number sign (`#`) is stripped and messages are truncated to 2000 characters automatically,
as PRTG requires.

## 🔀 Running in 64-bit PowerShell or in PowerShell 7+

PRTG starts custom sensors in **32-bit Windows PowerShell 5.1**. If you need 64-bit-only
modules or PowerShell 7+ features, call the matching helper right after import — it re-invokes
your script in the right host (keeping the original arguments) and exits, so the rest of your
script can assume the correct runtime. Both are no-ops when already in the target host.

```powershell
Import-Module PrtgSensorKit
$ErrorActionPreference = 'Stop'
trap { $_ | Write-PrtgError; return }

Restart-As64BitPowershell   # ensure 64-bit
Restart-InPwsh              # ensure PowerShell 7+ (warns and continues if pwsh is absent)

# Import the modules your sensor needs AFTER the restart, not before (see warning)
Import-Module SqlServer

# your sensor code here
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
> **Using `Invoke-PrtgSensor`?** Call the `Restart-*` helpers at the top of your script,
> **before** `Invoke-PrtgSensor` — never inside the block. They relaunch the sensor as a child
> process, and its output would be discarded by the wrapper's output guard (the sensor would
> emit nothing). `Import-Module` inside the block is fine.
>
> ```powershell
> Import-Module PrtgSensorKit
> Restart-As64BitPowershell # top level, before the wrapper
> Invoke-PrtgSensor { <# channels here #> }
> ```

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
>`-Full` is the one to reach for while writing a sensor — it lists every unit, limit, and
> lookup parameter with a description. This works for all commands below.

## 🧰 Commands

| Command | Purpose |
| --- | --- |
| [`Invoke-PrtgSensor`](Source/Public/Invoke-PrtgSensor.ps1) | Run a sensor block with boilerplate, error handling, and output hygiene handled |
| [`New-PrtgChannel`](Source/Public/New-PrtgChannel.ps1) | Build a channel object |
| [`Add-PrtgChannel`](Source/Public/Add-PrtgChannel.ps1) | Add a channel to the sensor output (max 50) |
| [`Set-PrtgMessage`](Source/Public/Set-PrtgMessage.ps1) | Set the sensor message |
| [`Get-PrtgMessage`](Source/Public/Get-PrtgMessage.ps1) | Read the current sensor message |
| [`Write-PrtgOutput`](Source/Public/Write-PrtgOutput.ps1) | Emit the sensor JSON |
| [`Write-PrtgError`](Source/Public/Write-PrtgError.ps1) | Emit a PRTG error response |
| [`Clear-PrtgOutput`](Source/Public/Clear-PrtgOutput.ps1) | Clear channels and message |
| [`Set-PrtgOutput`](Source/Public/Set-PrtgOutput.ps1) | Replace the entire output object (advanced) |
| [`Save-PrtgSecret`](Source/Public/Save-PrtgSecret.ps1) | Store an API token or credential, DPAPI-encrypted |
| [`Get-PrtgSecret`](Source/Public/Get-PrtgSecret.ps1) | Read a stored secret in a sensor |
| [`Restart-As64BitPowershell`](Source/Public/Restart-As64BitPowershell.ps1) | Re-launch the sensor in 64-bit PowerShell |
| [`Restart-InPwsh`](Source/Public/Restart-InPwsh.ps1) | Re-launch the sensor in PowerShell 7+ |

## 🛠️ Building from source

```powershell
./tasks.ps1 install_dev_requirements   # ModuleBuilder, Configuration, Pester, PSScriptAnalyzer
./tasks.ps1 lint                       # PSScriptAnalyzer style + 5.1/7.0 compatibility checks
./tasks.ps1 build                      # builds to ./Dist, then runs the Pester suite
./tasks.ps1 test                       # runs the Pester suite against the built module
```

## 📄 License

Released under the [MIT License](LICENSE).