function Add-PrtgChannel {
  <#
  .SYNOPSIS
    Adds a PRTG channel object to the current sensor output.

  .DESCRIPTION
    Appends a channel object to the module-scope result collection. Build output incrementally:
    add channels via this cmdlet (one per call, pipeline-friendly), then emit the JSON with
    Write-PrtgOutput. PRTG allows a maximum of 50 channels per sensor, so adding a 51st throws.

    PRTG also requires channel names to be unique within a sensor, so adding a channel whose
    name was already added throws too (comparison is case-insensitive). Aggregate first when
    generating names from process, service, or disk names, where duplicates occur naturally.

    Channel objects are typically created with New-PrtgChannel.

  .PARAMETER PrtgChannel
    A channel object (PSCustomObject) to add to the output. Usually from New-PrtgChannel.
    Accepts pipeline input.

  .EXAMPLE
    Get-Process | Group-Object ProcessName |
      Sort-Object { ($_.Group | Measure-Object CPU -Sum).Sum } -Descending |
      Select-Object -First 10 | ForEach-Object {
        New-PrtgChannel -Channel $_.Name -Value ($_.Group | Measure-Object CPU -Sum).Sum -Unit CPU -Float
      } | Add-PrtgChannel
    Write-PrtgOutput

    Adds one channel per process NAME (total CPU across its instances), then writes PRTG JSON
    output. Both steps are required: several processes commonly share a name and channel names
    must be unique, and an ordinary machine has well over 50 distinct process names, so the
    list has to be capped to stay under the 50-channel limit.

  .EXAMPLE
    New-PrtgChannel -Channel 'A' -Value 1 | Add-PrtgChannel
    New-PrtgChannel -Channel 'B' -Value 2 | Add-PrtgChannel

    Adds two channels one after the other.

  .INPUTS
    PSCustomObject. Channel objects from New-PrtgChannel (or compatible structure).

  .LINK
    New-PrtgChannel
  .LINK
    Write-PrtgOutput
  #>
  [CmdletBinding()]
  param(
    [Parameter(
      Mandatory = $true,
      ValueFromPipeline = $true
    )]
    [PSCustomObject]$PrtgChannel
  )

  process {
    if ($script:OutputObject.prtg.result.Count -ge 50) {
      throw "PRTG allows a maximum of 50 channels per sensor; refusing to add another."
    }

    # PRTG requires channel names to be unique per sensor; duplicates are easy to generate
    # accidentally from process or service names, and PRTG's behaviour with them is undefined.
    if ($script:OutputObject.prtg.result.Channel -contains $PrtgChannel.Channel) {
      throw "A channel named '$($PrtgChannel.Channel)' was already added; PRTG requires channel names to be unique per sensor."
    }

    # Runs after the count and name checks, which tolerate a null document.
    Assert-PrtgOutputDocument -Caller $PSCmdlet -Action 'add a channel to' -Document $script:OutputObject

    [void] $script:OutputObject.prtg.result.Add($PrtgChannel)
  }
}
