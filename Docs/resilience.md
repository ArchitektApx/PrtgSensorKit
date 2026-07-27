# 🔁 Resilience: retries and modern TLS

## Errors inside the block are terminating

`Invoke-PrtgSensor` sets `$ErrorActionPreference` to `Stop` for the duration of your block, so
a NON-terminating error becomes a PRTG error response instead of being written to stderr and
ignored. This is what makes a failing `Get-CimInstance`, `Get-Counter`, or `Invoke-RestMethod`
turn the sensor red rather than emitting a green sensor with missing or stale channels.

```powershell
Invoke-PrtgSensor {
  $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='Q:'"   # no such drive
  New-PrtgChannel -Channel 'Free' -Value $disk.FreeSpace | Add-PrtgChannel
}
# -> {"prtg":{"error":1,"text":"..."}}  (previously: a green sensor with no channels)
```

To let a specific command fail quietly, opt out per statement with `-ErrorAction`, or assign
`$ErrorActionPreference` INSIDE the block - an assignment there is block-local and shadows the
wrapper's setting:

```powershell
Invoke-PrtgSensor {
  $optional = Get-Item 'C:\maybe-missing.txt' -ErrorAction SilentlyContinue
  ...
}
```

See [16-making-errors-nonterminating.ps1](../Examples/16-making-errors-nonterminating.ps1).

> [!NOTE]
> Setting `$ErrorActionPreference` at the top of the sensor script (outside the block) does NOT
> opt out. PRTG runs sensors as `powershell.exe -f sensor.ps1`, where the script's top-level
> scope is the global scope, so the wrapper's setting replaces it. One exception is worth knowing
> when you test by hand: if the preference lives in a real child scope - a wrapper FUNCTION that
> calls `Invoke-PrtgSensor`, or running `& .\sensor.ps1` from an existing session - it shadows the
> wrapper and errors stay non-terminating. Interactive testing can therefore behave differently
> from the deployed run; test with `powershell -File .\sensor.ps1` to match production.

## Retrying flaky data sources

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
with `unsuccessful after 2 retries:`. With `-EnableLogging`, every failed attempt is also
logged with its error (see [File logging](logging.md)).

> [!WARNING]
> Keep `(RetryCount + 1) * (block runtime + delay)` below the PRTG sensor timeout,
> otherwise PRTG kills the sensor before the retries finish.

See [19-retries-transient-failures.ps1](../Examples/19-retries-transient-failures.ps1).

## Modern TLS on Windows PowerShell 5.1

Windows PowerShell 5.1 defaults can lack TLS 1.2, which makes HTTPS calls fail against
modern endpoints - and only under PRTG, because your interactive testing probably happens
in pwsh where the defaults are fine. Add `-ForceModernTls` and `Invoke-PrtgSensor` enables
TLS 1.2/1.3 for the process before your block runs:

```powershell
Invoke-PrtgSensor -ForceModernTls {
  $data = Invoke-RestMethod -Uri 'https://api.example.com/stats'
  ...
}
```

The sensor doctor flags web requests without a TLS setup (check PSK0009).

See [22-force-modern-tls.ps1](../Examples/22-force-modern-tls.ps1).
