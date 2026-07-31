# Module-scope registry of secret values to mask on their way out of the module. PRTG's
# manual warns that placeholders are resolved before the output is displayed, so a credential
# echoed back in an error message ends up on screen in the clear; this is the defence in depth
# against that. Ordinal comparison: two strings that differ only by culture-sensitive casing
# rules are different secrets.
$script:PrtgRedactions = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

function Add-PrtgRedaction {
  # Registers a secret value for masking in sensor output and logs. Private on purpose:
  # redaction seeds itself from what the module already knows (PRTG's resolved credential
  # placeholders and Get-PrtgSecret -AsPlainText), so a sensor author never has to opt in.
  [CmdletBinding()]
  param(
    [AllowNull()]
    [AllowEmptyString()]
    [string]$Value
  )

  # Under 6 chars: masking would mangle ordinary text and protects nothing meaningful.
  if (-not [string]::IsNullOrEmpty($Value) -and $Value.Length -ge 6) {
    [void]$script:PrtgRedactions.Add($Value)
  }
}

function Initialize-PrtgRedaction {
  # PRTG's "Set placeholders as environment values" exposes the SAME resolved strings the
  # command line received, so seeding from these also covers a credential the user passed
  # as a script parameter - which the sensor otherwise cannot recognise as sensitive.
  # Credential placeholders only: user names, domains, and host names are not secrets and
  # redacting them would only make troubleshooting harder.
  [CmdletBinding()]
  param()

  foreach ($name in 'prtg_windowspassword', 'prtg_linuxpassword', 'prtg_snmpcommunity') {
    $value = [Environment]::GetEnvironmentVariable($name)

    # RFC 1157 default communities are not secrets, and 'public' (exactly 6 chars) would clear
    # the length gate and mask an ordinary word everywhere ('Republic' -> 'Re*****'). Community
    # placeholder only: a PASSWORD of 'public' is still a secret and still registers.
    if ($name -eq 'prtg_snmpcommunity' -and $value -in @('public', 'private')) { continue }

    Add-PrtgRedaction $value
  }
}

function Protect-PrtgSecretText {
  # Masks every registered secret. Partial masking (first few characters kept) so an
  # operator can still tell WHICH credential appeared; the asterisk mask itself is a fixed
  # five characters and at most six characters are ever revealed, so the output never grows
  # with the secret.
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [AllowNull()]
    [AllowEmptyString()]
    [string]$Text
  )

  if ([string]::IsNullOrEmpty($Text) -or $script:PrtgRedactions.Count -eq 0) { return $Text }

  # Longest first: when one registered secret contains another, HashSet iteration order is
  # unspecified, so masking the shorter one first would leave a different (and nondeterministic)
  # result than masking the longer one first.
  foreach ($secret in ($script:PrtgRedactions | Sort-Object -Property Length -Descending)) {
    $reveal = if ($secret.Length -ge 12) { [Math]::Min(6, [Math]::Ceiling($secret.Length / 3)) } else { 0 }
    $mask = if ($reveal -gt 0) { $secret.Substring(0, $reveal) + '*****' } else { '*****' }
    $Text = $Text.Replace($secret, $mask)
  }

  $Text
}

# Seeded at import: PRTG sets the placeholder environment variables before starting the
# sensor process, so they are already there. Invoke-PrtgSensor re-seeds, for a long-lived
# host that imported the module before the variables existed.
Initialize-PrtgRedaction
