# 🔀 Running in 64-bit PowerShell or in PowerShell 7+

PRTG starts custom sensors in **32-bit Windows PowerShell 5.1**. If you need 64-bit-only
modules or PowerShell 7+ features, call the matching helper right after import - it re-invokes
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
> visible. (`Import-Module PrtgSensorKit` itself is fine anywhere - it works in every edition.)

> [!WARNING]
> Never call the `Restart-*` helpers inside the `Invoke-PrtgSensor` script block. The
> relaunched child process's output would be discarded by the wrapper's output guard.

Remember that the target host also needs your dependency modules installed - see
[Installation](installation.md) for the matrix.

See [06-relaunch-64bit-and-pwsh.ps1](../Examples/06-relaunch-64bit-and-pwsh.ps1).
