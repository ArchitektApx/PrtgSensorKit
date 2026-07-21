function Format-PrtgErrorText {
  <#
  .SYNOPSIS
    Renders an ErrorRecord to the standard PRTG error text.
  .DESCRIPTION
    Produces the 'line:.. char:.. --- message: .. --- line: ..' rendering used for PRTG
    error responses. Shared by Write-PrtgError and by Invoke-PrtgSensor's retry handling,
    which prefixes it with the retry summary before emitting.
  #>
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory = $true)]
    [System.Management.Automation.ErrorRecord]$ErrorObject
  )

  "line:$($ErrorObject.InvocationInfo.ScriptLineNumber.ToString()) " +
  "char:$($ErrorObject.InvocationInfo.OffsetInLine.ToString()) --- " +
  "message: $($ErrorObject.Exception.Message.ToString()) --- " +
  "line: $($ErrorObject.InvocationInfo.Line.ToString())"
}
