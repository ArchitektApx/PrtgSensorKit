function Use-PrtgCachedResult {
  <#
  .SYNOPSIS
    Returns a cached result, or runs the script block to produce and cache it.

  .DESCRIPTION
    Several sensors on one device often need slices of the SAME expensive source: one
    REST response, one SQL query, one WMI sweep. PRTG launches each sensor as its own
    process every interval, so 8 sensors mean 8 identical expensive calls per interval.
    Use-PrtgCachedResult makes them share one: the first sensor to find the cache stale
    runs the block and stores the result; every other sensor gets the stored value.

    Unlike a hand-rolled Get-PrtgSensorState / Save-PrtgSensorState pattern, concurrent
    sensors that all see a stale cache do not all fetch: they wait briefly for the first
    caller's fetch and then read the entry it just wrote. Exactly one fetch per expiry,
    guaranteed.

    The cache is stored as a regular sensor state entry (same folder, same file format,
    same key namespace), so Get-PrtgSensorState can inspect it and Clear-PrtgSensorState
    manages it - no separate cache tooling.

    Semantics worth knowing:

    - If the block throws, the exception propagates unchanged (inside Invoke-PrtgSensor
      it becomes the sensor error) and nothing is written; an existing stale entry is
      kept so the next caller retries the fetch.
    - A block returning $null is a valid result: $null is stored and served as $null.
      Use -SkipNullCache when a $null means "the fetch produced nothing useful" and you
      would rather pay for a retry than serve it.
    - A cached result keeps its properties but not its methods: treat it as plain data
      on both paths, like data read from a file. Live handles (sockets, sessions,
      database connections) cannot be cached.
    - The cache saves the expensive call, not the per-sensor process startup.
    - Never call Use-PrtgCachedResult for a key inside the block computing that same
      key: the inner call waits on the outer one, and the sensor hangs until the
      timeout.

    When many metrics come from one source, also consider the alternative design: one
    collector sensor with many channels. Use-PrtgCachedResult is for when you want
    separate sensors (independent intervals, notifications, priorities per metric).

  .PARAMETER Key
    Cache identifier, shared machine-wide with sensor state. Used as the file name, so
    it is restricted to letters, digits, dot, dash, and underscore. Prefix it with the
    data source (for example 'AcmeApi.Stats') to avoid collisions.

  .PARAMETER MaxAge
    How long a stored result stays fresh (compared against UTC now). Choose it slightly
    below the sensors' scan interval - for example 55 seconds for a 60-second interval -
    otherwise every interval refetches.

  .PARAMETER ScriptBlock
    Produces the result on a cache miss. Runs in-process, so it sees your script's
    variables, parameters, and imported modules - exactly like the Invoke-PrtgSensor
    block. The result is stored on disk, so it must be plain serializable data (no
    live handles).

  .PARAMETER Path
    Folder for the cache file. Defaults to '$env:ProgramData\PrtgSensorKit\State' on
    Windows, or a temp folder on other platforms (same store as the state cmdlets).

  .PARAMETER Depth
    Serialization depth passed to Export-Clixml (default 5), same meaning as on
    Save-PrtgSensorState. Raise it when the block returns rich .NET objects whose nested
    properties matter (a CIM instance, a FileInfo); beyond the depth those flatten to strings.
    Object trees built from PSCustomObjects and hashtables - an Invoke-RestMethod response,
    for instance - are not affected by the depth limit.

  .PARAMETER TimeoutSeconds
    Maximum time to wait for the cache lock (default 30 - higher than the state cmdlets'
    10, because waiting sensors hold out for the duration of a sibling's fetch). Set it
    above the slowest expected fetch. On expiry a terminating error is thrown: that is a
    real contention problem and should become a visible PRTG error.

  .PARAMETER SkipNullCache
    Treat a $null result as "nothing worth caching": a stored $null is ignored on read (the
    block runs again) and a $null returned by the block is not written to the cache file.
    Off by default, because it costs the cmdlet's main guarantee - a source that keeps
    returning $null is then refetched by EVERY sensor on EVERY interval instead of once.
    Use it only when a $null genuinely means the fetch failed and a retry is worth the calls.

  .PARAMETER Force
    Bypass locking entirely: best-effort read-or-fetch without serialization, which may
    duplicate fetches. Escape hatch for diagnostics and the interactive console.

  .EXAMPLE
    $stats = Use-PrtgCachedResult -Key 'AcmeApi.Stats' -MaxAge (New-TimeSpan -Seconds 55) {
      Invoke-RestMethod -Uri 'https://api.example.com/stats'
    }
    New-PrtgChannel -Channel 'Queue Depth' -Value $stats.queueDepth | Add-PrtgChannel

    Eight sensors on the device each want one field of the same response; the API is
    called once per interval, machine-wide, and every sensor reads from the cache.

  .EXAMPLE
    Clear-PrtgSensorState -Key 'AcmeApi.Stats'

    Cache entries are ordinary state entries; the existing state tooling clears them.

  .OUTPUTS
    The block's result. On a cache hit it comes back as plain data: properties
    preserved, methods not.

  .LINK
    Get-PrtgSensorState
  .LINK
    Clear-PrtgSensorState
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'MaxAge, ScriptBlock, Depth, and SkipNullCache are used inside the script block passed to Invoke-PrtgStateLock; the analyzer cannot see into it.')]
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$Key,

    [Parameter(Mandatory = $true)]
    [timespan]$MaxAge,

    [Parameter(Mandatory = $true, Position = 0)]
    [scriptblock]$ScriptBlock,

    [Parameter(Mandatory = $false)]
    [string]$Path,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 100)]
    [int]$Depth = 5,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 3600)]
    [int]$TimeoutSeconds = 30,

    [Parameter(Mandatory = $false)]
    [switch]$SkipNullCache,

    [Parameter(Mandatory = $false)]
    [switch]$Force
  )

  $state = Get-PrtgStateFile -Key $Key -Path $Path
  $file = $state.File

  # The lock is held across check + fetch + write on purpose: that is the entire fix for
  # the thundering-herd race the manual state pattern has.
  Invoke-PrtgStateLock -PrtgLockFile $state.LockFile -PrtgLockTimeout $TimeoutSeconds -PrtgLockForce:$Force -PrtgLockBlock {
    $loaded = Get-PrtgStateEntry -File $file -Cmdlet 'Use-PrtgCachedResult' -Noun 'cache file' `
      -UnreadableConsequence ', refetching'
    $entries = @($loaded)

    if ($entries.Count -gt 0) {
      # The file may hold a history written by Save-PrtgSensorState; this cmdlet itself
      # stores exactly one entry.
      $newest = Get-PrtgNewestEntry -Entries $entries
      # A cached $null is served like any other value unless -SkipNullCache asked for a retry.
      if ($newest.Timestamp.ToUniversalTime() -ge ([DateTime]::UtcNow - $MaxAge) -and
          -not ($SkipNullCache -and $null -eq $newest.Value)) {
        return $newest.Value
      }
    }

    # Miss: fetch while still holding the lock, so waiting siblings hit the fresh entry.
    # A throwing block skips the save, keeping any stale entry for the next caller.
    $result = & $ScriptBlock
    if ($SkipNullCache -and $null -eq $result) {
      Write-Verbose "Use-PrtgCachedResult: block returned `$null and -SkipNullCache is set; not caching '$Key'."
    } else {
      # Written atomically: a corrupt cache entry would send every sensor on the probe back to
      # the source at once, which is the stampede this cmdlet exists to prevent.
      Export-PrtgClixmlAtomic -LiteralPath $file -Depth $Depth -InputObject ([PSCustomObject]@{
        Value     = $result
        Timestamp = [DateTime]::UtcNow
      })
      Write-Verbose "Use-PrtgCachedResult: refreshed cache '$Key' in '$file'."
    }

    return $result
  }
}
