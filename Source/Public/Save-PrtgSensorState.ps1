function Save-PrtgSensorState {
  <#
  .SYNOPSIS
    Persists a value between sensor runs.

  .DESCRIPTION
    Appends a new entry (your value plus a UTC timestamp) to the state history for a key,
    so a later run can read it back with Get-PrtgSensorState. Useful for caching, storing
    results of expensive calculations, or computing deltas/rates against previous runs.
    Stored with Export-Clixml, so typed objects round-trip. State is treated as plain
    data: values are written unencrypted. Note that a SecureString or PSCredential inside
    the value is still DPAPI-encrypted by Export-Clixml itself on Windows (the same
    mechanism Save-PrtgSecret uses), but UNLIKE the secret cmdlets, the state cmdlets make
    no promises about protection: no checks, no ACL hardening on the files, and no guard
    off Windows (where a SecureString is merely obfuscated, not encrypted). For secrets,
    prefer Save-PrtgSecret / Get-PrtgSecret.

    Access to the state file is serialized with an exclusive lock so overlapping sensor
    scans cannot corrupt it. The lock is held only for the duration of the write.

    Keys are not namespaced automatically - they are shared by every sensor on the machine.
    Prefix the key with your sensor name (for example 'MySensor.LastTotal') to keep sensors
    from colliding.

  .PARAMETER Key
    Unique identifier for this piece of state. Used as the file name, so it is restricted
    to letters, digits, dot, dash, and underscore.

  .PARAMETER Value
    The data to store. Any object Export-Clixml can serialize (numbers, strings, dates,
    hashtables, PSCustomObjects, arrays, ...).

  .PARAMETER Path
    Folder to store state in. Defaults to '$env:ProgramData\PrtgSensorKit\State' on
    Windows, or a temp folder on other platforms.

  .PARAMETER Depth
    Serialization depth passed to Export-Clixml (default 5). Raise it for deeply nested
    values; the Export-Clixml default of 2 would silently flatten nested data.

  .PARAMETER MaxEntries
    Keep only the newest N entries after appending (default 1000, roughly 16 hours of
    once-a-minute saves). Prevents a per-run save from growing the file - and the full
    read-plus-rewrite each save performs - forever. Pass 0 explicitly for unlimited.

  .PARAMETER TimeoutSeconds
    Maximum time to wait for the state file lock (default 10). 0 means a single try that
    fails immediately when another run holds the lock. On expiry a terminating error is
    thrown.

  .PARAMETER Force
    Bypass locking entirely and write best-effort, even while another process holds the
    lock. Escape hatch for diagnostics; concurrent forced writes can lose entries.

  .EXAMPLE
    Save-PrtgSensorState -Key 'MySensor.TotalRequests' -Value $api.totalRequests

    Stores a counter for the next run to diff against.

  .EXAMPLE
    Save-PrtgSensorState -Key 'MySensor.Inventory' -Value $inventory -Depth 8 -MaxEntries 10

    Stores a nested object, keeping only the ten newest entries.

  .NOTES
    Overlapping runs are serialized via the lock, but state is still a best-effort store,
    not a transactional database. A leftover zero-byte '<Key>.clixml.lock' file next to the
    state file is normal and harmless; see Clear-PrtgSensorState -ClearLock.

  .LINK
    Get-PrtgSensorState
  .LINK
    Clear-PrtgSensorState
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Value, Depth, and MaxEntries are used inside the script block passed to Invoke-PrtgStateLock; the analyzer cannot see into it.')]
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$Key,

    [Parameter(Mandatory = $true)]
    [AllowNull()]
    [object]$Value,

    [Parameter(Mandatory = $false)]
    [string]$Path,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 100)]
    [int]$Depth = 5,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, [int]::MaxValue)]
    [int]$MaxEntries = 1000,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 3600)]
    [int]$TimeoutSeconds = 10,

    [Parameter(Mandatory = $false)]
    [switch]$Force
  )

  $folder = Get-PrtgStatePath -Path $Path
  $file = Join-Path $folder "$Key.clixml"
  $lockFile = "$file.lock"

  Invoke-PrtgStateLock -LockFile $lockFile -TimeoutSeconds $TimeoutSeconds -Force:$Force -ScriptBlock {
    $loaded = Get-PrtgStateEntry -File $file
    if ($loaded.Unreadable) {
      Write-Warning "Save-PrtgSensorState: existing state file '$file' is unreadable and will be replaced. ($($loaded.UnreadableMessage))"
    }
    if ($loaded.MalformedCount -gt 0) {
      Write-Warning "Save-PrtgSensorState: state file '$file' had $($loaded.MalformedCount) malformed entries (corrupted on disk), ignoring them."
    }
    $entries = @($loaded.Entries)

    $entries += [PSCustomObject]@{
      Value     = $Value
      Timestamp = [DateTime]::UtcNow
    }

    if ($MaxEntries -gt 0 -and $entries.Count -gt $MaxEntries) {
      $entries = @($entries | Select-Object -Last $MaxEntries)
    }

    $entries | Export-Clixml -LiteralPath $file -Depth $Depth -Force
    Write-Verbose "Saved state '$Key' to '$file' ($($entries.Count) entries)."
  }
}
