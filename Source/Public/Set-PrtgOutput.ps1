function Set-PrtgOutput {
  <#
  .SYNOPSIS
    Replaces the entire sensor output object.

  .DESCRIPTION
    Overwrites the module-scope output object with the one provided. Most sensors never need
    this - build output with New-PrtgChannel / Add-PrtgChannel instead. Use it only
    when you want to supply a fully pre-built object with the PRTG shape (a 'prtg' property
    containing 'result' and 'text').

  .PARAMETER Object
    The replacement output object. Must have the PRTG structure for Add-PrtgChannel,
    Set-PrtgMessage, and Write-PrtgOutput to keep working.

  .EXAMPLE
    $custom = [PSCustomObject]@{ prtg = [PSCustomObject]@{ result = [System.Collections.ArrayList]@(); text = '' } }
    Set-PrtgOutput $custom

    Replaces the current output object with a custom one.

  .LINK
    Clear-PrtgOutput
  .LINK
    Write-PrtgOutput
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Only replaces the in-memory module-scope output object; nothing persistent to confirm and sensors run non-interactively.')]
  [CmdletBinding()]
  param(
    $Object
  )

  $script:OutputObject = $Object
}
