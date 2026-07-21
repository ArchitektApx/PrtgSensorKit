# Changelog

All notable changes to PrtgSensorKit are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-07-21

All changes are strictly additive: no existing cmdlet, parameter, default, or output
shape changed. Sensors written against 1.0.0 behave identically after upgrading.

### Added

- `Invoke-PrtgSensor -DryRun`: returns the sensor result as an inspectable
  `PSCustomObject` instead of the PRTG JSON string, for debugging in a normal console.
  Errors are rethrown with full details instead of being flattened into a PRTG error
  response. ([Examples/18](Examples/18-dry-run-debugging.ps1))
- `Invoke-PrtgSensor -RetryCount` / `-RetryDelaySeconds`: re-runs a throwing script
  block up to N additional times with an optional pause. Output state is cleared before
  every attempt. Success after retries appends `(n/max retries attempted)` to the sensor
  message; total failure prefixes the error text with `unsuccessful after N retries:`.
  ([Examples/19](Examples/19-retries-transient-failures.ps1))
- `Invoke-PrtgSensor -ForceModernTls`: switches the process to TLS 1.2 (plus TLS 1.3
  when the runtime supports it) before the block runs. Replaces the manual
  `[Net.ServicePointManager]` one-liner Windows PowerShell 5.1 web requests needed.
  ([Examples/22](Examples/22-force-modern-tls.ps1))
- `Save-PrtgSensorState` / `Get-PrtgSensorState` / `Clear-PrtgSensorState`: persist
  arbitrary data between sensor runs (caching, deltas, rates). Entries carry UTC
  timestamps; `-MaxAge` filters or prunes by age, `-Latest` returns the newest bare
  value, `-MaxEntries` caps history growth. Reads and writes are serialized with an
  exclusive, crash-safe file lock (`-TimeoutSeconds` to bound the wait, `-Force` to
  bypass, `Clear-PrtgSensorState -ClearLock` to remove the lock sidecar).
  ([Examples/20](Examples/20-sensor-state-between-runs.ps1))
- `Invoke-PrtgSensorDoctor`: static analysis (AST only, never executes the script) plus
  environment diagnosis for sensor scripts. Ten script checks (PSK0001-PSK0010: syntax,
  import order, Restart-* placement, manual output calls inside the block, multiple or
  missing `Invoke-PrtgSensor`, trailing output, missing TLS setup, leftover `-DryRun`)
  and four environment checks (PSK0101-PSK0104: PrtgSensorKit and dependency modules
  resolvable in the 32-bit / 64-bit / pwsh hosts the sensor actually runs in). Prints a
  colored summary and returns one finding object per check.
  ([Examples/21](Examples/21-sensor-doctor.ps1))
- Integration sensors under `Tests/Integration/` (working, failing, and malformed
  categories) for manual end-to-end validation on a real PRTG probe before a release, with
  a validation matrix mapping each script to its expected PRTG result and
  `Invoke-PrtgSensorDoctor` verdict.

### Changed

- README: new sections for state between runs, retries, `-DryRun` debugging, and the
  sensor doctor; the TLS tip now recommends `-ForceModernTls`.
- Module manifest `ReleaseNotes` points at `CHANGELOG.md` so the PowerShell Gallery page
  links to the full history.

## [1.0.0] - 2026-07-19

### Added

- Initial release.
- `Invoke-PrtgSensor`: wraps a sensor script block with clean state, terminating error
  handling, an output guard against stray stdout writes, and exactly one valid PRTG
  response (JSON or error).
- Channel building: `New-PrtgChannel` (units, limits, lookups, floats),
  `Add-PrtgChannel` (max 50 channels enforced), `Set-PrtgMessage` / `Get-PrtgMessage`
  (`#` stripped, 2000-char cap).
- Low-level output control: `Write-PrtgOutput`, `Write-PrtgError`, `Clear-PrtgOutput`,
  `Set-PrtgOutput`.
- Runtime helpers: `Restart-As64BitPowershell` and `Restart-InPwsh` relaunch the sensor
  in the right host, preserving arguments and exit codes.
- Secret storage: `Save-PrtgSecret` / `Get-PrtgSecret` with Windows DPAPI encryption and
  NTFS ACL hardening.
- Full comment-based help on every command, 17 runnable examples, Pester suite run
  against the built module on Windows PowerShell 5.1 and PowerShell 7.

[Unreleased]: https://github.com/ArchitektApx/PrtgSensorKit/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/ArchitektApx/PrtgSensorKit/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/ArchitektApx/PrtgSensorKit/releases/tag/v1.0.0
