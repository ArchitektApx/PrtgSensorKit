# Changelog

All notable changes to PrtgSensorKit are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] - 2026-07-27

### Added

- `Use-PrtgCachedResult -SkipNullCache`: treats a `$null` result as nothing worth caching, so a
  stored `$null` is ignored on read and a `$null` returned by the block is not written. Off by
  default: a source that keeps returning `$null` is then refetched by every sensor on every
  interval instead of once. Use it when a `$null` means the fetch failed and a retry is worth
  the extra calls.
- `Use-PrtgCachedResult -Depth`: serialization depth for the cached value, same meaning and
  default (5) as on `Save-PrtgSensorState`. The refresh previously always wrote at depth 5 with
  no way to raise it, so a cached CIM instance or FileInfo lost its nested properties.
- `./tasks.ps1 coverage`: runs the suite with code coverage and lists every missed command.
  `-MinimumPercent` fails the run below a threshold. Coverage is per host, so compare hosts
  before calling a line untested.
- `Tools/deploy_to_testvm.sh`: deploys the working tree to a Windows test VM, runs the suite on
  Windows PowerShell 5.1 (x64 and x86) and pwsh 7, installs the built module for both editions,
  and deploys the integration sensors to a PRTG probe. For developing on macOS, Linux, or WSL;
  remote paths are overridable with `TESTVM_REPO` / `TESTVM_EXEXML`.
- `Tools/README.md`: what each developer tool does and how to run it.
- Integration sensors for the 1.3.0 changes: `working/20` + `failing/21` (a secret saved by the
  sensor's own account vs. by the wrong one), `failing/22` + `working/23` (a non-terminating error
  failing the sensor, and the supported opt-outs), and `working/24` (raw CIM `UInt64` values,
  including one above 2^53).

### Changed

- **`Invoke-PrtgSensor` now really applies `$ErrorActionPreference = 'Stop'` to your script
  block.** It always claimed to, but the setting did not actually reach your block. A
  NON-terminating error inside the block was therefore written to stderr and discarded, and the
  sensor reported GREEN with missing or stale channels. Such a sensor now correctly reports an
  error.
  **This can turn previously green sensors red**, where the old behavior was hiding a real
  failure. To let a specific command keep failing quietly, use `-ErrorAction` on that statement,
  or assign `$ErrorActionPreference` INSIDE the block; see
  [`Examples/16-making-errors-nonterminating.ps1`](Examples/16-making-errors-nonterminating.ps1).
  Note that setting `$ErrorActionPreference` at the top of the sensor SCRIPT does not opt out; it
  has to be inside the block, or per command via `-ErrorAction`.
- **`Save-PrtgSecret` no longer ACL-locks the secret store FOLDER**, only the individual secret
  files. The store folder is shared by every sensor account on a probe, but each save re-locked it
  to whichever account ran the save - cutting all the other accounts off from their own secret
  files, which were still perfectly intact.

  **Does this need action on upgrade?**

  - **Sensors run as Local System only** (the PRTG default): no. Local System and Administrators
    always kept access, so your store keeps working untouched.
  - **Some other account also uses the store**: yes, once. That account was already locked out
    before 1.3.0, and 1.3.0 does not clear the old folder ACL for you. As an administrator:

    ```powershell
    Remove-Item "$env:ProgramData\PrtgSensorKit\Secrets" -Recurse -Force
    # then re-save each secret, running as the sensor account that needs it
    ```

  Secret files themselves are unchanged: each stays locked to the account that saved it, plus
  Administrators and SYSTEM. They are now locked down before the secret is written into them, so a
  file is never briefly readable under inherited permissions.
- `Tools/lint.ps1` now fails on warnings, not only on errors, matching the compatibility check.
- `Tools/build.ps1` and `Tools/install_dev_requirements.ps1` include the underlying error when
  they fail, instead of only reporting that the step failed.
- Docs updated for the above: `Docs/resilience.md` gains a section on terminating errors inside
  the block, `Docs/secrets.md` covers multiple sensor accounts and the upgrade step, and
  `Docs/state.md` / `Docs/shared-cache.md` spell out that `-Latest` maps a stored `$null` to
  `-Default` while the cache serves one as-is.

### Fixed

- `New-PrtgChannel -Value` accepted only `int`, `int64`, `float`, `double`, and `decimal`, and
  rejected every unsigned and small integer type. `UInt64` is what CIM and WMI return for nearly
  every size and counter (`Win32_LogicalDisk.FreeSpace`, `Get-Volume.SizeRemaining`,
  `Win32_OperatingSystem.FreePhysicalMemory`), so those values had to be cast before use. All
  built-in numeric types are now accepted - `byte`, `sbyte`, `int16`, `uint16`, `int32`, `uint32`,
  `int64`, `uint64`, `single`, `double`, `decimal` - on `-Value` and on the four `Limit*`
  parameters (which continue to accept strings).
  Integers keep their exact value in the JSON, so a `UInt64` above 2^53 is not rounded.
