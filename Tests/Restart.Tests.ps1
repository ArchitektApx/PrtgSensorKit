BeforeAll {
  . $PSScriptRoot/_TestHelpers.ps1
  Import-BuiltPrtgModule
}

# -Skip must resolve at DISCOVERY time and on Windows PowerShell 5.1 (where $IsWindows is undefined).
$is64      = [Environment]::Is64BitProcess
$isCore    = $PSVersionTable.PSEdition -eq 'Core'
$onWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows

Describe 'Restart-* no-op safety' {
  It 'Restart-As64BitPowershell is a no-op in a 64-bit process' -Skip:(-not $is64) {
    Restart-As64BitPowershell | Should -BeNullOrEmpty
  }

  It 'Restart-InPwsh is a no-op on PowerShell Core' -Skip:(-not $isCore) {
    Restart-InPwsh | Should -BeNullOrEmpty
  }
}

# Real relaunch spawns a child PowerShell and calls exit, so it cannot run in-process. Drive it
# through a probe script launched under a specific host and assert: the host switched, the exit
# code passed through, the caller's own arguments survived, and injected flags were not duplicated.
Describe 'Restart-* relaunch (Windows)' -Tag 'Windows' -Skip:(-not $onWindows) {
  BeforeAll {
    . $PSScriptRoot/_TestHelpers.ps1
    $manifest = Get-BuiltPrtgManifest
    $script:probe = Join-Path ([System.IO.Path]::GetTempPath()) ("prtg_probe_{0}.ps1" -f ([guid]::NewGuid().ToString('N')))
    # The probe echoes the relaunched process' facts: bitness/edition, the -Payload it received,
    # and its full command line (to prove args survived and injected flags were not duplicated).
    @"
param([string]`$Mode, [string]`$Payload)
Import-Module '$manifest' -Force
if (`$Mode -eq '64')   { Restart-As64BitPowershell }
if (`$Mode -eq 'pwsh') { Restart-InPwsh }
[Console]::Out.WriteLine("BITS=" + ([IntPtr]::Size * 8) + ";EDITION=" + `$PSVersionTable.PSEdition)
[Console]::Out.WriteLine("PAYLOAD=" + `$Payload)
[Console]::Out.WriteLine("ARGS=" + ([Environment]::GetCommandLineArgs() -join '|'))
exit 7
"@ | Set-Content -LiteralPath $script:probe -Encoding UTF8

    $script:ps32    = "$env:WINDIR\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
    $script:desktop = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
  }
  AfterAll {
    Remove-Item -LiteralPath $script:probe -Force -ErrorAction SilentlyContinue
  }

  Context '32-bit to 64-bit' -Skip:(-not (Test-Path "$env:WINDIR\SysWOW64\WindowsPowerShell\v1.0\powershell.exe")) {
    BeforeAll {
      $script:out  = & $script:ps32 -NoProfile -ExecutionPolicy Bypass -File $script:probe -Mode '64' -Payload 'keep-me-123' 2>&1
      $script:code = $LASTEXITCODE
      $script:text = $script:out -join "`n"
      $script:argsLine = ($script:out | Where-Object { $_ -match '^ARGS=' }) -join ''
    }

    It 'relaunches into a 64-bit process' { $script:text | Should -Match 'BITS=64' }
    It 'preserves the exit code' { $script:code | Should -Be 7 }
    It 'runs the target host exactly once (no double-run)' {
      (@($script:out | Where-Object { $_ -match 'BITS=' })).Count | Should -Be 1
    }
    It 'preserves the script arguments (-Payload) across the relaunch' {
      $script:text | Should -Match 'PAYLOAD=keep-me-123'
      $script:argsLine | Should -Match 'keep-me-123'
    }
    It 'does not duplicate injected flags' {
      ([regex]::Matches($script:argsLine, '(?i)-NoProfile')).Count | Should -Be 1
      ([regex]::Matches($script:argsLine, '(?i)-ExecutionPolicy')).Count | Should -Be 1
    }
  }

  Context 'Desktop to pwsh' -Skip:(-not [bool](Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue)) {
    BeforeAll {
      $script:out  = & $script:desktop -NoProfile -ExecutionPolicy Bypass -File $script:probe -Mode 'pwsh' -Payload 'keep-me-456' 2>&1
      $script:code = $LASTEXITCODE
      $script:text = $script:out -join "`n"
      $script:argsLine = ($script:out | Where-Object { $_ -match '^ARGS=' }) -join ''
    }

    It 'relaunches into PowerShell Core' { $script:text | Should -Match 'EDITION=Core' }
    It 'preserves the exit code' { $script:code | Should -Be 7 }
    It 'preserves the script arguments (-Payload) across the relaunch' {
      $script:text | Should -Match 'PAYLOAD=keep-me-456'
      $script:argsLine | Should -Match 'keep-me-456'
    }
    It 'does not duplicate injected flags' {
      ([regex]::Matches($script:argsLine, '(?i)-NoProfile')).Count | Should -Be 1
    }
  }

  # PRTG starts sensors via -Command (not -File), so verify a -Command-launched sensor still
  # relaunches correctly and preserves its exit code.
  Context '32-bit to 64-bit, sensor launched via -Command' -Skip:(-not (Test-Path "$env:WINDIR\SysWOW64\WindowsPowerShell\v1.0\powershell.exe")) {
    BeforeAll {
      $cmd = "& '$script:probe' -Mode '64' -Payload 'cmd-me-789'"
      $script:out  = & $script:ps32 -NoProfile -ExecutionPolicy Bypass -Command $cmd 2>&1
      $script:code = $LASTEXITCODE
      $script:text = $script:out -join "`n"
    }

    It 'relaunches into a 64-bit process' { $script:text | Should -Match 'BITS=64' }
    It 'preserves the script arguments (-Payload) across the relaunch' {
      $script:text | Should -Match 'PAYLOAD=cmd-me-789'
    }
    It 'runs the target host exactly once (no double-run)' {
      (@($script:out | Where-Object { $_ -match 'BITS=' })).Count | Should -Be 1
    }
    # No exit-code assertion here: a process launched via -Command "& 'script'" reports exit code 1
    # for any non-zero exit (a PowerShell quirk of -Command, independent of the relaunch). Exit-code
    # passthrough through the relaunch itself is covered by the -File context above.
  }
}
