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

    Windows only. The store folder and file are ACL-locked to the saving account, Administrators,
    and SYSTEM.

  .PARAMETER Name
    Identifier for the secret. Used as the file name, so it is restricted to letters, digits,
    dot, dash, and underscore.

  .PARAMETER Secret
    The secret as a SecureString (e.g. an API token). Use this or -Credential.

  .PARAMETER Credential
    A full PSCredential (user name + password). Use this or -Secret.

  .PARAMETER Path
    Folder to store secrets in. Defaults to '$env:ProgramData\PrtgSensorKit\Secrets' on Windows,
    or a temp folder when -AllowUnprotected is used off Windows.

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

  if ([string]::IsNullOrEmpty($Path)) {
    $Path = if ($onWindows) { Join-Path $env:ProgramData 'PrtgSensorKit\Secrets' }
            else { Join-Path ([System.IO.Path]::GetTempPath()) 'PrtgSensorKit/Secrets' }
  }

  if (-not (Test-Path -LiteralPath $Path)) {
    [void] (New-Item -ItemType Directory -Path $Path -Force)
  }

  $file = Join-Path $Path "$Name.clixml"
  $object = if ($PSCmdlet.ParameterSetName -eq 'Credential') { $Credential } else { $Secret }

  $object | Export-Clixml -LiteralPath $file -Force

  # NTFS ACL hardening is Windows-only; the DPAPI protection is what matters and only exists here.
  if ($onWindows) {
    Set-PrtgSecretAcl -Path $Path
    Set-PrtgSecretAcl -Path $file
  }

  if ($onWindows) {
    Write-Verbose "Saved secret '$Name' to '$file' (DPAPI-protected for account '$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)')."
  } else {
    Write-Verbose "Saved OBFUSCATED (not encrypted) secret '$Name' to '$file'."
  }
}
