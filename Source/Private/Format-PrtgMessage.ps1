function Format-PrtgMessage {
  <#
  .SYNOPSIS
    Makes a string safe for a PRTG sensor message / error text.
  .DESCRIPTION
    PRTG does not support the number sign (#) in sensor messages and truncates messages at
    2000 characters. This strips '#' and truncates so the emitted text always conforms.
    Reference: https://www.paessler.com/manuals/prtg/custom_sensors

    Registered secrets (resolved PRTG credential placeholders, Get-PrtgSecret -AsPlainText
    values) are masked first - see PrtgRedaction.ps1. This is the chokepoint for sensor MESSAGE
    text, so no caller of Set-PrtgMessage or Write-PrtgError can bypass the masking. It is not a
    chokepoint for everything PRTG receives: channel names and values, and the manual
    Set-PrtgOutput / Write-PrtgOutput path, never pass through here.
  #>
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [AllowNull()]
    [AllowEmptyString()]
    [string]$Text
  )

  if ([string]::IsNullOrEmpty($Text)) { return '' }

  # Order is load-bearing, not cosmetic:
  #  - BEFORE the '#' strip, because a password containing '#' is registered WITH it; strip
  #    first and the text no longer matches the registered secret, leaking it in the clear.
  #  - BEFORE the truncation, because a secret straddling the 2000-char boundary would be cut
  #    in half and the surviving fragment would match nothing.
  $clean = (Protect-PrtgSecretText -Text $Text).Replace('#', '')
  if ($clean.Length -gt 2000) { $clean = $clean.Substring(0, 2000) }
  return $clean
}
