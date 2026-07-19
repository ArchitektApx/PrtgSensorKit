function Get-PrtgMessage {
  <#
  .SYNOPSIS
    Returns the current sensor message text.

  .DESCRIPTION
    Reads the 'text' currently set on the module-scope output object (see Set-PrtgMessage).

  .EXAMPLE
    Set-PrtgMessage 'Working'
    Get-PrtgMessage   # -> 'Working'

  .OUTPUTS
    System.String. The current sensor message.

  .LINK
    Set-PrtgMessage
  #>
  return $script:OutputObject.prtg.text
}
