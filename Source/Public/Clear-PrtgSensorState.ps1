function Clear-PrtgSensorState {
  <#
  .SYNOPSIS
    Deletes or prunes state saved by Save-PrtgSensorState.

  .DESCRIPTION
    Without -MaxAge, deletes the whole state history for a key. With -MaxAge, keeps only
    the entries younger than the cutoff and deletes the file when none remain. A missing
    state file is a no-op, not an error.

    The '.lock' sidecar next to the state file is left in place by default (a leftover
    zero-byte lock file is harmless, and deleting it while another run polls it is a
    race). Pass -ClearLock to remove it too.

  .PARAMETER Key
    Identifier passed to Save-PrtgSensorState.

  .PARAMETER MaxAge
    Prune mode: keep entries younger than this TimeSpan (compared against UTC now),
    drop the rest. Without it the whole state file is deleted.

  .PARAMETER Path
    Folder the state was stored in. Defaults to '$env:ProgramData\PrtgSensorKit\State' on
    Windows, or a temp folder on other platforms.

  .PARAMETER Depth
    Serialization depth used when re-exporting the pruned entries (default 10). Raise it to
    match (or exceed) the -Depth used when the entries were originally saved with
    Save-PrtgSensorState, or -MaxAge pruning will silently flatten nested data beyond this
    depth.

  .PARAMETER TimeoutSeconds
    Maximum time to wait for the state file lock (default 10). 0 means a single try that
    fails immediately when another run holds the lock. On expiry a terminating error is
    thrown.

  .PARAMETER Force
    Bypass locking entirely and act best-effort, even while another process holds the
    lock. With -ClearLock, the sidecar deletion is also attempted best-effort.

  .PARAMETER ClearLock
    Also remove the '<Key>.clixml.lock' sidecar file. The lock is acquired first (unless
    -Force), and the OS deletes the file when the held handle closes - so a lock file
    cannot be pulled out from under another live holder; if one holds it, this call times
    out like any other.

  .EXAMPLE
    Clear-PrtgSensorState -Key 'MySensor.TotalRequests'

    Deletes the stored history for the key.

  .EXAMPLE
    Clear-PrtgSensorState -Key 'MySensor.Samples' -MaxAge (New-TimeSpan -Days 7)

    Keeps only the last week of entries.

  .LINK
    Save-PrtgSensorState
  .LINK
    Get-PrtgSensorState
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Non-interactive sensor housekeeping; a -Confirm prompt would stall a PRTG probe.')]
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$Key,

    [Parameter(Mandatory = $false)]
    [timespan]$MaxAge,

    [Parameter(Mandatory = $false)]
    [string]$Path,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 100)]
    [int]$Depth = 10,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 3600)]
    [int]$TimeoutSeconds = 10,

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$ClearLock
  )

  $folder = Get-PrtgStatePath -Path $Path
  $file = Join-Path $folder "$Key.clixml"
  $lockFile = "$file.lock"

  # Captured here: $PSBoundParameters inside the script block below would be the block's
  # own (empty) bound parameters, not this function's.
  $pruneMode = $PSBoundParameters.ContainsKey('MaxAge')

  $action = {
    if (-not (Test-Path -LiteralPath $file)) { return }

    if (-not $pruneMode) {
      Remove-Item -LiteralPath $file -Force
      Write-Verbose "Cleared state '$Key' ('$file' deleted)."
      return
    }

    $loaded = Get-PrtgStateEntry -File $file
    if ($loaded.Unreadable) {
      Write-Warning "Clear-PrtgSensorState: state file '$file' is unreadable and will be deleted. ($($loaded.UnreadableMessage))"
    }
    if ($loaded.MalformedCount -gt 0) {
      Write-Warning "Clear-PrtgSensorState: state file '$file' had $($loaded.MalformedCount) malformed entries (corrupted on disk), ignoring them."
    }
    $entries = @($loaded.Entries)

    $cutoff = [DateTime]::UtcNow - $MaxAge
    $keep = @($entries | Where-Object { $_.Timestamp.ToUniversalTime() -ge $cutoff })

    if ($keep.Count -eq 0) {
      Remove-Item -LiteralPath $file -Force
      Write-Verbose "Cleared state '$Key' (no entries younger than $MaxAge, '$file' deleted)."
    } else {
      $keep | Export-Clixml -LiteralPath $file -Depth $Depth -Force
      Write-Verbose "Pruned state '$Key' to $($keep.Count) entries younger than $MaxAge."
    }
  }

  # With -ClearLock the lock handle is opened with DeleteOnClose, so the OS removes the
  # sidecar atomically when the handle is released - no window where a freshly acquired
  # lock could be deleted under its holder.
  Invoke-PrtgStateLock -LockFile $lockFile -TimeoutSeconds $TimeoutSeconds -Force:$Force `
    -DeleteLockOnRelease:($ClearLock -and -not $Force) -ScriptBlock $action

  if ($ClearLock -and $Force -and (Test-Path -LiteralPath $lockFile)) {
    try {
      Remove-Item -LiteralPath $lockFile -Force
    } catch {
      Write-Warning "Clear-PrtgSensorState: could not remove lock file '$lockFile' (probably held by a live run). ($($_.Exception.Message))"
    }
  }
}
