BeforeAll {
  . $PSScriptRoot/_TestHelpers.ps1
  Import-BuiltPrtgModule
}

# Dot-sourced at top level as well as in BeforeAll: Pester evaluates -Skip: at DISCOVERY time,
# before any BeforeAll has run.
. $PSScriptRoot/_TestHelpers.ps1
$onWindows = Test-OnWindowsHost

Describe 'Save/Get-PrtgSecret (cross-platform)' {
  It 'round-trips a SecureString (AsPlainText matches)' {
    $path = Join-Path $TestDrive 'secrets'
    $ss = ConvertTo-SecureString 'tok3n' -AsPlainText -Force
    Save-PrtgSecret -Name 'Api' -Secret $ss -Path $path -AllowUnprotected -WarningAction SilentlyContinue
    Get-PrtgSecret -Name 'Api' -Path $path -AllowUnprotected -AsPlainText | Should -Be 'tok3n'
  }

  It 'round-trips a PSCredential (user + password)' {
    $path = Join-Path $TestDrive 'secrets'
    $cred = [System.Management.Automation.PSCredential]::new(
      'dom\user', (ConvertTo-SecureString 'pw' -AsPlainText -Force))
    Save-PrtgSecret -Name 'Login' -Credential $cred -Path $path -AllowUnprotected -WarningAction SilentlyContinue
    $got = Get-PrtgSecret -Name 'Login' -Path $path -AllowUnprotected
    $got.UserName | Should -Be 'dom\user'
    $got.GetNetworkCredential().Password | Should -Be 'pw'
  }

  It 'rejects an invalid secret name' {
    { Save-PrtgSecret -Name 'bad/name' -Secret (ConvertTo-SecureString 'x' -AsPlainText -Force) `
        -AllowUnprotected -ErrorAction Stop } | Should -Throw
  }

  It 'errors clearly when reading a missing secret' {
    { Get-PrtgSecret -Name 'DoesNotExist' -Path (Join-Path $TestDrive 'empty') -AllowUnprotected -ErrorAction Stop } |
      Should -Throw
  }

  It 'returns the password with -AsPlainText for a stored PSCredential' {
    $path = Join-Path $TestDrive 'plain'
    $cred = [System.Management.Automation.PSCredential]::new(
      'u', (ConvertTo-SecureString 'pw-plain' -AsPlainText -Force))
    Save-PrtgSecret -Name 'Cred' -Credential $cred -Path $path -AllowUnprotected -WarningAction SilentlyContinue
    Get-PrtgSecret -Name 'Cred' -Path $path -AllowUnprotected -AsPlainText | Should -Be 'pw-plain'
  }

  It 'throws a clear error when the stored file cannot be read back' {
    $path = Join-Path $TestDrive 'broken'
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $path 'Broke.clixml') -Value 'not valid clixml'
    { Get-PrtgSecret -Name 'Broke' -Path $path -AllowUnprotected -ErrorAction Stop } | Should -Throw
  }
}

Describe 'Save/Get-PrtgSecret off Windows guard' -Skip:$onWindows {
  It 'Save refuses without -AllowUnprotected off Windows' {
    { Save-PrtgSecret -Name 'X' -Secret (ConvertTo-SecureString 'x' -AsPlainText -Force) `
        -Path (Join-Path $TestDrive 's') -ErrorAction Stop } | Should -Throw
  }

  It 'Get refuses without -AllowUnprotected off Windows' {
    { Get-PrtgSecret -Name 'X' -Path (Join-Path $TestDrive 's') -ErrorAction Stop } | Should -Throw
  }

  It 'round-trips using the default temp path (no -Path) off Windows' {
    $default = Join-Path ([System.IO.Path]::GetTempPath()) 'PrtgSensorKit'
    try {
      Save-PrtgSecret -Name 'DefTmp' -Secret (ConvertTo-SecureString 'deftmp' -AsPlainText -Force) `
        -AllowUnprotected -WarningAction SilentlyContinue
      Get-PrtgSecret -Name 'DefTmp' -AllowUnprotected -AsPlainText | Should -Be 'deftmp'
    } finally {
      Remove-Item $default -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

Describe 'Save/Get-PrtgSecret DPAPI + ACL (Windows only)' -Tag 'Windows' -Skip:(-not $onWindows) {
  It 'encrypts the blob (not plaintext on disk)' {
    $path = Join-Path $TestDrive 'wsecrets'
    Save-PrtgSecret -Name 'Api' -Secret (ConvertTo-SecureString 'PLAINTEXT-MARKER' -AsPlainText -Force) -Path $path
    (Get-Content -Raw (Join-Path $path 'Api.clixml')) | Should -Not -Match 'PLAINTEXT-MARKER'
  }

  It 'locks the file ACL (inheritance off, no Everyone/Users)' {
    $path = Join-Path $TestDrive 'wsecrets2'
    Save-PrtgSecret -Name 'Api' -Secret (ConvertTo-SecureString 'x' -AsPlainText -Force) -Path $path
    $acl = Get-Acl (Join-Path $path 'Api.clixml')
    $acl.AreAccessRulesProtected | Should -BeTrue
    ($acl.Access.IdentityReference.Value -join ';') | Should -Not -Match 'Everyone|BUILTIN\\Users'
  }

  It 'grants exactly the saving account, Administrators, and SYSTEM on the file' {
    $path = Join-Path $TestDrive 'aclexact'
    Save-PrtgSecret -Name 'Api' -Secret (ConvertTo-SecureString 'x' -AsPlainText -Force) -Path $path
    $acl = Get-Acl (Join-Path $path 'Api.clixml')
    $sids = $acl.Access | ForEach-Object { $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value }
    $expected = @(
      [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
      'S-1-5-32-544'
      'S-1-5-18'
    )
    ($sids | Sort-Object -Unique) -join ';' | Should -Be (($expected | Sort-Object -Unique) -join ';')
    ($acl.Access | Where-Object { $_.FileSystemRights -ne 'FullControl' }) | Should -BeNullOrEmpty
  }

  It 'leaves the secret folder ACL alone' {
    # Regression test for the multi-account lockout.
    $path = Join-Path $TestDrive 'folderacl'
    Save-PrtgSecret -Name 'Api' -Secret (ConvertTo-SecureString 'x' -AsPlainText -Force) -Path $path
    (Get-Acl $path).AreAccessRulesProtected | Should -BeFalse
  }

  It 'keeps the file ACL when the same secret name is saved twice' {
    # A re-save swaps a new file in over the old one, so the ACL must come out unchanged.
    $path = Join-Path $TestDrive 'resave'
    Save-PrtgSecret -Name 'Api' -Secret (ConvertTo-SecureString 'one' -AsPlainText -Force) -Path $path
    $first = (Get-Acl (Join-Path $path 'Api.clixml')).Sddl
    Save-PrtgSecret -Name 'Api' -Secret (ConvertTo-SecureString 'two' -AsPlainText -Force) -Path $path
    (Get-Acl (Join-Path $path 'Api.clixml')).Sddl | Should -Be $first
    (Get-Acl (Join-Path $path 'Api.clixml')).AreAccessRulesProtected | Should -BeTrue
    Get-PrtgSecret -Name 'Api' -Path $path -AsPlainText | Should -Be 'two'
  }

  It 're-locks the file after the swap, which inherits the REPLACED file ACL' {
    # [File]::Replace keeps the destination's ACL, not the temp file's, so a re-save over a file
    # whose ACL is wrong (saved by another account, or edited by hand) would keep the wrong one.
    # The previous test cannot catch this: both ACLs are already correct there.
    $path = Join-Path $TestDrive 'reacl'
    Save-PrtgSecret -Name 'Relock' -Secret (ConvertTo-SecureString 'one' -AsPlainText -Force) -Path $path
    $file = Join-Path $path 'Relock.clixml'

    # Get-Acl reports identities as NTAccount, so compare on the resolved SID string; comparing
    # an NTAccount against a SecurityIdentifier object is always false and asserts nothing.
    function Get-AclSid([string]$File) {
      @((Get-Acl -LiteralPath $File).Access.IdentityReference |
        ForEach-Object { $_.Translate([System.Security.Principal.SecurityIdentifier]).Value })
    }

    # Strip SYSTEM, leaving the current account and Administrators so the re-save can still run.
    $tampered = Get-Acl -LiteralPath $file
    @($tampered.Access) |
      Where-Object { $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value -eq 'S-1-5-18' } |
      ForEach-Object { [void]$tampered.RemoveAccessRule($_) }
    Set-Acl -LiteralPath $file -AclObject $tampered
    Get-AclSid $file | Should -Not -Contain 'S-1-5-18'

    Save-PrtgSecret -Name 'Relock' -Secret (ConvertTo-SecureString 'two' -AsPlainText -Force) -Path $path
    Get-AclSid $file | Should -Contain 'S-1-5-18'
    Get-PrtgSecret -Name 'Relock' -Path $path -AsPlainText | Should -Be 'two'
  }

  It 'a second secret in the same folder does not disturb the first file ACL' {
    $path = Join-Path $TestDrive 'twosecrets'
    Save-PrtgSecret -Name 'A' -Secret (ConvertTo-SecureString 'a' -AsPlainText -Force) -Path $path
    $firstSddl = (Get-Acl (Join-Path $path 'A.clixml')).Sddl
    Save-PrtgSecret -Name 'B' -Secret (ConvertTo-SecureString 'b' -AsPlainText -Force) -Path $path
    (Get-Acl (Join-Path $path 'A.clixml')).Sddl | Should -Be $firstSddl
    Get-PrtgSecret -Name 'A' -Path $path -AsPlainText | Should -Be 'a'
    Get-PrtgSecret -Name 'B' -Path $path -AsPlainText | Should -Be 'b'
  }

  It 'an explicit foreign ACE on the folder survives a save' {
    # BUILTIN\Users (S-1-5-32-545) stands in for a second sensor account.
    $path = Join-Path $TestDrive 'foreignace'
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    $users = [System.Security.Principal.SecurityIdentifier]::new('S-1-5-32-545')
    $acl = Get-Acl $path
    $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new(
        $users, 'ReadAndExecute', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
    Set-Acl -LiteralPath $path -AclObject $acl
    Save-PrtgSecret -Name 'Api' -Secret (ConvertTo-SecureString 'x' -AsPlainText -Force) -Path $path
    $after = (Get-Acl $path).Access | ForEach-Object { $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value }
    $after | Should -Contain 'S-1-5-32-545'
  }

  It 'never leaves the blob readable under inherited permissions' {
    $path = Join-Path $TestDrive 'ordering'
    Save-PrtgSecret -Name 'Api' -Secret (ConvertTo-SecureString 'x' -AsPlainText -Force) -Path $path
    $acl = Get-Acl (Join-Path $path 'Api.clixml')
    $acl.AreAccessRulesProtected | Should -BeTrue
    ($acl.Access | Where-Object { $_.IsInherited }) | Should -BeNullOrEmpty
  }

  It 'round-trips using the default ProgramData path (no -Path)' {
    $file = Join-Path $env:ProgramData 'PrtgSensorKit\Secrets\DefPd.clixml'
    try {
      Save-PrtgSecret -Name 'DefPd' -Secret (ConvertTo-SecureString 'defpd' -AsPlainText -Force)
      Get-PrtgSecret -Name 'DefPd' -AsPlainText | Should -Be 'defpd'
    } finally {
      Remove-Item $file -Force -ErrorAction SilentlyContinue
    }
  }
}

Describe 'Get-PrtgSecret -AsPlainText with a non-secret payload' {
  It 'throws instead of silently returning the object' {
    $path = Join-Path $TestDrive 'foreign'
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    'just a plain string' | Export-Clixml -LiteralPath (Join-Path $path 'Odd.clixml')
    { Get-PrtgSecret -Name 'Odd' -Path $path -AllowUnprotected -AsPlainText -ErrorAction Stop } |
      Should -Throw -ExpectedMessage '*not a PSCredential or SecureString*'
  }

  It 'still returns the raw object without -AsPlainText' {
    $path = Join-Path $TestDrive 'foreign2'
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    'just a plain string' | Export-Clixml -LiteralPath (Join-Path $path 'Odd.clixml')
    Get-PrtgSecret -Name 'Odd' -Path $path -AllowUnprotected | Should -Be 'just a plain string'
  }
}

Describe 'Save/Get-PrtgSecret partial-write handling' {
  It 'reports a truncated secret file clearly instead of crashing' {
    # Import-Clixml returns $null for a truncated file WITHOUT throwing, so this is not covered
    # by the decrypt-failure catch.
    $path = Join-Path $TestDrive 'trunc'
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    # Well-formed but object-less: this is what a save that died after the header leaves behind.
    Set-Content -LiteralPath (Join-Path $path 'Cut.clixml') -Value '<Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04"></Objs>'
    { Get-PrtgSecret -Name 'Cut' -Path $path -AllowUnprotected -ErrorAction Stop } |
      Should -Throw -ExpectedMessage '*empty or truncated*'
  }

  It 'reports it the same way with -AsPlainText' {
    $path = Join-Path $TestDrive 'trunc2'
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    # Well-formed but object-less: this is what a save that died after the header leaves behind.
    Set-Content -LiteralPath (Join-Path $path 'Cut.clixml') -Value '<Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04"></Objs>'
    { Get-PrtgSecret -Name 'Cut' -Path $path -AllowUnprotected -AsPlainText -ErrorAction Stop } |
      Should -Throw -ExpectedMessage '*empty or truncated*'
  }

  It 'cleans up its temp file when the save fails' {
    # Only the rename is mocked, so Export-Clixml really writes the temp file and the cleanup
    # runs against one that exists on disk.
    $path = Join-Path $TestDrive 'failsave'
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    Mock -CommandName Move-Item -ModuleName PrtgSensorKit -MockWith { throw 'simulated rename failure' }
    { Save-PrtgSecret -Name 'Doomed' -Secret (ConvertTo-SecureString 'x' -AsPlainText -Force) `
        -Path $path -AllowUnprotected -WarningAction SilentlyContinue -ErrorAction Stop } | Should -Throw
    @(Get-ChildItem -LiteralPath $path -Filter '*.tmp') | Should -BeNullOrEmpty
    Test-Path -LiteralPath (Join-Path $path 'Doomed.clixml') | Should -BeFalse
  }

  It 'keeps the existing secret when the swap itself fails' {
    # Regression: Move-Item -Force replaces by DELETING the destination and then moving, so a
    # failure in between left neither copy on disk. The swap must leave the old secret intact.
    $path = Join-Path $TestDrive 'swapfail'
    Save-PrtgSecret -Name 'Keep' -Secret (ConvertTo-SecureString 'original' -AsPlainText -Force) `
      -Path $path -AllowUnprotected -WarningAction SilentlyContinue
    Mock -CommandName Move-PrtgFileAtomic -ModuleName PrtgSensorKit -MockWith { throw 'simulated swap failure' }
    { Save-PrtgSecret -Name 'Keep' -Secret (ConvertTo-SecureString 'replacement' -AsPlainText -Force) `
        -Path $path -AllowUnprotected -WarningAction SilentlyContinue -ErrorAction Stop } | Should -Throw
    Test-Path -LiteralPath (Join-Path $path 'Keep.clixml') | Should -BeTrue
    Get-PrtgSecret -Name 'Keep' -Path $path -AllowUnprotected -AsPlainText | Should -Be 'original'
  }

  It 'keeps the existing secret when a rotation fails part-way' {
    # Regression: Export-Clixml truncates before it writes, so writing straight to the target
    # destroyed the old value when the write then threw.
    $path = Join-Path $TestDrive 'rotate'
    Save-PrtgSecret -Name 'Rot' -Secret (ConvertTo-SecureString 'original' -AsPlainText -Force) `
      -Path $path -AllowUnprotected -WarningAction SilentlyContinue
    Mock -CommandName Export-Clixml -ModuleName PrtgSensorKit -MockWith { throw 'simulated write failure' }
    { Save-PrtgSecret -Name 'Rot' -Secret (ConvertTo-SecureString 'replacement' -AsPlainText -Force) `
        -Path $path -AllowUnprotected -WarningAction SilentlyContinue -ErrorAction Stop } | Should -Throw
    Get-PrtgSecret -Name 'Rot' -Path $path -AllowUnprotected -AsPlainText | Should -Be 'original'
  }

  It 'leaves no temp files behind on a successful save' {
    $path = Join-Path $TestDrive 'notemp'
    Save-PrtgSecret -Name 'Clean' -Secret (ConvertTo-SecureString 'x' -AsPlainText -Force) `
      -Path $path -AllowUnprotected -WarningAction SilentlyContinue
    @(Get-ChildItem -LiteralPath $path -Filter '*.tmp') | Should -BeNullOrEmpty
    @(Get-ChildItem -LiteralPath $path).Name | Should -Be 'Clean.clixml'
  }

  It 'sweeps a stale temp file left by an earlier interrupted save' {
    # A killed process (a PRTG sensor timeout, power loss) strands the temp file; nothing else
    # in the module prunes it, so the next save of the same name has to.
    # These names are the LEGACY generation, '<Name>.<guid>.tmp', written before this cmdlet
    # shared the atomic writer. They hold real encrypted payload, so they must still be swept.
    $path = Join-Path $TestDrive 'stale'
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    $stale = Join-Path $path 'Stale.deadbeef.tmp'
    $other = Join-Path $path 'Other.deadbeef.tmp'
    # Same name, longer extension: a Windows provider filter of '*.tmp' can match this one via
    # its 8.3 short name, and the store folder is allowed to hold unrelated files.
    $lookalike = Join-Path $path 'Stale.deadbeef.tmpbackup'
    Set-Content -LiteralPath $stale -Value 'leftover'
    Set-Content -LiteralPath $other -Value 'not mine'
    Set-Content -LiteralPath $lookalike -Value 'not a temp file'
    foreach ($f in $stale, $other, $lookalike) {
      (Get-Item -LiteralPath $f).LastWriteTimeUtc = [DateTime]::UtcNow.AddHours(-2)
    }
    Save-PrtgSecret -Name 'Stale' -Secret (ConvertTo-SecureString 'x' -AsPlainText -Force) `
      -Path $path -AllowUnprotected -WarningAction SilentlyContinue
    Test-Path -LiteralPath $stale | Should -BeFalse
    # Only this secret's own leftovers: another name's temp file is none of its business.
    Test-Path -LiteralPath $other | Should -BeTrue
    Test-Path -LiteralPath $lookalike | Should -BeTrue
  }

  It 'leaves a fresh temp file alone (a concurrent save of the same secret)' {
    # The secret store has no lock, so a second sensor instance can be part-way through its own
    # save of the same name. Deleting its temp file would break that save - and on Windows make
    # Export-Clixml recreate the file WITHOUT the ACL that save had already applied.
    $path = Join-Path $TestDrive 'concurrent'
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    $inFlight = Join-Path $path 'Busy.abc123.tmp'
    Set-Content -LiteralPath $inFlight -Value 'another instance is writing this'
    Save-PrtgSecret -Name 'Busy' -Secret (ConvertTo-SecureString 'x' -AsPlainText -Force) `
      -Path $path -AllowUnprotected -WarningAction SilentlyContinue
    Test-Path -LiteralPath $inFlight | Should -BeTrue
  }

  It 'names the secret and the account when the target cannot be replaced' {
    # The store folder is shared but each file is locked to its saver, so the rename is where a
    # cross-account name collision surfaces. A raw access-denied naming the GUID temp file does
    # not tell the operator which secret failed or which account it is running as.
    $path = Join-Path $TestDrive 'locked'
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    Mock -CommandName Move-Item -ModuleName PrtgSensorKit -MockWith {
      throw [System.UnauthorizedAccessException]::new('Access to the path is denied.')
    }
    $err = { Save-PrtgSecret -Name 'Owned' -Secret (ConvertTo-SecureString 'x' -AsPlainText -Force) `
        -Path $path -AllowUnprotected -WarningAction SilentlyContinue -ErrorAction Stop } |
      Should -Throw -ExpectedMessage "*Failed to replace secret 'Owned'*" -PassThru
    $err.Exception.Message | Should -BeLike '*belongs to another account*'
    @(Get-ChildItem -LiteralPath $path -Filter '*.tmp') | Should -BeNullOrEmpty
  }

  It 'reports a corrupt (malformed XML) secret as corruption, not an account mismatch' {
    # Unclosed XML makes Import-Clixml throw XmlException; blaming DPAPI would send the operator
    # to chase permissions for a problem no re-permissioning can fix.
    $path = Join-Path $TestDrive 'corrupt'
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $path 'Bad.clixml') -Value '<Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04">'
    $err = { Get-PrtgSecret -Name 'Bad' -Path $path -AllowUnprotected -ErrorAction Stop } |
      Should -Throw -ExpectedMessage '*not well-formed XML*' -PassThru
    $err.Exception.Message | Should -Not -BeLike '*same Windows account and machine*'
  }

  It 'still reports a non-XML read failure as an account mismatch' {
    # Well-formed XML whose SecureString payload is unreadable throws FormatException, NOT
    # XmlException, so it must fall through to the DPAPI wording. Asserting the message matters:
    # an unknown ELEMENT would also be an XmlException and would silently test the wrong branch.
    $path = Join-Path $TestDrive 'notsecret'
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $path 'Odd.clixml') -Value '<Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04"><SS>NOT-HEX-ZZZZ</SS></Objs>'
    { Get-PrtgSecret -Name 'Odd' -Path $path -AllowUnprotected -ErrorAction Stop } |
      Should -Throw -ExpectedMessage '*same Windows account and machine*'
  }
}

