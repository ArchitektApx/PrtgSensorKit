BeforeAll {
  . $PSScriptRoot/_TestHelpers.ps1
  Import-ModuleUnderTest
}

# Dot-sourced at top level as well as in BeforeAll: Pester evaluates -Skip: at DISCOVERY time,
# before any BeforeAll has run.
. $PSScriptRoot/_TestHelpers.ps1
$onWindows = Test-OnWindowsHost

Describe 'Save/Get-PrtgSecret (cross-platform)' {
  It 'round-trips a SecureString (AsPlainText matches)' {
    $path = New-TestStore 'secrets'
    $ss = ConvertTo-SecureString 'tok3n' -AsPlainText -Force
    Save-PrtgSecret -Name 'Api' -Secret $ss -Path $path -AllowUnprotected -WarningAction SilentlyContinue
    Get-PrtgSecret -Name 'Api' -Path $path -AllowUnprotected -AsPlainText | Should -Be 'tok3n'
  }

  It 'round-trips a PSCredential (user + password)' {
    $path = New-TestStore 'secrets'
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
    $path = New-TestStore 'empty' -NoCreate
    { Get-PrtgSecret -Name 'DoesNotExist' -Path $path -AllowUnprotected -ErrorAction Stop } |
      Should -Throw
  }

  It 'returns the password with -AsPlainText for a stored PSCredential' {
    $path = New-TestStore 'plain'
    $cred = [System.Management.Automation.PSCredential]::new(
      'u', (ConvertTo-SecureString 'pw-plain' -AsPlainText -Force))
    Save-PrtgSecret -Name 'Cred' -Credential $cred -Path $path -AllowUnprotected -WarningAction SilentlyContinue
    Get-PrtgSecret -Name 'Cred' -Path $path -AllowUnprotected -AsPlainText | Should -Be 'pw-plain'
  }

  It 'throws a clear error when the stored file cannot be read back' {
    $path = New-TestStore 'broken'
    Set-Content -LiteralPath (Join-Path $path 'Broke.clixml') -Value 'not valid clixml'
    { Get-PrtgSecret -Name 'Broke' -Path $path -AllowUnprotected -ErrorAction Stop } | Should -Throw
  }
}

