# 🤝 Sharing one expensive call across sensors

Several sensors on one device often need slices of the **same** expensive source: one
REST response, one SQL query, one WMI sweep. PRTG launches every sensor as its own
process each interval, so 8 sensors mean 8 identical calls - probe load, hammered APIs,
rate-limit hits. `Use-PrtgCachedResult` makes them share one: the first sensor to find
the cache stale runs the block and stores the result; every other sensor gets the
stored value.

```powershell
Invoke-PrtgSensor {
  $stats = Use-PrtgCachedResult -Key 'AcmeApi.Stats' -MaxAge (New-TimeSpan -Seconds 55) {
    Invoke-RestMethod -Uri 'https://api.example.com/stats'   # runs once per interval, machine-wide
  }
  New-PrtgChannel -Channel 'Queue Depth' -Value $stats.queueDepth | Add-PrtgChannel
}
```

Details worth knowing:

- **Only one sensor fetches** - sensors firing at the same moment wait briefly for the
  first one's fetch and then read its result: exactly one fetch per expiry, guaranteed.
  (A hand-rolled Get/Save state pattern cannot promise this.)
- **Pick `-MaxAge` slightly below the scan interval** (55 s for a 60 s interval),
  otherwise every interval refetches. Pick `-TimeoutSeconds` (default 30) above the
  slowest expected fetch.
- **Cache entries are ordinary sensor state** - same folder, same format, same keys as
  [state between runs](state.md). `Get-PrtgSensorState` inspects them (but do NOT use its
  `-Latest` switch for that: it maps a stored `$null` to its `-Default`, whereas the cache
  serves a cached `$null` as-is, so the two would disagree about the same entry),
  `Clear-PrtgSensorState` clears them.
- **Treat results as plain data** - a cached result keeps its properties but not its
  methods. Treat it like data read from a file, and don't cache live handles (sockets,
  sessions, database connections). Rich .NET objects (a CIM instance, a `FileInfo`) lose
  nested properties below `-Depth` (default 5); raise it if you cache those. Trees of
  PSCustomObjects and hashtables, such as an `Invoke-RestMethod` response, are unaffected.
- **A throwing block keeps the stale entry** and propagates the error (inside
  `Invoke-PrtgSensor` it becomes the sensor error); the next run retries the fetch.
- **A `$null` result is cached and served like any other value.** If a `$null` means the fetch
  produced nothing useful and you would rather retry, add `-SkipNullCache`: a stored `$null` is
  then ignored on read and never written. Use it deliberately - a source that keeps returning
  `$null` is refetched by every sensor on every interval, which is exactly the thundering herd
  the cmdlet otherwise prevents.
- **Never call `Use-PrtgCachedResult` for a key inside the block that computes that same
  key** - the inner call waits on the outer one, and the sensor hangs until the timeout.
- The cache saves the expensive call, not the per-sensor process startup. If one source
  feeds many metrics, also consider a single collector sensor with many channels;
  `Use-PrtgCachedResult` is for when you want separate sensors (independent intervals,
  notifications, priorities per metric).

See [24-shared-collection-cache.ps1](../Examples/24-shared-collection-cache.ps1).
