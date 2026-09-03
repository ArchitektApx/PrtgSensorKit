function Format-PrtgMessage {
  <#
  .SYNOPSIS
    Makes a string safe for a PRTG sensor message / error text.
  .DESCRIPTION
    PRTG does not support the number sign (#) in sensor messages and truncates messages at
    2000 characters. This strips '#' and truncates so the emitted text always conforms.
    Reference: https://www.paessler.com/manuals/prtg/custom_sensors

    Registered secrets are masked first (ADR 0005). Channel names and values, and the
    Set-PrtgOutput / Write-PrtgOutput path, do not pass through here.
  #>
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [AllowNull()]
    [AllowEmptyString()]
    [string]$Text
  )

  if ([string]::IsNullOrEmpty($Text)) { return '' }

  # Order is load-bearing: strip '#' and truncate only after masking, or a secret containing
  # '#' or straddling the cut stops matching.
  $clean = (Protect-PrtgSecretText -Text $Text).Replace('#', '')
  if ($clean.Length -gt 2000) { $clean = $clean.Substring(0, 2000) }
  return $clean
}