Describe 'Save/Get-PrtgSecret off Windows guard' -Skip:$onWindows {
  It 'Save refuses without -AllowUnprotected off Windows' {
    $path = New-TestStore 's'
    { Save-PrtgSecret -Name 'X' -Secret (ConvertTo-SecureString 'x' -AsPlainText -Force) `
        -Path $path -ErrorAction Stop } | Should -Throw
  }

  It 'Get refuses without -AllowUnprotected off Windows' {
    $path = New-TestStore 's'
    { Get-PrtgSecret -Name 'X' -Path $path -ErrorAction Stop } | Should -Throw
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
    $path = New-TestStore 'wsecrets'
    Save-PrtgSecret -Name 'Api' -Secret (ConvertTo-SecureString 'PLAINTEXT-MARKER' -AsPlainText -Force) -Path $path
    (Get-Content -Raw (Join-Path $path 'Api.clixml')) | Should -Not -Match 'PLAINTEXT-MARKER'
  }

  It 'locks the file ACL (inheritance off, no Everyone/Users)' {
    $path = New-TestStore 'wsecrets2'
    Save-PrtgSecret -Name 'Api' -Secret (ConvertTo-SecureString 'x' -AsPlainText -Force) -Path $path
    $acl = Get-Acl (Join-Path $path 'Api.clixml')
    $acl.AreAccessRulesProtected | Should -BeTrue
    ($acl.Access.IdentityReference.Value -join ';') | Should -Not -Match 'Everyone|BUILTIN\\Users'
  }

  It 'grants exactly the saving account, Administrators, and SYSTEM on the file' {
    $path = New-TestStore 'aclexact'
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
    # The folder ACL stays untouched; only the file is locked down.
    $path = New-TestStore 'folderacl'
    Save-PrtgSecret -Name 'Api' -Secret (ConvertTo-SecureString 'x' -AsPlainText -Force) -Path $path
    (Get-Acl $path).AreAccessRulesProtected | Should -BeFalse
  }

  It 'keeps the file ACL when the same secret name is saved twice' {
    # A re-save swaps a new file in over the old one, so the ACL must come out unchanged.
    $path = New-TestStore 'resave'
    Save-PrtgSecret -Name 'Api' -Secret (ConvertTo-SecureString 'one' -AsPlainText -Force) -Path $path
    $first = (Get-Acl (Join-Path $path 'Api.clixml')).Sddl
    Save-PrtgSecret -Name 'Api' -Secret (ConvertTo-SecureString 'two' -AsPlainText -Force) -Path $path
    (Get-Acl (Join-Path $path 'Api.clixml')).Sddl | Should -Be $first
    (Get-Acl (Join-Path $path 'Api.clixml')).AreAccessRulesProtected | Should -BeTrue
    Get-PrtgSecret -Name 'Api' -Path $path -AsPlainText | Should -Be 'two'
  }

  It 're-locks the file after the swap, which inherits the REPLACED file ACL' {
    # [File]::Replace keeps the destination's ACL, not the temp file's, so a re-save over a file
    # whose ACL is wrong keeps the wrong one.
    $path = New-TestStore 'reacl'
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
    $path = New-TestStore 'twosecrets'
    Save-PrtgSecret -Name 'A' -Secret (ConvertTo-SecureString 'a' -AsPlainText -Force) -Path $path
    $firstSddl = (Get-Acl (Join-Path $path 'A.clixml')).Sddl
    Save-PrtgSecret -Name 'B' -Secret (ConvertTo-SecureString 'b' -AsPlainText -Force) -Path $path
    (Get-Acl (Join-Path $path 'A.clixml')).Sddl | Should -Be $firstSddl
    Get-PrtgSecret -Name 'A' -Path $path -AsPlainText | Should -Be 'a'
    Get-PrtgSecret -Name 'B' -Path $path -AsPlainText | Should -Be 'b'
  }

  It 'an explicit foreign ACE on the folder survives a save' {
    # BUILTIN\Users (S-1-5-32-545) stands in for a second sensor account.
    $path = New-TestStore 'foreignace'
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
    $path = New-TestStore 'ordering'
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
    $path = New-TestStore 'foreign'
    'just a plain string' | Export-Clixml -LiteralPath (Join-Path $path 'Odd.clixml')
    { Get-PrtgSecret -Name 'Odd' -Path $path -AllowUnprotected -AsPlainText -ErrorAction Stop } |
      Should -Throw -ExpectedMessage '*not a PSCredential or SecureString*'
  }

  It 'still returns the raw object without -AsPlainText' {
    $path = New-TestStore 'foreign2'
    'just a plain string' | Export-Clixml -LiteralPath (Join-Path $path 'Odd.clixml')
    Get-PrtgSecret -Name 'Odd' -Path $path -AllowUnprotected | Should -Be 'just a plain string'
  }
}

Describe 'Save/Get-PrtgSecret partial-write handling' {
  It 'reports a truncated secret file clearly instead of crashing' {
    # Import-Clixml returns $null for a truncated file WITHOUT throwing, so this is not covered
    # by the decrypt-failure catch.
    $path = New-TestStore 'trunc'
    # Well-formed but object-less: this is what a save that died after the header leaves behind.
    Set-Content -LiteralPath (Join-Path $path 'Cut.clixml') -Value '<Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04"></Objs>'
    { Get-PrtgSecret -Name 'Cut' -Path $path -AllowUnprotected -ErrorAction Stop } |
      Should -Throw -ExpectedMessage '*empty or truncated*'
  }

  It 'reports it the same way with -AsPlainText' {
    $path = New-TestStore 'trunc2'
    # Well-formed but object-less: this is what a save that died after the header leaves behind.
    Set-Content -LiteralPath (Join-Path $path 'Cut.clixml') -Value '<Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04"></Objs>'
    { Get-PrtgSecret -Name 'Cut' -Path $path -AllowUnprotected -AsPlainText -ErrorAction Stop } |
      Should -Throw -ExpectedMessage '*empty or truncated*'
  }

  It 'cleans up its temp file when the save fails' {
    # Only the rename is mocked, so Export-Clixml really writes the temp file and the cleanup
    # runs against one that exists on disk.
    $path = New-TestStore 'failsave'
    Mock -CommandName Move-Item -ModuleName PrtgSensorKit -MockWith { throw 'simulated rename failure' }
    { Save-PrtgSecret -Name 'Doomed' -Secret (ConvertTo-SecureString 'x' -AsPlainText -Force) `
        -Path $path -AllowUnprotected -WarningAction SilentlyContinue -ErrorAction Stop } | Should -Throw
    @(Get-ChildItem -LiteralPath $path -Filter '*.tmp') | Should -BeNullOrEmpty
    Test-Path -LiteralPath (Join-Path $path 'Doomed.clixml') | Should -BeFalse
  }

  It 'keeps the existing secret when the swap itself fails' {
    # A swap that fails half-way must leave the old secret on disk.
    $path = New-TestStore 'swapfail'
    Save-PrtgSecret -Name 'Keep' -Secret (ConvertTo-SecureString 'original' -AsPlainText -Force) `
      -Path $path -AllowUnprotected -WarningAction SilentlyContinue
    Mock -CommandName Move-PrtgFileAtomic -ModuleName PrtgSensorKit -MockWith { throw 'simulated swap failure' }
    { Save-PrtgSecret -Name 'Keep' -Secret (ConvertTo-SecureString 'replacement' -AsPlainText -Force) `
        -Path $path -AllowUnprotected -WarningAction SilentlyContinue -ErrorAction Stop } | Should -Throw
    Test-Path -LiteralPath (Join-Path $path 'Keep.clixml') | Should -BeTrue
    Get-PrtgSecret -Name 'Keep' -Path $path -AllowUnprotected -AsPlainText | Should -Be 'original'
  }

  It 'keeps the existing secret when a rotation fails part-way' {
    # Export-Clixml truncates before it writes, so a write straight to the target destroys the
    # old value when it throws.
    $path = New-TestStore 'rotate'
    Save-PrtgSecret -Name 'Rot' -Secret (ConvertTo-SecureString 'original' -AsPlainText -Force) `
      -Path $path -AllowUnprotected -WarningAction SilentlyContinue
    Mock -CommandName Export-Clixml -ModuleName PrtgSensorKit -MockWith { throw 'simulated write failure' }
    { Save-PrtgSecret -Name 'Rot' -Secret (ConvertTo-SecureString 'replacement' -AsPlainText -Force) `
        -Path $path -AllowUnprotected -WarningAction SilentlyContinue -ErrorAction Stop } | Should -Throw
    Get-PrtgSecret -Name 'Rot' -Path $path -AllowUnprotected -AsPlainText | Should -Be 'original'
  }

  It 'leaves no temp files behind on a successful save' {
    $path = New-TestStore 'notemp'
    Save-PrtgSecret -Name 'Clean' -Secret (ConvertTo-SecureString 'x' -AsPlainText -Force) `
      -Path $path -AllowUnprotected -WarningAction SilentlyContinue
    @(Get-ChildItem -LiteralPath $path -Filter '*.tmp') | Should -BeNullOrEmpty
    @(Get-ChildItem -LiteralPath $path).Name | Should -Be 'Clean.clixml'
  }

  It 'sweeps a stale temp file left by an earlier interrupted save' {
    # A killed process strands the temp file and nothing else prunes it, so the next save of the
    # same name has to. The legacy '<Name>.<guid>.tmp' names hold real payload and count too.
    $path = New-TestStore 'stale'
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
    # The store has no lock, so a second sensor can be part-way through its own save of the same
    # name. Deleting its temp file breaks that save and drops the ACL it had already applied.
    $path = New-TestStore 'concurrent'
    $inFlight = Join-Path $path 'Busy.abc123.tmp'
    Set-Content -LiteralPath $inFlight -Value 'another instance is writing this'
    Save-PrtgSecret -Name 'Busy' -Secret (ConvertTo-SecureString 'x' -AsPlainText -Force) `
      -Path $path -AllowUnprotected -WarningAction SilentlyContinue
    Test-Path -LiteralPath $inFlight | Should -BeTrue
  }

  It 'names the secret and the account when the target cannot be replaced' {
    # Each file is locked to its saver, so the rename is where a cross-account collision
    # surfaces. A raw access-denied on the GUID temp file names neither the secret nor the account.
    $path = New-TestStore 'locked'
    Save-PrtgSecret -Name 'Owned' -Secret (ConvertTo-SecureString 'original' -AsPlainText -Force) `
      -Path $path -AllowUnprotected -WarningAction SilentlyContinue
    Mock -CommandName Move-PrtgFileAtomic -ModuleName PrtgSensorKit -MockWith {
      throw [System.UnauthorizedAccessException]::new('Access to the path is denied.')
    }
    $err = { Save-PrtgSecret -Name 'Owned' -Secret (ConvertTo-SecureString 'x' -AsPlainText -Force) `
        -Path $path -AllowUnprotected -WarningAction SilentlyContinue -ErrorAction Stop } |
      Should -Throw -ExpectedMessage "*Failed to replace secret 'Owned'*" -PassThru
    $err.Exception.Message | Should -BeLike '*belongs to another account*'
    @(Get-ChildItem -LiteralPath $path -Filter '*.tmp') | Should -BeNullOrEmpty
  }

  It 'does not blame a collision for a failure that never reached the swap' {
    # A full disk while writing the temp file is not a name collision. Reporting one sends the
    # operator to delete a secret that is healthy, or one that does not exist yet.
    $path = New-TestStore 'nocollision'
    Mock -CommandName Export-Clixml -ModuleName PrtgSensorKit -MockWith {
      throw [System.IO.IOException]::new('There is not enough space on the disk.')
    }
    $err = { Save-PrtgSecret -Name 'Fresh' -Secret (ConvertTo-SecureString 'x' -AsPlainText -Force) `
        -Path $path -AllowUnprotected -WarningAction SilentlyContinue -ErrorAction Stop } |
      Should -Throw -PassThru

    $err.Exception.Message | Should -Not -BeLike '*belongs to another account*'
    $err.Exception.Message | Should -BeLike '*not enough space*'
    @(Get-ChildItem -LiteralPath $path -Filter '*.tmp') | Should -BeNullOrEmpty
  }

  It 'reports a corrupt (malformed XML) secret as corruption, not an account mismatch' {
    # Unclosed XML makes Import-Clixml throw XmlException; blaming DPAPI would send the operator
    # to chase permissions for a problem no re-permissioning can fix.
    $path = New-TestStore 'corrupt'
    Set-Content -LiteralPath (Join-Path $path 'Bad.clixml') -Value '<Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04">'
    $err = { Get-PrtgSecret -Name 'Bad' -Path $path -AllowUnprotected -ErrorAction Stop } |
      Should -Throw -ExpectedMessage '*not well-formed XML*' -PassThru
    $err.Exception.Message | Should -Not -BeLike '*same Windows account and machine*'
  }

  It 'still reports a non-XML read failure as an account mismatch' {
    # An unreadable SecureString payload in well-formed XML throws FormatException, not
    # XmlException; asserting the message keeps this off the XmlException branch.
    $path = New-TestStore 'notsecret'
    Set-Content -LiteralPath (Join-Path $path 'Odd.clixml') -Value '<Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04"><SS>NOT-HEX-ZZZZ</SS></Objs>'
    { Get-PrtgSecret -Name 'Odd' -Path $path -AllowUnprotected -ErrorAction Stop } |
      Should -Throw -ExpectedMessage '*same Windows account and machine*'
  }
}

Describe 'Save-PrtgSecret through the shared atomic writer' {
  It 'sweeps a stale temp file from the current naming generation' {
    # The shared writer derives the temp name from the full leaf, so this secret's temps are
    # named '<Name>.clixml.<guid>.tmp'.
    $path = New-TestStore 'stalecurrent'
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
    # Secrets serialized at depth 2 must still read back; the writer uses 5.
    $path = New-TestStore 'depthsecure'
    (ConvertTo-SecureString 'legacy-token' -AsPlainText -Force) |
      Export-Clixml -LiteralPath (Join-Path $path 'OldSecure.clixml')

    Get-PrtgSecret -Name 'OldSecure' -Path $path -AllowUnprotected -AsPlainText |
      Should -Be 'legacy-token'
  }

  It 'reads back a PSCredential written at the previous serialization depth' {
    $path = New-TestStore 'depthcred'
    $cred = [System.Management.Automation.PSCredential]::new(
      'olduser', (ConvertTo-SecureString 'legacy-pass' -AsPlainText -Force))
    $cred | Export-Clixml -LiteralPath (Join-Path $path 'OldCred.clixml')

    $got = Get-PrtgSecret -Name 'OldCred' -Path $path -AllowUnprotected
    $got.UserName | Should -Be 'olduser'
    $got.GetNetworkCredential().Password | Should -Be 'legacy-pass'
  }

  It 'explains the collision when the destination is genuinely held open' -Tag 'Windows' -Skip:(-not $onWindows) {
    # Nothing is mocked: the arm sees a real [System.IO.File]::Replace failure rethrown through
    # the writer's cleanup catch, where Windows PowerShell 5.1 misdispatches a multi-type catch.
    $path = New-TestStore 'heldopen'
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
    $path = New-TestStore 'neverread' -NoCreate
    { Get-PrtgSecret -Name 'Nope' -Path $path -AllowUnprotected -ErrorAction Stop } |
      Should -Throw -ExpectedMessage "*not found*"
    Test-Path -LiteralPath $path | Should -BeFalse
  }

  It 'lands a relative -Path under the PowerShell location on a first save and a re-save' {
    # The resolver leaves a relative path alone; the consumers below it go through the
    # PowerShell provider, which resolves against the current LOCATION, not the process cwd.
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
