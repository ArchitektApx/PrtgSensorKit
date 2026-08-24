# Changelog

All notable changes to PrtgSensorKit are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **`Save-PrtgSecret` now writes through the same crash-safe sequence as the state store.** It
  kept a parallel copy of that sequence, so the last two crash-safety fixes each had to be made
  twice, months apart. The shared writer gained a before-write and an after-swap hook, and the
  secret store hardens its file ACL through those: the blob still never exists under inherited
  permissions, and the destination is still re-locked after the swap. Nothing changes for a
  sensor script. Two details worth knowing for anyone looking at the store folder: a secret's
  temporary file is now named `<Name>.clixml.<guid>.tmp` rather than `<Name>.<guid>.tmp`, and
  leftovers in both naming generations are swept. The secret payload is now serialized at the
  shared writer's depth of 5 instead of `Export-Clixml`'s implicit 2; secrets written before
  this release read back unchanged.

- **The secret store folder is resolved in one place.** `Save-PrtgSecret` and `Get-PrtgSecret`
  each resolved it inline with an identical copy of the same code. Where a secret lives is now
  answered by a single private resolver, and that answer is covered by tests that need no DPAPI.
  The resolved folder is unchanged, on Windows and off it, and reading a secret still never
  creates the folder.

### Fixed

- **`Get-PrtgSensorState` can no longer name two different entries as the newest one.** The
  entry history and `-Latest` ordered by different rules, so the same file could answer the
  same question two ways in a single call. Both now compare timestamps in UTC and break ties
  in favour of the entry appended last. Two saves inside one clock tick were enough to hit the
  tie case, and `[DateTime]::UtcNow` has roughly 15 ms resolution on .NET Framework. Histories
  written by the module are unaffected in value: it only ever stores UTC timestamps, and
  `Export-Clixml` preserves that, so the normalization is the identity transform on them.

## [1.4.0] - 2026-07-31

### Added

