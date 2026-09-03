function Move-PrtgFileAtomic {
  <#
  .SYNOPSIS
    Moves a file over a destination without a window in which neither copy exists.
  .DESCRIPTION
    Move-Item -Force deletes then moves, leaving a gap on failure. File.Replace swaps
    atomically but needs an existing destination, so a first write uses Move-Item. Replace
    keeps the destination's ACL, so a caller that hardened its temp file re-applies it.
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
