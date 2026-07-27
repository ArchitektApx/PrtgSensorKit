# 💾 State between runs

Sensors often need yesterday's number to make sense of today's: rates from ever-growing
counters, caching an expensive lookup, or averaging the last hour of samples.
`Save-PrtgSensorState` appends a value (with a UTC timestamp) to a per-key history on
disk, and `Get-PrtgSensorState` reads it back on the next run:

```powershell
Invoke-PrtgSensor {
  $total = (Invoke-RestMethod -Uri $statsUrl).totalRequests

  # Last run's counter, or $null on the very first run / when the data is too old
  $previous = Get-PrtgSensorState -Key 'MySensor.Total' -MaxAge (New-TimeSpan -Minutes 15) -Latest

  if ($null -ne $previous) {
    New-PrtgChannel -Channel 'Delta' -Value ($total - $previous) | Add-PrtgChannel
  }

  Save-PrtgSensorState -Key 'MySensor.Total' -Value $total -MaxEntries 10
}
```

Details worth knowing:

- **Never throws for missing data** - the first run gets `-Default` (or `$null`), so no
  special-casing is needed.
- **Histories, not single values** - `Get-PrtgSensorState` returns `Value` + `Timestamp`
  entries newest first; `-Latest` shortcuts to the newest bare value. `-MaxEntries` on
  save and `Clear-PrtgSensorState -MaxAge` keep histories from growing forever.
- **Safe under overlapping scans** - reads and writes are serialized with a file lock.
  `-TimeoutSeconds` controls how long to wait for it, `-Force` bypasses it. A leftover
  zero-byte `<Key>.clixml.lock` file is normal; remove it with
  `Clear-PrtgSensorState -ClearLock` if it bothers you.
- **Keys are machine-global** - prefix them with your sensor name (`'MySensor.Total'`)
  to avoid collisions.
- **Plain data on disk** (`%ProgramData%\PrtgSensorKit\State`) - values are stored
  unencrypted. A `SecureString`/`PSCredential` inside a value does stay encrypted on
  Windows, but unlike the secret cmdlets the state cmdlets make no promises about
  protection: no checks, no ACL hardening, no guard off Windows. For secrets, prefer
  `Save-PrtgSecret` (see [Credentials and secrets](secrets.md)).

`-Latest` treats a stored `$null` as "no usable value" and returns `-Default` instead, so a
sensor doing arithmetic on the result cannot be silently poisoned by one. A stored `0`, `''`,
or `$false` is a real value and comes back unchanged.

> [!NOTE]
> `Use-PrtgCachedResult` deliberately does the opposite: a `$null` produced by the fetch block
> is a valid cached result and is served as `$null`. So if you point `Get-PrtgSensorState -Latest`
> at a CACHE key to inspect it, a cached `$null` reads back as your `-Default`, even though the
> cache is serving that entry normally. Inspect cache entries without `-Latest` (the entry list
> shows the real stored value), or see
> [Sharing one expensive call across sensors](shared-cache.md).

To share one expensive collection **across several sensors** instead of remembering values
**between runs of one sensor**, use `Use-PrtgCachedResult` - see
[Sharing one expensive call across sensors](shared-cache.md).

See [20-sensor-state-between-runs.ps1](../Examples/20-sensor-state-between-runs.ps1) for a
full rate-from-counter sensor.
