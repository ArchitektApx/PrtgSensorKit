function Clear-PrtgOutput {
  <#
  .SYNOPSIS
    Resets the sensor output state to an empty result set.

  .DESCRIPTION
    Re-initializes the module-scope output object (channels and text). Because module state
    persists for the lifetime of the imported module, call this to start a fresh sensor output
    when reusing the same session (e.g. between test cases or multiple sensor runs in one host).

  .EXAMPLE
    Clear-PrtgOutput
    New-PrtgChannel -Channel 'A' -Value 1 | Add-PrtgChannel
    Write-PrtgOutput
  #>
  [CmdletBinding()]
  param()

  $script:OutputObject = [PSCustomObject]@{
    prtg = [PSCustomObject]@{
      result = [System.Collections.ArrayList]@()
      text   = ''
    }
  }
}
