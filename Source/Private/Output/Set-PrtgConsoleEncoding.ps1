function Set-PrtgConsoleEncoding {
  <#
  .SYNOPSIS
    Sets stdout to UTF-8; never throws.
  .DESCRIPTION
    On .NET Framework the setter fails when no console is attached, so the failure is only
    written to the verbose stream.
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Non-interactive console setup on the sensor output path; a -Confirm prompt would stall a PRTG probe.')]
  [CmdletBinding()]
  param()

  try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
  } catch {
    Write-Verbose "Console output encoding could not be set. ($($_.Exception.Message))"
  }
}