- **Resolved PRTG credential placeholders are masked in sensor messages, error text, and log
  files.** PRTG's manual warns that placeholders are resolved *before* the output is displayed,
  so a credential echoed back in an error message - a failing `Invoke-RestMethod` that includes
  the full request URI, say - ends up on screen in the clear. The module now registers the
  values it can know about and masks them on the way out:

  - the resolved `prtg_windowspassword`, `prtg_linuxpassword`, and `prtg_snmpcommunity`
    environment variables, when *"Set placeholders as environment values"* is enabled in the
    sensor settings. These hold the same strings the command line received, so this also
    covers a credential passed as a script parameter. User names, domains, and host names are
    deliberately **not** masked: they are not secrets and hiding them only makes
    troubleshooting harder. Neither are the RFC 1157 default SNMP communities `public` and
    `private`, which are not secrets and are far too common as ordinary words to mask;
  - every value returned by `Get-PrtgSecret -AsPlainText`.

  Masking is partial so an operator can still tell *which* credential leaked: values of 12
  characters or more keep their first few characters (at most six), shorter values are masked
  entirely, and the asterisk mask itself is always five characters, so the output never grows
  with the secret. Values under six characters are never registered - masking those would
  mangle ordinary text for no real protection.

  Nothing to configure and nothing to opt into. See the limitations in
  [`Docs/secrets.md`](Docs/secrets.md) - notably that only exact substring matches are found
  (a URL-encoded or base64'd form is not), and that `Set-PrtgOutput`, `Write-PrtgOutput`,
  channel names/values, and `Invoke-PrtgSensor -DryRun` are not covered.

### Security

- The masking above is **defence in depth, not a guarantee**. It reduces the blast radius of an
  accidental credential leak into sensor output; it does not make credentials safe to log. Keep
  treating credentials as sensitive and keep them out of messages you build yourself.

### Changed

- **`Add-PrtgChannel` now rejects a duplicate channel name.** PRTG's manual requires the
  `<Channel>` name to be *"unique for the sensor"*; the module enforced the 50-channel cap but
  not uniqueness. Adding a name that was already added now throws, and the comparison is
  case-insensitive (`CPU` and `cpu` in one sensor is a bug in every realistic case).

  **This can turn previously green sensors red.** Duplicates are easy to generate accidentally
  from process, service, or disk names - an ordinary machine has 80+ process names with more
  than one instance. Aggregate first, and cap the result: the same machine has well over 50
  distinct process names, which would hit the 50-channel limit instead.

  ```powershell
  Get-Process | Group-Object ProcessName |
    Sort-Object { ($_.Group | Measure-Object CPU -Sum).Sum } -Descending |
    Select-Object -First 10 | ForEach-Object {
      New-PrtgChannel -Channel $_.Name -Value ($_.Group | Measure-Object CPU -Sum).Sum -Unit CPU -Float
    } | Add-PrtgChannel
  ```

  The `Add-PrtgChannel` help example and [`Docs/channels.md`](Docs/channels.md) demonstrated the
  broken pattern and have been rewritten to the aggregated, capped form above.

### Fixed

- **Log retention no longer deletes files this module did not create.** The `-MaxLogs` sweep in
  `Write-PrtgLog` matched every `*.log` file in the log directory, so it deleted whatever it
  found beyond the retention count. With the default `-MaxLogs 30` and an
  `Invoke-PrtgSensor -EnableLogging -LogPath` pointed at a folder holding 40 unrelated
  application logs, 11 of them were destroyed on the first run - and two sensor scripts sharing
  one `-LogPath` (the layout the help recommends, `-LogPath "$PSScriptRoot\Logs"`) silently
  pruned each other's history. The sweep now only considers files matching this script's own
  run-file shape, `<scriptname>_<yyyyMMdd-HHmmss>_<pid>.log`.

  Note that retention is therefore **per script name**: run files left behind by a sensor script
  that has since been renamed are no longer pruned automatically. Never deleting a file we did
  not create is worth that.

- **A relative `-Path` no longer sends the state lock to a different folder than the state
  file.** The `.lock` sidecar is handed straight to `[System.IO.FileStream]`, and .NET resolves
  a relative path against the *process* working directory, which is not PowerShell's current
  location. `Save-PrtgSensorState -Key k -Value 42 -Path 'store'` therefore either stalled for
  the full `-TimeoutSeconds` and then blamed a concurrent sensor run that did not exist, or -
  when a `store` folder happened to exist under both - wrote the state file and its lock into
  two different directories, so concurrent runs serialized on different locks while writing the
  same file. PRTG starts sensors with an unhelpful working directory, so this was reachable in
  production. The path is now normalised once in the shared resolver, so the folder, the state
  file, and the lock can never disagree.

- **A state lock in a folder that does not exist now fails immediately** with a message naming
  the missing folder, instead of retrying until the timeout and reporting a lock conflict.
  `DirectoryNotFoundException` derives from `IOException` and was landing in the retry arm.

- Internal: every parameter and local in the private `Invoke-PrtgStateLock` is now prefixed
  `PrtgLock`. A script block passed to it resolves unqualified variable names up the dynamic
  chain - the lock's own frame first - so its former parameter names (`LockFile`,
  `ScriptBlock`, `TimeoutSeconds`, `Force`, `DeleteLockOnRelease`) were an undocumented reserved
  list that would silently shadow a caller's variable of the same name. This had already bitten
  once inside `Use-PrtgCachedResult`, whose workaround is now removed.

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

[Unreleased]: https://github.com/ArchitektApx/PrtgSensorKit/compare/v1.4.0...HEAD
[1.4.0]: https://github.com/ArchitektApx/PrtgSensorKit/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/ArchitektApx/PrtgSensorKit/compare/v1.2.1...v1.3.0
[1.2.1]: https://github.com/ArchitektApx/PrtgSensorKit/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/ArchitektApx/PrtgSensorKit/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/ArchitektApx/PrtgSensorKit/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/ArchitektApx/PrtgSensorKit/releases/tag/v1.0.0
