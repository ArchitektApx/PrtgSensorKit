BeforeAll {
  . $PSScriptRoot/_TestHelpers.ps1
  Import-BuiltPrtgModule
}

# Windows detection for -Skip must work at DISCOVERY time and on Windows PowerShell 5.1,
# where $IsWindows is undefined. PSEdition 'Desktop' implies Windows.
$onWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows

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
