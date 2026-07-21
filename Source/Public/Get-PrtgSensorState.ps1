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
    Returned when nothing matches (no state file, empty history, or everything older than
    -MaxAge). Defaults to $null.

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

  $folder = Get-PrtgStatePath -Path $Path
  $file = Join-Path $folder "$Key.clixml"
  $lockFile = "$file.lock"

  $entries = Invoke-PrtgStateLock -LockFile $lockFile -TimeoutSeconds $TimeoutSeconds -Force:$Force -ScriptBlock {
    if (-not (Test-Path -LiteralPath $file)) { return @() }
    try {
      @(Import-Clixml -LiteralPath $file)
    } catch {
      Write-Warning "Get-PrtgSensorState: state file '$file' is unreadable, treating it as empty. ($($_.Exception.Message))"
      @()
    }
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
    # Single pass instead of sorting the whole history for one value; this runs on every
    # scan interval and the history can be large when -MaxEntries is not used on save.
    $newest = $entries[0]
    foreach ($entry in $entries) {
      if ($entry.Timestamp.ToUniversalTime() -gt $newest.Timestamp.ToUniversalTime()) { $newest = $entry }
    }
    return $newest.Value
  }

  return @($entries | Sort-Object -Property Timestamp -Descending)
}
