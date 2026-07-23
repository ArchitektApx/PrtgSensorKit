function Get-PrtgStateEntry {
  <#
  .SYNOPSIS
    Reads and validates the entry list from a sensor state file.
  .DESCRIPTION
    Shared by Save/Get/Clear-PrtgSensorState: Import-Clixml the file and drop any entry that
    isn't a well-formed {Value, Timestamp} object. Data only, no Write-Warning - callers own
    their own wording.
  #>
  [CmdletBinding()]
  [OutputType([PSCustomObject])]
  param(
    [Parameter(Mandatory = $true)]
    [string]$File
  )

  if (-not (Test-Path -LiteralPath $File)) {
    return [PSCustomObject]@{ Entries = @(); Unreadable = $false; UnreadableMessage = $null; MalformedCount = 0 }
  }

  $unreadable = $false
  $unreadableMessage = $null
  $entries = try {
    @(Import-Clixml -LiteralPath $File)
  } catch {
    $unreadable = $true
    $unreadableMessage = $_.Exception.Message
    @()
  }

  $valid = @($entries | Where-Object {
    $null -ne $_ -and
    $_.PSObject.Properties['Value'] -and
    $_.PSObject.Properties['Timestamp'] -and
    $_.Timestamp -is [DateTime]
  })

  [PSCustomObject]@{
    Entries           = $valid
    Unreadable        = $unreadable
    UnreadableMessage = $unreadableMessage
    MalformedCount    = $entries.Count - $valid.Count
  }
}
