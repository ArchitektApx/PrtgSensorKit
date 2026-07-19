function Add-PrtgChannel {
  <#
  .SYNOPSIS
    Adds a PRTG channel object to the current sensor output.

  .DESCRIPTION
    Appends a channel object to the module-scope result collection. Build output incrementally:
    add channels via this cmdlet (one per call, pipeline-friendly), then emit the JSON with
    Write-PrtgOutput. PRTG allows a maximum of 50 channels per sensor, so adding a 51st throws.

    Channel objects are typically created with New-PrtgChannel.

  .PARAMETER PrtgChannel
    A channel object (PSCustomObject) to add to the output. Usually from New-PrtgChannel.
    Accepts pipeline input.

  .EXAMPLE
    Get-Process | ForEach-Object { New-PrtgChannel -Channel $_.ProcessName -Value $_.CPU -Float } | Add-PrtgChannel
    Write-PrtgOutput

    Adds a channel per process (CPU value), then writes PRTG JSON output.

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

    [void] $script:OutputObject.prtg.result.Add($PrtgChannel)
  }
}