- `New-PrtgChannel` emitted explicitly bound COMMON parameters as channel properties, so
  `-Verbose` or `-ErrorAction SilentlyContinue` added `"Verbose":1` / `"ErrorAction":"..."` to the
  sensor JSON. Adding `-Verbose` while debugging silently changed the emitted payload. Common
  parameters are now excluded automatically, including `-ProgressAction` and anything future
  hosts add.
- `Invoke-PrtgSensor -EnableLogging -LogPath` left the process's log run file pointed at the
  `-LogPath` folder after returning. Every later `Write-PrtgLog` call in the same script went to
  that folder instead of the script's own log directory, splitting one run across two folders.
  The run file is now restored along with the directory and retention settings, and only when
  `-LogPath` actually redirected it - so a plain `-EnableLogging` call keeps the run file it
  created and later `Write-PrtgLog` calls still append to it.
- `Get-PrtgSensorState -Latest` returned a stored `$null` instead of falling back to `-Default`,
  so `$current - (Get-PrtgSensorState -Key 'k' -Latest -Default 0)` silently yielded `$current`.
  A stored `0`, `''`, or `$false` still comes back unchanged. `Use-PrtgCachedResult` deliberately
  keeps the opposite behaviour: a cached `$null` is a valid result and is served from the cache.
- `Save-PrtgSecret` could destroy an existing secret when a re-save failed part-way (for example
  DPAPI being unavailable on a network logon, or a full disk). `Export-Clixml` truncates the file
  before it writes, so the previous value was already gone by the time the write threw, leaving a
  truncated file that a later `Get-PrtgSecret` reported as a confusing decrypt error. The secret
  is now written to a temp file in the same folder and swapped in as a single step, so a failed
  save leaves the previous secret intact and no partial file behind, on every platform.
- `Save-PrtgSensorState` and `Clear-PrtgSensorState -MaxAge` wrote the state file directly, so a
  failure part-way through the write (full disk, a sensor killed on a PRTG timeout) emptied the
  file and lost the ENTIRE entry history - the next run reported it as unreadable and a delta
  counter silently fell back to `-Default` for one interval. Both now write to a temp file and
  swap it in, so a failed write leaves the previous history intact.
- `Save-PrtgSecret` reported a name already owned by another account as a raw
  `Access to the path ... is denied` naming its internal temp file. The error now names the
  secret, the target file, and the account the save is running as.
- `Save-PrtgSecret` left its temp file behind when the process was killed mid-save (a PRTG sensor
  timeout, a reboot). Stale temp files for a given secret name are now cleared on the next save of
  that name, and only when they are more than an hour old, so a second instance of the same sensor
  saving at the same moment is never disturbed.
- `Use-PrtgCachedResult` refreshed the cache with a direct write, so a failure part-way through
  (full disk, killed process) corrupted the shared cache entry and sent every sensor using that
  key back to the source at once. The refresh now writes a temp file and swaps it in, the same
  way `Save-PrtgSecret` does.
- `Get-PrtgSecret` returned `$null` for an empty or truncated secret file, because such a file
  deserializes to `$null` without raising an error. It now throws and names the file. With
  `-AsPlainText` this previously surfaced as `You cannot call a method on a null-valued
  expression`.
- `Get-PrtgSecret` reported a CORRUPT secret file (malformed XML from an interrupted write) as a
  DPAPI account mismatch, sending operators to check permissions for a problem no re-permissioning
  can fix. Malformed XML is now reported as file corruption; the account-mismatch wording is kept
  for real decrypt failures.
- `Get-PrtgSecret -AsPlainText` silently returned the raw object when the stored payload was
  neither a `PSCredential` nor a `SecureString` (only reachable via a hand-written clixml or a
  `-Path` aimed at a foreign store). It now throws and names the actual type instead of returning
  an object the caller asked to get as a string.
- `Write-PrtgOutput` and `Write-PrtgError` set `[Console]::OutputEncoding` without a guard. Under
  .NET Framework that setter can throw when the process has no attached console, and it runs
  BEFORE the response is written - so `Write-PrtgError` would have emitted nothing at the exact
  moment it mattered. Both are now guarded so the response is always emitted.

## [1.2.1] - 2026-07-23

### Fixed

- `Clear-PrtgSensorState -MaxAge`: the pruned re-export used a hardcoded `-Depth 10`, silently
  flattening state saved with `Save-PrtgSensorState -Depth` above that. `Clear-PrtgSensorState`
  now takes its own `-Depth` (default 10, matching the previous hardcoded value).
