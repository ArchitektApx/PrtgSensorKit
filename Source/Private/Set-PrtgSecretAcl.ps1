function Set-PrtgSecretAcl {
  # Locks a secret file or its folder down to the account that created it, Administrators, and
  # SYSTEM. DPAPI already restricts *decryption* to the saving account; this is defence in depth
  # so other non-admin users cannot even read the encrypted blob. Windows-only (uses NTFS ACLs).
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseCompatibleCommands', '',
    Justification = 'Get-Acl/Set-Acl are Windows-only by design; this helper is only ever called on Windows (Save-PrtgSecret guards the call with Test-PrtgWindows).')]
  [CmdletBinding(SupportsShouldProcess = $true)]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $item = Get-Item -LiteralPath $Path
  $acl = Get-Acl -LiteralPath $Path

  # Disable inheritance and drop any inherited/explicit rules so only ours remain.
  $acl.SetAccessRuleProtection($true, $false)
  @($acl.Access) | ForEach-Object { [void]$acl.RemoveAccessRule($_) }

  $inherit = if ($item.PSIsContainer) { 'ContainerInherit,ObjectInherit' } else { 'None' }
  $identities = @(
    [System.Security.Principal.WindowsIdentity]::GetCurrent().User            # the saving account
    [System.Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')       # BUILTIN\Administrators
    [System.Security.Principal.SecurityIdentifier]::new('S-1-5-18')           # NT AUTHORITY\SYSTEM
  )
  foreach ($id in $identities) {
    $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
      $id, 'FullControl', $inherit, 'None', 'Allow'
    )
    $acl.AddAccessRule($rule)
  }

  if ($PSCmdlet.ShouldProcess($Path, 'Restrict ACL to owner, Administrators, and SYSTEM')) {
    Set-Acl -LiteralPath $Path -AclObject $acl
  }
}
