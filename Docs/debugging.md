# 🩺 Diagnosing and debugging a sensor

Three tools, in the order you typically reach for them: the **doctor** finds script
mistakes without running anything, **`-DryRun`** shows the sensor result as objects in
your console, and **file logging** captures what happens on the probe where you cannot
watch. Logging has [its own page](logging.md); this one covers the doctor and `-DryRun`.

## The sensor doctor

`Invoke-PrtgSensorDoctor` analyzes a sensor script (it parses, never executes) and checks
for the classic mistakes: `Restart-*` in the wrong place, manual output calls inside the
`Invoke-PrtgSensor` block, a leftover `-DryRun`, web requests without TLS setup, output
after the sensor response, unsafe file encoding, and more. On Windows it also probes
whether PrtgSensorKit and your imported modules are actually installed in the hosts the
sensor runs in (32-bit PowerShell 5.1, 64-bit, pwsh).

```powershell
Invoke-PrtgSensorDoctor -ScriptPath 'C:\...\Custom Sensors\EXEXML\MySensor.ps1'
```

A colored summary is printed to the console, and every check comes back as an object
(`CheckId`, `Severity`, `Message`, `Line`, `Recommendation`) for scripted use:

```powershell
$findings = Invoke-PrtgSensorDoctor -ScriptPath .\MySensor.ps1 -SkipEnvironmentChecks
$findings | Where-Object Severity -eq 'Error'
```

See [21-sensor-doctor.ps1](../Examples/21-sensor-doctor.ps1).

## Debugging with -DryRun

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
> The doctor catches a leftover `-DryRun` (check PSK0010).

See [18-dry-run-debugging.ps1](../Examples/18-dry-run-debugging.ps1).

## When it only breaks under PRTG

Console testing can lie: PRTG runs the script in 32-bit 5.1, as the probe account, with a
different working directory. When a sensor works in your console but fails deployed, add
`-EnableLogging` and read the run log from the probe - see [File logging](logging.md).
For secrets that fail only at runtime, see the account-binding note in
[Credentials and secrets](secrets.md).
