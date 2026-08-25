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

  $invocation = $ErrorObject.InvocationInfo
  $lineNumber = if ($invocation) { $invocation.ScriptLineNumber.ToString() } else { 'unknown' }
  $charOffset = if ($invocation) { $invocation.OffsetInLine.ToString() } else { 'unknown' }
  $sourceLine = if ($invocation) { $invocation.Line.ToString() } else { '' }

  "line:$lineNumber " +
  "char:$charOffset --- " +
  "message: $($ErrorObject.Exception.Message.ToString()) --- " +
  "line: $sourceLine"
}
