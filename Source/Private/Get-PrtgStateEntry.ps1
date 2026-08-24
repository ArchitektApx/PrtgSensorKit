function Get-PrtgStateEntry {
  <#
  .SYNOPSIS
    Reads the entry list from a sensor state file and reports what was wrong with it.
  .DESCRIPTION
    Shared by Save/Get/Clear-PrtgSensorState and Use-PrtgCachedResult: Import-Clixml the file,
    drop any entry that isn't a well-formed {Value, Timestamp} object, and warn about both kinds
    of damage. Corruption policy is decided here, so changing it is one edit and one review
    rather than four. Callers supply only the three things this function cannot know: which
    cmdlet is speaking, what that cmdlet calls the file, and what happens to an unreadable file
    next.

    Returns an [object[]] for zero, one and many entries alike, so a caller cannot silently get
    a scalar or nothing. Assign the result before wrapping it: '@(Get-PrtgStateEntry ...)'
    collects the returned array as a SINGLE element, while '$e = Get-PrtgStateEntry ...; @($e)'
    yields the entries.
  #>
  [CmdletBinding()]
  [OutputType([object[]])]
  param(
    [Parameter(Mandatory = $true)]
    [string]$File,

    [Parameter(Mandatory = $true)]
    [string]$Cmdlet,

    # 'state file' for the three state cmdlets, 'cache file' for the shared cache. Operator-facing
    # framing rather than a claim about storage - the cache is an entry in the same store.
    [Parameter(Mandatory = $true)]
    [string]$Noun,

    # Completes "<noun> '<file>' is unreadable", so it carries its own joining punctuation: one
    # caller continues " and will be replaced", another ", refetching". Deliberately free-form.
    # Constraining it to a fixed set would put the callers' vocabulary inside this function,
    # which is the coupling it exists to remove: only the caller knows what happens next.
    [Parameter(Mandatory = $true)]
    [string]$UnreadableConsequence,

    # Save-PrtgSensorState calls the file an 'existing state file' when it is about to replace
    # it, and only in that one warning; its malformed warning uses the plain noun like the rest.
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