Describe 'Save-PrtgSecret through the shared atomic writer' {
  It 'sweeps a stale temp file from the current naming generation' {
    # The shared writer derives the temp name from the full leaf, so this secret's temps are now
    # '<Name>.clixml.<guid>.tmp'. The legacy generation is covered by the sweep test above.
    $path = Join-Path $TestDrive 'stalecurrent'
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    $stale = Join-Path $path 'Current.clixml.deadbeef.tmp'
    $other = Join-Path $path 'Other.clixml.deadbeef.tmp'
    Set-Content -LiteralPath $stale -Value 'leftover'
    Set-Content -LiteralPath $other -Value 'not mine'
    foreach ($f in $stale, $other) {
      (Get-Item -LiteralPath $f).LastWriteTimeUtc = [DateTime]::UtcNow.AddHours(-2)
    }

    Save-PrtgSecret -Name 'Current' -Secret (ConvertTo-SecureString 'x' -AsPlainText -Force) `
      -Path $path -AllowUnprotected -WarningAction SilentlyContinue

    Test-Path -LiteralPath $stale | Should -BeFalse
    Test-Path -LiteralPath $other | Should -BeTrue
  }

  It 'reads back a SecureString written at the previous serialization depth' {
    # Before this cmdlet shared the writer it exported at Export-Clixml's implicit depth of 2
    # rather than the writer's 5. Secrets already on disk must keep reading back.
    $path = Join-Path $TestDrive 'depthsecure'
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    (ConvertTo-SecureString 'legacy-token' -AsPlainText -Force) |
      Export-Clixml -LiteralPath (Join-Path $path 'OldSecure.clixml')

    Get-PrtgSecret -Name 'OldSecure' -Path $path -AllowUnprotected -AsPlainText |
      Should -Be 'legacy-token'
  }

  It 'reads back a PSCredential written at the previous serialization depth' {
    $path = Join-Path $TestDrive 'depthcred'
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    $cred = [System.Management.Automation.PSCredential]::new(
      'olduser', (ConvertTo-SecureString 'legacy-pass' -AsPlainText -Force))
    $cred | Export-Clixml -LiteralPath (Join-Path $path 'OldCred.clixml')

    $got = Get-PrtgSecret -Name 'OldCred' -Path $path -AllowUnprotected
    $got.UserName | Should -Be 'olduser'
    $got.GetNetworkCredential().Password | Should -Be 'legacy-pass'
  }

  It 'explains the collision when the destination is genuinely held open' -Tag 'Windows' -Skip:(-not $onWindows) {
    # The mocked collision test above proves the wording; this one proves the dispatch. The swap
    # now happens inside the shared writer, whose own cleanup catch runs first, so this arm sees
    # a REAL [System.IO.File]::Replace failure only after a rethrow - and Windows PowerShell 5.1
    # is documented to misdispatch a multi-type catch. Nothing is mocked here on purpose.
    $path = Join-Path $TestDrive 'heldopen'
    Save-PrtgSecret -Name 'Held' -Secret (ConvertTo-SecureString 'original' -AsPlainText -Force) `
      -Path $path -WarningAction SilentlyContinue
    $dest = Join-Path $path 'Held.clixml'

    $handle = [System.IO.FileStream]::new(
      $dest,
      [System.IO.FileMode]::Open,
      [System.IO.FileAccess]::ReadWrite,
      [System.IO.FileShare]::None)
    try {
      $err = { Save-PrtgSecret -Name 'Held' -Secret (ConvertTo-SecureString 'replacement' -AsPlainText -Force) `
            -Path $path -WarningAction SilentlyContinue -ErrorAction Stop } |
        Should -Throw -ExpectedMessage "*Failed to replace secret 'Held'*" -PassThru
      $err.Exception.Message | Should -BeLike '*belongs to another account*'
      # The point of the wrapper: the operator must not be shown the GUID temp file instead.
      $err.Exception.Message | Should -Not -BeLike '*.tmp*'
    } finally {
      $handle.Dispose()
    }

    @(Get-ChildItem -LiteralPath $path -Filter '*.tmp') | Should -BeNullOrEmpty
    Get-PrtgSecret -Name 'Held' -Path $path -AsPlainText | Should -Be 'original'
  }
}

Describe 'Secret store folder resolution through the public cmdlets' {
  It 'reading a missing secret does not create the store folder' {
    $path = Join-Path $TestDrive "neverread-$(Get-Random)"
    { Get-PrtgSecret -Name 'Nope' -Path $path -AllowUnprotected -ErrorAction Stop } |
      Should -Throw -ExpectedMessage "*not found*"
    Test-Path -LiteralPath $path | Should -BeFalse
  }

  It 'lands a relative -Path under the PowerShell location on a first save and a re-save' {
    # The resolver deliberately leaves a relative path alone; every consumer below it goes
    # through the PowerShell provider, which resolves against the current LOCATION rather than
    # the process working directory.
    $base = Join-Path $TestDrive "relsecret-$(Get-Random)"
    [void] (New-Item -ItemType Directory -Path $base -Force)
    Push-Location $base
    try {
      Save-PrtgSecret -Name 'Rel' -Secret (ConvertTo-SecureString 'first' -AsPlainText -Force) `
        -Path 'store' -AllowUnprotected -WarningAction SilentlyContinue
      Test-Path -LiteralPath (Join-Path $base 'store/Rel.clixml') | Should -BeTrue
      Get-PrtgSecret -Name 'Rel' -Path 'store' -AllowUnprotected -AsPlainText | Should -Be 'first'

      Save-PrtgSecret -Name 'Rel' -Secret (ConvertTo-SecureString 'second' -AsPlainText -Force) `
        -Path 'store' -AllowUnprotected -WarningAction SilentlyContinue
      Get-PrtgSecret -Name 'Rel' -Path 'store' -AllowUnprotected -AsPlainText | Should -Be 'second'
      @(Get-ChildItem -LiteralPath (Join-Path $base 'store') -Filter '*.tmp') | Should -BeNullOrEmpty
    } finally {
      Pop-Location
    }
  }
}
