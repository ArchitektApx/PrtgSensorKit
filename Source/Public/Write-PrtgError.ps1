function Write-PrtgError {
  <#
  .SYNOPSIS
    Outputs an error to PRTG.

  .DESCRIPTION
    Emits a PRTG error response (JSON) that replaces all channel data with a single error
    message. The number sign (#) is stripped and the message is truncated to 2000 characters,
    as PRTG requires.

  .PARAMETER ErrorObject
    The error object to output. This is typically the $_ variable in a try/catch block or
    the $Error[0] variable. The emitted message includes line, char, message, and source line.

  .PARAMETER ErrorString
    A custom error message to output.

  .EXAMPLE
    Write-PrtgError -ErrorObject $_

    Reports a caught error (from a trap or catch block) to PRTG.

  .EXAMPLE
    Write-PrtgError -ErrorString "My error message"

    Reports a custom error message to PRTG.

  .LINK
    Write-PrtgOutput
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseProcessBlockForPipelineCommand', '',
    Justification = 'A PRTG sensor returns exactly one error response. Deliberately no process block, so piping multiple errors yields a single response, not one per error.')]
  [CmdletBinding()]
  param (
    [Parameter(
      Mandatory = $true,
      ValueFromPipeline = $true,
      ParameterSetName = 'ErrorObject'
    )]
    [System.Management.Automation.ErrorRecord]
    $ErrorObject,
    [Parameter(
      Mandatory = $true,
      ValueFromPipeline = $true,
      ParameterSetName = 'ErrorString'
    )]
    [string]
    $ErrorString
  )

  $RawText = if ($PsCmdlet.ParameterSetName -eq 'ErrorObject') {
    "line:$($ErrorObject.InvocationInfo.ScriptLineNumber.ToString()) " +
    "char:$($ErrorObject.InvocationInfo.OffsetInLine.ToString()) --- " +
    "message: $($ErrorObject.Exception.Message.ToString()) --- " +
    "line: $($ErrorObject.InvocationInfo.Line.ToString())"
  } else {
    $ErrorString
  }

  $ErrorOutput = [PSCustomObject]@{
    prtg = [PSCustomObject]@{
      error = 1
      text  = Format-PrtgMessage $RawText
    }
  }

  [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
  Write-Output ($ErrorOutput | ConvertTo-Json -Depth 10)
}