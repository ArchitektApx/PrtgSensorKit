# 🧩 Installation: where the module and your dependencies must go

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

`Import-Module PrtgSensorKit` works in every edition, so the module itself is never the problem -
but **the modules _your_ sensor imports must be installed in the host where your code actually
runs**, which depends on whether you call a `Restart-*` helper:

| Your sensor... | Install your dependency modules for |
| --- | --- |
| uses no `Restart-*` | 32-bit Windows PowerShell 5.1 (what PRTG starts) |
| calls `Restart-As64BitPowershell` | 64-bit Windows PowerShell 5.1 |
| calls `Restart-InPwsh` | PowerShell 7+ (pwsh) |

For Windows PowerShell, one `Install-Module` covers both the 32-bit and the 64-bit host: they
share the same module folders. The exception is modules with **native/architecture-specific**
components (e.g. `SqlServer`). For those, run the install from a process of the **matching
bitness**, so the correct binaries are downloaded.

Then *always* put your `Import-Module` lines **after** the `Restart-*` call - see
[Running in 64-bit PowerShell or in PowerShell 7+](runtime-hosts.md) for why.

On Windows, `Invoke-PrtgSensorDoctor` probes whether PrtgSensorKit and your imported modules are
actually resolvable in the hosts your sensor runs in; see [Diagnosing and debugging](debugging.md).
