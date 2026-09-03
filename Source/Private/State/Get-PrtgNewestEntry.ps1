function Get-PrtgNewestEntry {
  <#
  .SYNOPSIS
    Returns the newest entry of a state history, or $null for an empty one.
  .DESCRIPTION
    Single pass, not a sort. The comparison is -ge: UtcNow has ~15 ms resolution, so a tie
    goes to the later-appended entry (ADR 0002).
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
