# 📝 File logging

PRTG reads the sensor result from stdout, so anything you want to record - progress,
timings, diagnostics, or the details of a failure - has to go to a file. `Write-PrtgLog`
is that file writer, batteries included: timestamped lines, one file per run, automatic
cleanup, and it can never interfere with the sensor result. Use it for plain operational
logging as much as for debugging.

`Invoke-PrtgSensor -EnableLogging` adds automatic lifecycle entries on top: sensor start,
every retry, a success summary, and on failure the **full** error details (exception
type, message, script line, stack trace) that PRTG flattens into one error line.

```powershell
# zero-config: logs to %ProgramData%\PrtgSensorKit\Logs\<scriptname>\
Invoke-PrtgSensor -EnableLogging {
  Write-PrtgLog "querying $ApiUrl"
  ...
}

# custom folder next to the script, keep the last 10 runs
Invoke-PrtgSensor -EnableLogging -LogPath "$PSScriptRoot\Logs" -MaxLogs 10 { ... }
```

Details worth knowing:

- **One file per run** (`<scriptname>_<timestamp>_<PID>.log`), so a failing run is one
  self-contained file and concurrent runs never write into each other. The newest 30
  files are kept (`-MaxLogs` to change); to inspect the latest run:
  `Get-ChildItem $env:ProgramData\PrtgSensorKit\Logs\MySensor | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Get-Content`
- **Logging can never break the sensor** - `Write-PrtgLog` never throws and writes
  nothing to the output stream; a full disk or bad path just drops the entry.
- **`Write-PrtgLog` also works standalone** (manual low-level scripts, no wrapper):
  it writes to the default folder above.
- **Location and retention are configured in one place** - `-LogPath` and `-MaxLogs`
  belong to `Invoke-PrtgSensor` and require `-EnableLogging`. If entries were already
  written to a different folder earlier in the run, `-LogPath` starts a new run file in
  the configured one.
- **Line format**: ISO 8601 local timestamp with UTC offset, a level tag
  (`-Level Info|Warning|Error|Debug`, a label only - nothing is filtered), then your
  message. UTF-8 on disk (with BOM under Windows PowerShell 5.1).
- A relative `-LogPath` resolves against the script's folder, not the working directory
  (PRTG starts sensors with an unhelpful CWD).
- **Don't log secret values** - nothing is redacted
  (see [Credentials and secrets](secrets.md)).

For the interactive debugging workflow (`-DryRun`, the sensor doctor), see
[Diagnosing and debugging](debugging.md).

See [23-file-logging.ps1](../Examples/23-file-logging.ps1).
