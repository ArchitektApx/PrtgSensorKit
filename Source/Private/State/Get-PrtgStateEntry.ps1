function Get-PrtgStateEntry {
  <#
  .SYNOPSIS
    Reads the entry list from a sensor state file and reports what was wrong with it.
  .DESCRIPTION
    Imports the file, drops every entry that is not a well-formed {Value, Timestamp} object,
    and warns about an unreadable file and about malformed entries.

    Returns an [object[]] for zero, one and many entries alike. Assign the result before
    wrapping it: '@(Get-PrtgStateEntry ...)' collects the returned array as a SINGLE element,
    while '$e = Get-PrtgStateEntry ...; @($e)' yields the entries.
  .PARAMETER Cmdlet
    Name of the calling cmdlet, used to prefix the warnings.
  .PARAMETER Noun
    What the warnings call the file: 'state file' for the state cmdlets, 'cache file' for the
    shared cache.
  .PARAMETER UnreadableConsequence
    Completes "<noun> '<file>' is unreadable", so it carries its own joining punctuation:
    " and will be replaced", ", refetching".
  .PARAMETER UnreadableNoun
    Noun for the unreadable warning alone. Defaults to -Noun.
  #>
  [CmdletBinding()]
  [OutputType([object[]])]
  param(
    [Parameter(Mandatory = $true)]
    [string]$File,

    [Parameter(Mandatory = $true)]
    [string]$Cmdlet,

    [Parameter(Mandatory = $true)]
    [string]$Noun,

    [Parameter(Mandatory = $true)]
    [string]$UnreadableConsequence,

    [Parameter(Mandatory = $false)]
    [string]$UnreadableNoun
  )

  if (-not $PSBoundParameters.ContainsKey('UnreadableNoun')) { $UnreadableNoun = $Noun }

  $valid = @()

  if (Test-Path -LiteralPath $File) {
    $entries = try {
      @(Import-Clixml -LiteralPath $File)
    } catch {
      Write-Warning "${Cmdlet}: $UnreadableNoun '$File' is unreadable$UnreadableConsequence. ($($_.Exception.Message))"
      @()
    }

    $valid = @($entries | Where-Object {
        $null -ne $_ -and
        $_.PSObject.Properties['Value'] -and
        $_.PSObject.Properties['Timestamp'] -and
        $_.Timestamp -is [DateTime]
      })

    $malformed = $entries.Count - $valid.Count
    if ($malformed -gt 0) {
      Write-Warning "${Cmdlet}: $Noun '$File' had $malformed malformed entries (corrupted on disk), ignoring them."
    }
  }

  , $valid
}
