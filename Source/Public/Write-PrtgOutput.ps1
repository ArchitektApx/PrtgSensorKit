function Write-PrtgOutput {
  <#
  .SYNOPSIS
    Emits the current sensor output as PRTG JSON.

  .DESCRIPTION
    Serializes the module-scope output object (channels and message) to the JSON structure
    PRTG expects and writes it to the output stream. Call this once, last, after adding all
    channels with Add-PrtgChannel and optionally setting text with Set-PrtgMessage.

  .EXAMPLE
    New-PrtgChannel -Channel 'A' -Value 1 | Add-PrtgChannel
    Write-PrtgOutput

    Emits a sensor result containing a single channel.

  .OUTPUTS
    System.String. The PRTG sensor JSON.

  .LINK
    Add-PrtgChannel
  .LINK
    Set-PrtgMessage
  #>
  [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
  Write-Output ($script:OutputObject | ConvertTo-Json -Depth 10)
}
