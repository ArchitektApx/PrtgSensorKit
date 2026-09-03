function New-PrtgOutputDocument {
  <#
  .SYNOPSIS
    The single definition of the output document's shape.
  .DESCRIPTION
    'result' is an ArrayList, not an array, because Add-PrtgChannel appends to it in place.
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Pure factory that returns a new in-memory object; it changes no state, so -WhatIf/-Confirm do not apply.')]
  [CmdletBinding()]
  [OutputType([PSCustomObject])]
  param()

  [PSCustomObject]@{
    prtg = [PSCustomObject]@{
      result = [System.Collections.ArrayList]@()
      text   = ''
    }
  }
}
