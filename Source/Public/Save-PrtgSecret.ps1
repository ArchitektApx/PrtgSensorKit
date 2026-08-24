function Save-PrtgSecret {
  <#
  .SYNOPSIS
    Saves a secret (SecureString or PSCredential) encrypted with Windows DPAPI for later use by a sensor.

  .DESCRIPTION
    Stores an API token, password, or full credential so a sensor never has to carry it in
    plain text. The secret is written with Export-Clixml, which protects it using Windows DPAPI:
    the file can only be decrypted by the SAME Windows account on the SAME machine that saved it.

    IMPORTANT - run this AS the account the sensor runs as. A PRTG custom sensor runs as Local
    System or the Windows credentials configured on the device/probe. You must save the secret
    while running as that same account, or Get-PrtgSecret will fail to decrypt it at sensor time.
    For Local System, run the save under Local System (for example via 'PsExec -s').

    Windows only. Each secret FILE is ACL-locked to the saving account, Administrators, and
    SYSTEM. The store FOLDER is left as an ordinary directory, because it is shared by every
    sensor account on the probe: several accounts save into it, and each owns only its own files.

    Secret names are a shared namespace within the store. The first account to save a given name
    owns that file, and another account cannot overwrite it without administrator help, so give
    each sensor account its own secret names (or its own -Path).

  .PARAMETER Name
    Identifier for the secret. Used as the file name, so it is restricted to letters, digits,
    dot, dash, and underscore.

  .PARAMETER Secret
    The secret as a SecureString (e.g. an API token). Use this or -Credential.

  .PARAMETER Credential
    A full PSCredential (user name + password). Use this or -Secret.

  .PARAMETER Path
    Folder to store secrets in. Defaults to '$env:ProgramData\PrtgSensorKit\Secrets' on Windows,
    or a temp folder when -AllowUnprotected is used off Windows. The folder itself is created if
    missing but is otherwise not modified: only the secret files written into it are ACL-locked,
    so pointing this at a folder with other content is safe.

  .PARAMETER AllowUnprotected
    Development only. Off Windows there is no DPAPI, so Export-Clixml stores the secret merely
    OBFUSCATED (the UTF-16 bytes), not encrypted - anyone who can read the file can recover it.
    This switch opts in to that behaviour so you can exercise sensor logic on non-Windows; it
    prints a warning and never applies on a real Windows sensor host. Do not use for real secrets.

  .EXAMPLE
    Save-PrtgSecret -Name 'AcmeApi' -Secret (Read-Host -AsSecureString)

    Prompts for a token and stores it encrypted for the current account.

  .EXAMPLE
    Save-PrtgSecret -Name 'SqlLogin' -Credential (Get-Credential)

    Stores a user name and password for later use in a sensor.

  .NOTES
    DPAPI ties the encryption to the saving account and machine - the secret does not roam to
    other users or servers. Re-save it per machine / per sensor account.

  .LINK
    Get-PrtgSecret
  #>
  [CmdletBinding(DefaultParameterSetName = 'SecureString')]
  param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$Name,

    [Parameter(Mandatory = $true, ParameterSetName = 'SecureString')]
    [System.Security.SecureString]$Secret,

    [Parameter(Mandatory = $true, ParameterSetName = 'Credential')]
    [System.Management.Automation.PSCredential]$Credential,

    [Parameter(Mandatory = $false)]
    [string]$Path,

    [Parameter(Mandatory = $false)]
    [switch]$AllowUnprotected
  )

  $onWindows = Test-PrtgWindows
  if (-not $onWindows) {
    if (-not $AllowUnprotected) {
      throw "PrtgSensorKit secret storage uses Windows DPAPI and NTFS ACLs; it is only available on Windows. Pass -AllowUnprotected to store an OBFUSCATED (not encrypted) secret for development only."
    }
    Write-Warning "Save-PrtgSecret: off Windows the secret is only OBFUSCATED, NOT encrypted (DPAPI is unavailable). Anyone who can read '$Name' can recover it. Use for development only - never for real credentials."
  }

  $Path = Get-PrtgSecretPath -Path $Path

  # Creation stays here rather than in the resolver, which only answers where the secret lives:
  # this is the one caller that wants the folder, and reading must leave nothing behind.
  if (-not (Test-Path -LiteralPath $Path)) {
    [void] (New-Item -ItemType Directory -Path $Path -Force)
  }

  $file = Join-Path $Path "$Name.clixml"
  $object = if ($PSCmdlet.ParameterSetName -eq 'Credential') { $Credential } else { $Secret }

  # Sweep leftovers from a save interrupted BEFORE this cmdlet shared the atomic writer. Those
  # temps are named '<Name>.<guid>.tmp', while the writer derives both its temp name and its own
  # sweep filter from the full leaf, so its '<Name>.clixml.*.tmp' filter cannot match them. A
  # stranded secret temp holds real encrypted payload under hardened permissions, so it is swept
  # here rather than left on disk forever. Age-limited, because the secret store has no lock: a
  # second sensor instance saving the same name right now must keep its in-flight temp file.
  Remove-PrtgStaleTempFile -Folder $Path -Filter "$Name.*.tmp"

  # NTFS ACL hardening is Windows-only; the DPAPI protection is what matters and only exists here.
  # Applied at BOTH hook points on purpose: to the temp file before the blob is written, so the
  # secret never exists under inherited ProgramData permissions, and to the destination after the
  # swap, because [System.IO.File]::Replace keeps the ACL of the file it replaced - a secret
  # re-saved by a different account would otherwise stay locked to the previous one.
  #
  # The store FOLDER is deliberately left alone: it is shared by every sensor account on the
  # probe, and locking it to one account locks the others out of their own secret files.
  $writeArgs = @{
    PrtgWriteInputObject = $object
    PrtgWriteLiteralPath = $file
  }
  if ($onWindows) {
    # The path arrives as an argument, so the block never resolves it up the dynamic scope chain.
    $harden = { param($PrtgSecretHardenPath) Set-PrtgSecretAcl -Path $PrtgSecretHardenPath }
    $writeArgs['PrtgWriteBeforeWrite'] = $harden
    $writeArgs['PrtgWriteAfterSwap'] = $harden
  }

  try {
    Export-PrtgClixmlAtomic @writeArgs
  } catch [System.UnauthorizedAccessException], [System.IO.IOException] {
    # The store folder is shared, but each secret file is locked to the account that saved it,
    # so the swap is where a name collision between accounts surfaces. Without this the operator
    # only sees a raw access-denied naming the temporary file. This stays a wrapper rather than a
    # hook: it encodes a secret-store concept the generic writer has no business knowing, and the
    # writer's own cleanup catch runs first, so this arm sees the exception only after a rethrow.
    $who = if ($onWindows) { [System.Security.Principal.WindowsIdentity]::GetCurrent().Name } else { $env:USER }
    throw ("Failed to replace secret '$Name' at '$file' while running as '$who'. The existing " +
      "file belongs to another account or is held open by another process. Delete it as an " +
      "administrator and save the secret again. ($($_.Exception.Message))")
  }

  if ($onWindows) {
    Write-Verbose "Saved secret '$Name' to '$file' (DPAPI-protected for account '$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)')."
  } else {
    Write-Verbose "Saved OBFUSCATED (not encrypted) secret '$Name' to '$file'."
  }
}
