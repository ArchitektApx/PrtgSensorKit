function Set-PrtgConsoleEncoding {
  # Sets stdout to UTF-8 so non-ASCII channel names and messages reach PRTG intact.
  #
  # Never-throw: on .NET Framework this setter can fail when no console is attached, and every
  # caller runs it immediately BEFORE writing the sensor response - an unguarded throw would mean
  # emitting nothing at all.
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