- `Write-PrtgError`: a hand-built `ErrorRecord` (as opposed to one from an actual `throw`) has a
  `$null` `InvocationInfo`; formatting one threw a `NullReferenceException` instead of emitting
  the PRTG error response. Missing invocation details now render as `unknown` instead of
  crashing.
- `Get-PrtgSensorState` / `Save-PrtgSensorState` / `Clear-PrtgSensorState` /
  `Use-PrtgCachedResult`: a state or cache file corrupted on disk (readable clixml, but with a
  malformed entry) could crash the cmdlet or silently return/store a broken entry. Malformed
  entries (missing `Value`/`Timestamp`, or a `Timestamp` that isn't a `DateTime`) are now
  dropped, with a warning, instead.

### Added

- `Tools/fuzz.ps1`: a mutation fuzzer (bit-flip/insert/delete/duplicate) exercising the sensor
  doctor, JSON output pipeline, sensor state store, error output, `Invoke-PrtgSensor`'s
  retry/`-DryRun` wrapper, and `Write-PrtgLog` against adversarial and corrupted input. Wired
  into `./tasks.ps1 fuzz` and gated on by `prepare_release` before every release.

## [1.2.0] - 2026-07-22

### Added

- `Write-PrtgLog`: safe, timestamped file logging for sensor debugging. One log file per
  sensor invocation (`<scriptname>_<timestamp>_<PID>.log`), so a failing run is one
  self-contained file and concurrent runs never interleave. Defaults to
  `%ProgramData%\PrtgSensorKit\Logs\<scriptname>\`; old run files are pruned
  automatically (newest 30 kept). Never throws, never touches stdout - logging can never
  turn a green sensor red.
- `Invoke-PrtgSensor -EnableLogging` (with optional `-LogPath` and `-MaxLogs`): opt-in
  lifecycle logging via `Write-PrtgLog` - sensor start, each retry, a success summary,
  and on failure the full error details (exception type, message, script line, stack
  trace) that PRTG's one-line error text flattens away. `-LogPath` and `-MaxLogs`
  require the switch; a relative `-LogPath` resolves against the script's folder.
  ([Examples/23](Examples/23-file-logging.ps1))
- `Use-PrtgCachedResult`: share one expensive call (REST response, SQL query, WMI sweep)
  across all sensors on a machine. Memoizes the script block's result with a TTL
  (`-MaxAge`), holding the state lock across check + fetch + write so concurrent sensors
  cannot stampede the source: exactly one fetch per expiry, guaranteed. Cache entries
  are ordinary sensor state (`Get-PrtgSensorState` inspects them, `Clear-PrtgSensorState`
  clears them).
  ([Examples/24](Examples/24-shared-collection-cache.ps1))
- Sensor doctor: three new script checks. PSK0011 warns when a script contains
  non-ASCII bytes without a BOM (Windows PowerShell 5.1 reads BOM-less files as ANSI
  and silently mangles umlauts under PRTG). PSK0012 reminds that channel limit values
  are snapshotted when the sensor is first created. PSK0013 reminds that DPAPI secrets
  only decrypt under the account that saved them when `Get-PrtgSecret` is used.
- Integration sensors for the new features: `working/17` (lifecycle logging to the
  default folder under the probe account), `working/18` (shared cache across multiple
  deployed sensors), and `malformed/19` (BOM-less non-ASCII fixture the Doctor flags as
  PSK0011 and PRTG displays as mojibake).

### Fixed

- `Get-PrtgSensorState -Latest` (and the cache hit path of `Use-PrtgCachedResult`) could
  return an OLDER entry when two saves landed within the clock resolution of
  `[DateTime]::UtcNow` (~15 ms on Windows PowerShell 5.1) and their timestamps tied.
  Ties now resolve to the last-appended entry.

### Changed

- Documentation restructured: the README now covers install, quickstart, and navigation;
  per-topic detail moved to `Docs/` (installation, channels, runtime hosts, secrets,
  state, shared cache, logging, resilience, debugging, low-level output). The doctor's
  PSK0013 recommendation points at `Docs/secrets.md` accordingly.
- README: the debug tip now shows `Write-PrtgLog` instead of hand-rolled `Add-Content`;
  the parameterized sensor example now reminds to quote PRTG placeholders
  (`-DeviceName '%device'`).

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

[Unreleased]: https://github.com/ArchitektApx/PrtgSensorKit/compare/v1.3.0...HEAD
[1.3.0]: https://github.com/ArchitektApx/PrtgSensorKit/compare/v1.2.1...v1.3.0
[1.2.1]: https://github.com/ArchitektApx/PrtgSensorKit/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/ArchitektApx/PrtgSensorKit/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/ArchitektApx/PrtgSensorKit/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/ArchitektApx/PrtgSensorKit/releases/tag/v1.0.0
