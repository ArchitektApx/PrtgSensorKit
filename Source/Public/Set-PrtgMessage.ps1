function Set-PrtgMessage {
  <#
  .SYNOPSIS
    Sets the sensor message text.

  .DESCRIPTION
    Sets the 'text' shown for the sensor in PRTG. The number sign (#) is stripped and the
    message is truncated to 2000 characters automatically, as PRTG requires.

  .PARAMETER Text
    The sensor message.

  .EXAMPLE
    Set-PrtgMessage 'All checks passed'

    Sets the sensor message.

  .LINK
    Get-PrtgMessage
  .LINK
    Write-PrtgOutput
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Only mutates in-memory module-scope output state; nothing persistent to confirm and sensors run non-interactively.')]
  [CmdletBinding()]
  param(
    [string]$Text
  )

  $script:OutputObject.prtg.text = Format-PrtgMessage $Text
}
