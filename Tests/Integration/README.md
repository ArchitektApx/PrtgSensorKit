# PrtgSensorKit integration sensors

Real EXE/Script Advanced sensor scripts to deploy on the PRTG test VM and validate by
hand before a release. They are NOT run by the Pester suite - they exercise the module
end to end inside an actual PRTG probe, which the unit tests cannot.

Three categories:

- **working/** - valid PRTG JSON, sensor should show **Up (green)**.
- **failing/** - the module reports a PRTG error response: well-formed JSON with
  `prtg.error = 1`, so the sensor shows **Down (red)** with a readable message. This is
  correct behavior, not a bug: the sensor is "working" in that it fails cleanly.
- **malformed/** - scripts that make one of the mistakes `Invoke-PrtgSensorDoctor`
  detects. Deployed, they emit corrupt or non-JSON output and PRTG shows a
  **parse/XML error** (not a clean Down). Each maps to a Doctor check id so you can
  confirm the Doctor predicts what PRTG actually does.

## How to deploy

PRTG only lists scripts that sit directly in
`C:\Program Files (x86)\PRTG Network Monitor\Custom Sensors\EXEXML\`, not in nested
folders. `.deployToTestVM.sh` therefore flattens the category subfolders into the EXEXML
root, prefixing each file with its category, so `working/01-static-single-channel.ps1`
becomes `working_01-static-single-channel.ps1`, and so on for `failing_*` and
`malformed_*`. The paths in the matrix below are the repo layout; on the probe look for
the prefixed names.

To deploy by hand instead, copy a script into the EXEXML folder (renamed with its
category prefix) and add an "EXE/Script Advanced" sensor pointing at it. Some sensors take
a `Parameters` field (noted below). PrtgSensorKit must be installed for all users first
(`Install-Module PrtgSensorKit -Scope AllUsers` from Windows PowerShell).

`Test-MalformedDoctor.ps1` is deployed alongside the sensors (it is a helper, not a
sensor). Run it on the probe from the EXEXML folder to confirm `Invoke-PrtgSensorDoctor`
flags every `malformed_*` script with its expected finding; it exits non-zero on any
mismatch.

Before deploying the malformed set, run the Doctor on each and confirm the predicted
findings:

```powershell
Get-ChildItem .\Tests\Integration -Recurse -Filter *.ps1 |
  ForEach-Object { Invoke-PrtgSensorDoctor -ScriptPath $_.FullName }
```

## Validation matrix

| Script | Category | Expected PRTG result | Expected Doctor verdict |
| --- | --- | --- | --- |
| working/01-static-single-channel.ps1 | working | Up; channel `Answer` = 42 | all Pass |
| working/02-multichannel-with-limits.ps1 | working | Up; one channel per fixed disk, limits applied | all Pass |
| working/03-retry-recovers.ps1 | working | Up; message ends `(1/3 retries attempted)` | all Pass |
| working/04-state-delta.ps1 | working | 1st scan: message `baseline stored`; later scans: `Elapsed ms` channel | all Pass |
| working/05-forcemoderntls-web.ps1 | working | Up if the probe has internet; needs TLS 1.2 endpoint | PSK0009 Pass (TLS forced) |
| failing/06-block-throws.ps1 | failing | Down; error text contains `deliberate failure` | all Pass (clean error handling) |
| failing/07-retries-exhausted.ps1 | failing | Down; text starts `unsuccessful after 2 retries:` | all Pass |
| failing/08-channel-limit-exceeded.ps1 | failing | Down; error about the 50-channel limit | all Pass |
| malformed/09-dryrun-left-in.ps1 | malformed | XML/parse error (object dump, not JSON) | PSK0010 Warning |
| malformed/10-manual-output-in-block.ps1 | malformed | XML/parse error (two responses / extra output) | PSK0005 Error |
| malformed/11-multiple-invoke.ps1 | malformed | XML/parse error (two JSON documents) | PSK0007 Error |
| malformed/12-trailing-output.ps1 | malformed | XML/parse error (text after the JSON) | PSK0008 Warning |
| malformed/13-restart-inside-block.ps1 | malformed | XML/parse error or empty (relaunch output discarded) | PSK0003 Error |
| malformed/14-restart-misplaced-import.ps1 | malformed | import fails in the wrong host before relaunch | PSK0004 Error |
| malformed/15-web-without-tls.ps1 | malformed | Down on 5.1 (TLS handshake fails) against a modern endpoint | PSK0009 Info |
| malformed/16-syntax-error.ps1 | malformed | sensor fails to run (parse error) | PSK0001 Error |

Notes:

- Sensors 03 and 04 dogfood the state cmdlets; 04 writes to
  `%ProgramData%\PrtgSensorKit\State`. Run it at least twice to see the delta path.
- 05 and 15 are the only sensors that need outbound HTTPS. 15 is expected to FAIL on
  Windows PowerShell 5.1 precisely because it omits `-ForceModernTls`; if the probe's
  5.1 already defaults to TLS 1.2 it may pass, which is itself worth recording.
- 14 must be run in a host where `SqlServer` (or the substituted module) is NOT
  available so the pre-restart import actually fails; adjust the module name to one
  missing on your probe.
