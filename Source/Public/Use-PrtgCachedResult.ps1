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

  .PARAMETER TimeoutSeconds
    Maximum time to wait for the cache lock (default 30 - higher than the state cmdlets'
    10, because waiting sensors hold out for the duration of a sibling's fetch). Set it
    above the slowest expected fetch. On expiry a terminating error is thrown: that is a
    real contention problem and should become a visible PRTG error.

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
    Justification = 'MaxAge and ScriptBlock are used inside the script block passed to Invoke-PrtgStateLock; the analyzer cannot see into it.')]
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
    [ValidateRange(0, 3600)]
    [int]$TimeoutSeconds = 30,

    [Parameter(Mandatory = $false)]
    [switch]$Force
  )

  $folder = Get-PrtgStatePath -Path $Path
  $file = Join-Path $folder "$Key.clixml"
  $lockFile = "$file.lock"

  # The block below runs inside Invoke-PrtgStateLock, where '$ScriptBlock' dynamically
  # resolves to the lock function's OWN parameter (the block itself) - invoking that
  # recurses forever. Capture the fetch block under a non-shadowed name first.
  $fetchBlock = $ScriptBlock

  # The lock is held across check + fetch + write on purpose: that is the entire fix for
  # the thundering-herd race the manual state pattern has.
  Invoke-PrtgStateLock -LockFile $lockFile -TimeoutSeconds $TimeoutSeconds -Force:$Force -ScriptBlock {
    $loaded = Get-PrtgStateEntry -File $file
    if ($loaded.Unreadable) {
      Write-Warning "Use-PrtgCachedResult: cache file '$file' is unreadable, refetching. ($($loaded.UnreadableMessage))"
    }
    if ($loaded.MalformedCount -gt 0) {
      Write-Warning "Use-PrtgCachedResult: cache file '$file' had $($loaded.MalformedCount) malformed entries (corrupted on disk), ignoring them."
    }
    $entries = @($loaded.Entries)

    if ($entries.Count -gt 0) {
      # Newest entry via a single pass (the file may hold a history written by
      # Save-PrtgSensorState; this cmdlet itself stores exactly one entry). -ge, not
      # -gt: on a timestamp tie (UtcNow resolution) the later-appended entry wins.
      $newest = $entries[0]
      foreach ($entry in $entries) {
        if ($entry.Timestamp.ToUniversalTime() -ge $newest.Timestamp.ToUniversalTime()) { $newest = $entry }
      }
      if ($newest.Timestamp.ToUniversalTime() -ge ([DateTime]::UtcNow - $MaxAge)) {
        return $newest.Value
      }
    }

    # Miss: fetch while still holding the lock, so waiting siblings hit the fresh entry.
    # A throwing block skips the save, keeping any stale entry for the next caller.
    $result = & $fetchBlock
    [PSCustomObject]@{
      Value     = $result
      Timestamp = [DateTime]::UtcNow
    } | Export-Clixml -LiteralPath $file -Depth 5 -Force
    Write-Verbose "Use-PrtgCachedResult: refreshed cache '$Key' in '$file'."

    return $result
  }
}
