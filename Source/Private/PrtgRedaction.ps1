# Module-scope registry of secret values to mask on their way out of the module (ADR 0005).
# Ordinal comparison: two strings that differ only by culture-sensitive casing are two secrets.
$script:PrtgRedactions = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

function Add-PrtgRedaction {
  <#
  .SYNOPSIS
    Registers a secret value for masking in sensor output and logs.
  #>
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
  <#
  .SYNOPSIS
    Seeds the registry from PRTG's credential placeholder environment variables.
  .DESCRIPTION
    Passwords and community strings only. User names, domains, and host names are not
    secrets and stay readable.
  #>
  [CmdletBinding()]
  param()

  foreach ($name in 'prtg_windowspassword', 'prtg_linuxpassword', 'prtg_snmpcommunity') {
    $value = [Environment]::GetEnvironmentVariable($name)

    # The RFC 1157 default communities are not secrets, and 'public' clears the length gate.
    # A password of 'public' still registers.
    if ($name -eq 'prtg_snmpcommunity' -and $value -in @('public', 'private')) { continue }

    Add-PrtgRedaction $value
  }
}

function Protect-PrtgSecretText {
  <#
  .SYNOPSIS
    Masks every registered secret in a string.
  .DESCRIPTION
    Masking is partial: at most six leading characters survive, followed by a fixed
    five-asterisk mask, so an operator can still tell which credential appeared.
  #>
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [AllowNull()]
    [AllowEmptyString()]
    [string]$Text
  )

  if ([string]::IsNullOrEmpty($Text) -or $script:PrtgRedactions.Count -eq 0) { return $Text }

  # Longest first: when one registered secret contains another, HashSet iteration order is
  # unspecified, so masking the shorter one first gives a nondeterministic result.
  foreach ($secret in ($script:PrtgRedactions | Sort-Object -Property Length -Descending)) {
    $reveal = if ($secret.Length -ge 12) { [Math]::Min(6, [Math]::Ceiling($secret.Length / 3)) } else { 0 }
    $mask = if ($reveal -gt 0) { $secret.Substring(0, $reveal) + '*****' } else { '*****' }
    $Text = $Text.Replace($secret, $mask)
  }

  $Text
}

# Seeded at import: PRTG sets the placeholder variables before starting the sensor process.
# Invoke-PrtgSensor re-seeds for a host that imported the module before they existed.
Initialize-PrtgRedaction
