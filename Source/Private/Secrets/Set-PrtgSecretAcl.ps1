function Set-PrtgSecretAcl {
  <#
  .SYNOPSIS
    Locks a secret file down to the account that created it, Administrators, and SYSTEM.
  .DESCRIPTION
    Windows-only NTFS hardening on top of the DPAPI protection, so that other non-admin
    users cannot read the encrypted blob either.
  .PARAMETER Path
    The secret file. Never the store folder.
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseCompatibleCommands', '',
    Justification = 'Get-Acl/Set-Acl are Windows-only by design; this helper is only ever called on Windows (Save-PrtgSecret guards the call with Test-PrtgWindows).')]
  [CmdletBinding(SupportsShouldProcess = $true)]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $acl = Get-Acl -LiteralPath $Path

  # Inheritance off and every existing rule dropped, so only the three rules below remain.
  $acl.SetAccessRuleProtection($true, $false)
  @($acl.Access) | ForEach-Object { [void]$acl.RemoveAccessRule($_) }

  # 'None': the target is a file, so nothing can inherit the rules.
  $inherit = 'None'
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
