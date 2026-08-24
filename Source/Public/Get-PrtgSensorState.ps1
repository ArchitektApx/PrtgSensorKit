function Get-PrtgSensorState {
  <#
  .SYNOPSIS
    Reads state saved by a previous sensor run.

  .DESCRIPTION
    Returns the entry history for a key as objects with 'Value' and 'Timestamp' (UTC)
    properties, newest first, so deltas and rates can be computed against the timestamps.
    Never throws for missing data - a first sensor run can call this unconditionally and
    fall back to -Default.

    Access to the state file is serialized with an exclusive lock; a lock timeout is a
    real contention problem and DOES throw, even when -Default is set.

  .PARAMETER Key
    Identifier passed to Save-PrtgSensorState.

  .PARAMETER MaxAge
    Only return entries younger than this TimeSpan (compared against UTC now). Older
    entries are ignored, not deleted; use Clear-PrtgSensorState -MaxAge to prune them.

  .PARAMETER Latest
    Return only the bare Value of the newest matching entry, instead of the entry list.
    The common "give me last run's value" shortcut.

  .PARAMETER Default
    Returned when nothing matches (no state file, empty history, everything older than
    -MaxAge, or -Latest finding a stored $null). Defaults to $null. A stored 0, '', or
    $false is a real value and is returned as-is.

  .PARAMETER Path
    Folder the state was stored in. Defaults to '$env:ProgramData\PrtgSensorKit\State' on
    Windows, or a temp folder on other platforms.

  .PARAMETER TimeoutSeconds
    Maximum time to wait for the state file lock (default 10). 0 means a single try that
    fails immediately when another run holds the lock. On expiry a terminating error is
    thrown (also when -Default is set - a lock timeout is not "no data").

  .PARAMETER Force
    Bypass locking entirely and read best-effort, even while another process holds the
    lock. Escape hatch for diagnostics and the interactive console.

  .EXAMPLE
    $previous = Get-PrtgSensorState -Key 'MySensor.TotalRequests' -Latest -Default 0
    $delta = $current - $previous

    Reads last run's counter (or 0 on the very first run) to compute a delta.

  .EXAMPLE
    $history = Get-PrtgSensorState -Key 'MySensor.Samples' -MaxAge (New-TimeSpan -Hours 1)
    $avg = ($history.Value | Measure-Object -Average).Average

    Averages all samples stored in the last hour; entries come back newest first.

  .LINK
    Save-PrtgSensorState
  .LINK
    Clear-PrtgSensorState
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$Key,

    [Parameter(Mandatory = $false)]
    [timespan]$MaxAge,

    [Parameter(Mandatory = $false)]
    [switch]$Latest,

    [Parameter(Mandatory = $false)]
    [AllowNull()]
    [object]$Default = $null,

    [Parameter(Mandatory = $false)]
    [string]$Path,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 3600)]
    [int]$TimeoutSeconds = 10,

    [Parameter(Mandatory = $false)]
    [switch]$Force
  )

  $entries = Invoke-PrtgStateOperation -PrtgOpKey $Key -PrtgOpPath $Path -PrtgOpTimeout $TimeoutSeconds `
    -PrtgOpForce:$Force -PrtgOpBlock {
    param($PrtgOpState)
    Get-PrtgStateEntry -File $PrtgOpState.File -Cmdlet 'Get-PrtgSensorState' -Noun 'state file' `
      -UnreadableConsequence ', treating it as empty'
  }

  $entries = @($entries)

  if ($PSBoundParameters.ContainsKey('MaxAge')) {
    $cutoff = [DateTime]::UtcNow - $MaxAge
    # ToUniversalTime() keeps the comparison correct even if a serializer changed the Kind.
    $entries = @($entries | Where-Object { $_.Timestamp.ToUniversalTime() -ge $cutoff })
  }

  if ($entries.Count -eq 0) {
    return $Default
  }

  if ($Latest) {
    $newest = Get-PrtgNewestEntry -Entries $entries
    # A stored $null is not a usable value for a caller doing arithmetic, so -Default wins.
    # -eq $null, not a truthiness test: a stored 0 or '' must NOT fall back.
    if ($null -eq $newest.Value) { return $Default }
    return $newest.Value
  }

  # Newest first by real elapsed time. Two rules, both needed for this path to name the same
  # entry as -Latest: a hand-written or foreign clixml can hold Local or Unspecified kinds, so
  # the comparison normalizes to UTC; and Sort-Object is not stable while UtcNow has ~15 ms
  # resolution, so the append index breaks ties in favour of the entry written last - file order
  # is append order, the same rule Get-PrtgNewestEntry applies with its -ge comparison.
  $order = 0
  $decorated = @($entries | ForEach-Object { [PSCustomObject]@{ Order = $order++; Entry = $_ } })
  return @($decorated |
      Sort-Object -Property @{ Expression = { $_.Entry.Timestamp.ToUniversalTime() }; Descending = $true },
                            @{ Expression = 'Order'; Descending = $true } |
      ForEach-Object { $_.Entry })
}
