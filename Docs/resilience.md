# 🔁 Resilience: retries and modern TLS

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
