function Move-PrtgFileAtomic {
  <#
  .SYNOPSIS
    Moves a file over a destination without a window in which neither copy exists.
  .DESCRIPTION
    Shared by every writer that builds its new content in a temp file first. Move-Item -Force
    cannot be used to replace an existing file: the provider deletes the destination and THEN
    moves, so a failure in between (a killed process, a virus scanner holding the temp file)
    leaves the destination gone and nothing in its place.

    [System.IO.File]::Replace does the swap in one step, and leaves the destination untouched
    when it fails. It requires the destination to exist, so a first write still goes through
    Move-Item, where there is nothing to lose.

    NOTE: Replace keeps the DESTINATION's ACL, not the temp file's. A caller that hardens its
    temp file has to re-apply the ACL afterwards.
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Non-interactive store write on the sensor path; a -Confirm prompt would stall a PRTG probe.')]
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$Destination
  )

  if (Test-Path -LiteralPath $Destination) {
    # .NET resolves relative paths against the PROCESS working directory, which is not
    # PowerShell's current location; a relative -Path would land somewhere else entirely.
    $sourceFull = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $destinationFull = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
    # [NullString]::Value, not $null: PowerShell binds $null to an empty string here, and
    # .NET Framework rejects that with 'The path is not of a legal form.'
    [System.IO.File]::Replace($sourceFull, $destinationFull, [NullString]::Value)
  } else {
    Move-Item -LiteralPath $Path -Destination $Destination -Force
  }
}
