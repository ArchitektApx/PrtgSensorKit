function Get-PrtgSecret {
  <#
  .SYNOPSIS
    Reads a secret previously stored with Save-PrtgSecret.

  .DESCRIPTION
    Loads a DPAPI-protected secret and returns it as a SecureString or PSCredential (whatever
    was saved). Decryption only succeeds when this runs as the SAME Windows account on the SAME
    machine that saved the secret - which for a sensor means the account PRTG runs it as.

    Windows only.

  .PARAMETER Name
    Identifier passed to Save-PrtgSecret.

  .PARAMETER Path
    Folder the secret was stored in. Defaults to '$env:ProgramData\PrtgSensorKit\Secrets'.

  .PARAMETER AsPlainText
    Return the secret as a plain [string] instead of a SecureString/PSCredential. For a stored
    SecureString this is the secret itself; for a stored PSCredential this is the password. Use
    only when an API requires the raw value - it defeats the point of keeping it a SecureString.
    Throws if the stored payload is neither, which only happens for a hand-written or truncated
    file, rather than silently returning an object that would stringify into a request header.

  .PARAMETER AllowUnprotected
    Development only. Allows reading a secret off Windows, where it was stored obfuscated rather
    than DPAPI-encrypted (see Save-PrtgSecret -AllowUnprotected). Never needed on a Windows sensor.

  .EXAMPLE
    $token = Get-PrtgSecret -Name 'AcmeApi' -AsPlainText
    Invoke-RestMethod -Uri $url -Headers @{ Authorization = "Bearer $token" }

    Reads a token for use in a web request.

  .EXAMPLE
    $cred = Get-PrtgSecret -Name 'SqlLogin'
    Invoke-Sqlcmd -Credential $cred -ServerInstance 'db01' -Query '...'

    Reads a stored credential and uses it directly.

  .LINK
    Save-PrtgSecret
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$Name,

    [Parameter(Mandatory = $false)]
    [string]$Path,

    [Parameter(Mandatory = $false)]
    [switch]$AsPlainText,

    [Parameter(Mandatory = $false)]
    [switch]$AllowUnprotected
  )

  $onWindows = Test-PrtgWindows
  if (-not $onWindows -and -not $AllowUnprotected) {
    throw "PrtgSensorKit secret storage uses Windows DPAPI and NTFS ACLs; it is only available on Windows. Pass -AllowUnprotected to read an OBFUSCATED (not encrypted) development secret."
  }

  if ([string]::IsNullOrEmpty($Path)) {
    $Path = if ($onWindows) { Join-Path $env:ProgramData 'PrtgSensorKit\Secrets' }
            else { Join-Path ([System.IO.Path]::GetTempPath()) 'PrtgSensorKit/Secrets' }
  }

  $file = Join-Path $Path "$Name.clixml"
  if (-not (Test-Path -LiteralPath $file)) {
    throw "Secret '$Name' not found at '$file'. Save it first with Save-PrtgSecret, running as the same account this sensor runs as (e.g. Local System)."
  }

  try {
    $object = Import-Clixml -LiteralPath $file
  } catch [System.Xml.XmlException] {
    # Malformed XML is file corruption, not an account mismatch. Blaming DPAPI here would send
    # the operator off to check permissions for a problem no re-permissioning can fix.
    throw "Secret '$Name' at '$file' is corrupt: the file is not well-formed XML, so it was not written completely. Re-save it with Save-PrtgSecret. ($($_.Exception.Message))"
  } catch {
    $who = if ($onWindows) { [System.Security.Principal.WindowsIdentity]::GetCurrent().Name } else { $env:USER }
    throw "Failed to decrypt secret '$Name'. DPAPI-protected secrets can only be read by the same Windows account and machine that saved them; this is running as '$who'. Re-save the secret as that account. ($($_.Exception.Message))"
  }

  # A truncated file (a save that failed part-way) deserializes to $null WITHOUT throwing above.
  if ($null -eq $object) {
    throw "Secret '$Name' at '$file' is empty or truncated, so it holds no usable value. Re-save it with Save-PrtgSecret."
  }

  if ($AsPlainText) {
    # The module KNOWS this value is a secret, so register it for masking before handing it
    # out: an exception message that echoes it back (a failing Invoke-RestMethod URI, say)
    # is otherwise emitted to PRTG in the clear.
    if ($object -is [System.Management.Automation.PSCredential]) {
      $plain = $object.GetNetworkCredential().Password
      Add-PrtgRedaction $plain
      return $plain
    }
    if ($object -is [System.Security.SecureString]) {
      $plain = [System.Net.NetworkCredential]::new('', $object).Password
      Add-PrtgRedaction $plain
      return $plain
    }
    # Only reachable for a hand-written or foreign clixml. Throwing beats returning an object the
    # caller asked to get as a string.
    throw "Secret '$Name' holds a [$($object.GetType().FullName)], not a PSCredential or SecureString, so -AsPlainText cannot produce a string. Re-save it with Save-PrtgSecret -Secret or -Credential."
  }

  return $object
}
