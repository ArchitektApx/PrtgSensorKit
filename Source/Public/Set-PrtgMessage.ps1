function Set-PrtgMessage {
  <#
  .SYNOPSIS
    Sets the sensor message text.

  .DESCRIPTION
    Sets the 'text' shown for the sensor in PRTG. The number sign (#) is stripped and the
    message is truncated to 2000 characters automatically, as PRTG requires.

    The text can be piped in. Each piped item overwrites the message, so piping several items
    leaves the last one as the message, and an empty pipeline leaves the message untouched.
    A piped object binds as its string form; pipe the property you mean.

  .PARAMETER Text
    The sensor message. Accepts pipeline input.

  .EXAMPLE
    Set-PrtgMessage 'All checks passed'

    Sets the sensor message.

  .EXAMPLE
    (Get-ServiceStatus).Message | Set-PrtgMessage

    Sets the sensor message from a command's output.

  .INPUTS
    String. The sensor message.

  .LINK
    Get-PrtgMessage
  .LINK
    Write-PrtgOutput
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Only mutates in-memory module-scope output state; nothing persistent to confirm and sensors run non-interactively.')]
  [CmdletBinding()]
  param(
    [Parameter(ValueFromPipeline = $true)]
    [string]$Text
  )

  process {
    Assert-PrtgOutputDocument -Caller $PSCmdlet -Action 'set a message on' -Document $script:OutputObject

    $script:OutputObject.prtg.text = Format-PrtgMessage $Text
  }
}
