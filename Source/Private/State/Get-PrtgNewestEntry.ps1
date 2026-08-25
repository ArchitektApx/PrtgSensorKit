function Get-PrtgNewestEntry {
  <#
  .SYNOPSIS
    Returns the newest entry of a state history, or $null for an empty one.
  .DESCRIPTION
    Shared by Get-PrtgSensorState -Latest and Use-PrtgCachedResult, which must agree on which
    entry is "the newest" - including the tie-break, which is not obvious.

    A single pass instead of sorting the whole list: this runs on every scan interval and a
    history can be large when -MaxEntries is not used on save. The comparison is -ge, not -gt,
    because UtcNow has ~15 ms resolution on .NET Framework and two quick saves can carry
    IDENTICAL timestamps; file order is append order, so on a tie the later-appended entry wins.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [AllowNull()]
    [AllowEmptyCollection()]
    [object[]]$Entries
  )

  if ($null -eq $Entries -or $Entries.Count -eq 0) { return $null }

  $newest = $Entries[0]
  foreach ($entry in $Entries) {
    if ($entry.Timestamp.ToUniversalTime() -ge $newest.Timestamp.ToUniversalTime()) { $newest = $entry }
  }
  $newest
}
