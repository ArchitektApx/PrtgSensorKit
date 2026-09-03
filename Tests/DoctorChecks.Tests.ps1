# Pins the exact wording of every message the thirteen script checks can emit, one Describe per
# check. The four environment checks have no check function; Doctor.Tests.ps1 covers those.
. $PSScriptRoot/_TestHelpers.ps1

BeforeAll {
  . $PSScriptRoot/_TestHelpers.ps1
  Import-ModuleUnderTest

  # The check functions are private, so they are reached through InModuleScope. Every call site
  # wraps the result in @(): under Windows PowerShell 5.1 a bare object has no .Count.
  function Invoke-Check([string]$CheckId, [string]$Content) {
    $file = Join-Path $TestDrive "check-$(Get-Random).ps1"
    Set-Content -LiteralPath $file -Value $Content
    InModuleScope PrtgSensorKit -Parameters @{ CheckId = $CheckId; Path = $file } {
      $context = Get-PrtgDoctorAst -ScriptPath $Path
      @(& "Test-PrtgDoctor$CheckId" -Parsed $context)
    }
  }

  # PSK0011 reads raw bytes, so its fixtures are written as bytes: this test file itself
  # stays ASCII, and the encoding under test is not at the mercy of Set-Content's default.
  function Invoke-CheckOnBytes([string]$CheckId, [byte[]]$Bytes) {
    $file = Join-Path $TestDrive "check-$(Get-Random).ps1"
    [System.IO.File]::WriteAllBytes($file, $Bytes)
    InModuleScope PrtgSensorKit -Parameters @{ CheckId = $CheckId; Path = $file } {
      $context = Get-PrtgDoctorAst -ScriptPath $Path
      @(& "Test-PrtgDoctor$CheckId" -Parsed $context)
    }
  }

  function Assert-Finding($Finding, [string]$CheckId, [string]$Severity, [string]$Message) {
    $Finding.CheckId | Should -Be $CheckId
    $Finding.Severity | Should -Be $Severity
    $Finding.Message | Should -Be $Message
  }
}

Describe 'PSK0001 the script must parse' {
  It 'passes on a script that parses' {
    $findings = @(Invoke-Check 'PSK0001' 'Import-Module PrtgSensorKit')
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0001' 'Pass' 'Script parses without syntax errors.'
  }

  It 'reports one Error per parse error, prefixed with the parser message' {
    # The parser's own wording differs between hosts, so the assertion pins the whole
    # message against the parse error this fixture produced rather than a literal.
    $file = Join-Path $TestDrive "check-$(Get-Random).ps1"
    Set-Content -LiteralPath $file -Value 'if ('
    InModuleScope PrtgSensorKit -Parameters @{ Path = $file } {
      $context = Get-PrtgDoctorAst -ScriptPath $Path
      $findings = @(Test-PrtgDoctorPSK0001 -Parsed $context)
      $context.ParseErrors.Count | Should -BeGreaterThan 0
      $findings.Count | Should -Be $context.ParseErrors.Count
      $findings[0].CheckId | Should -Be 'PSK0001'
      $findings[0].Severity | Should -Be 'Error'
      $findings[0].Message | Should -Be "Syntax error: $($context.ParseErrors[0].Message)"
      $findings[0].Recommendation | Should -Be 'Fix the syntax error; PRTG would report this sensor as failed on every scan.'
    }
  }
}

Describe 'PSK0011 source encoding' {
  It 'passes on an all-ASCII script' {
    $findings = @(Invoke-CheckOnBytes 'PSK0011' ([System.Text.Encoding]::ASCII.GetBytes("Get-Date`n")))
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0011' 'Pass' 'Script encoding is safe for Windows PowerShell 5.1 (all-ASCII or BOM present).'
  }

  It 'warns on a BOM-less script holding non-ASCII bytes' {
    # $x = '<U+00E4>' as UTF-8 without a BOM.
    $bytes = [byte[]]@(0x24, 0x78, 0x20, 0x3D, 0x20, 0x27, 0xC3, 0xA4, 0x27, 0x0A)
    $findings = @(Invoke-CheckOnBytes 'PSK0011' $bytes)
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0011' 'Warning' 'The script contains non-ASCII characters but has no BOM. Windows PowerShell 5.1 reads BOM-less files as ANSI, so string literals with umlauts, accents, or symbols are silently misread under PRTG even though the script looks correct in pwsh.'
    $findings[0].Recommendation | Should -Be 'Save the file as UTF-8 with BOM.'
  }
}

Describe 'PSK0002 import before first kit command' {
  It 'reports Info when the script uses no kit commands' {
    $findings = @(Invoke-Check 'PSK0002' 'Get-Date')
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0002' 'Info' 'No PrtgSensorKit commands found in the script.'
    $findings[0].Recommendation | Should -Be 'Nothing to check; is this really a PrtgSensorKit sensor script?'
  }

  It 'warns when no kit import is present at all' {
    $findings = @(Invoke-Check 'PSK0002' "Set-PrtgMessage 'ok'")
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0002' 'Warning' "No 'Import-Module PrtgSensorKit' found. Module autoloading may cover this, but an explicit import is more predictable under PRTG."
    $findings[0].Recommendation | Should -Be "Add 'Import-Module PrtgSensorKit' at the top of the script."
  }

  It 'warns when a kit command runs before the import' {
    $findings = @(Invoke-Check 'PSK0002' @'
Set-PrtgMessage 'ok'
Import-Module PrtgSensorKit
'@)
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0002' 'Warning' "'Set-PrtgMessage' is used before 'Import-Module PrtgSensorKit'."
    $findings[0].Recommendation | Should -Be 'Move the import above the first PrtgSensorKit command.'
  }

  It 'passes when the import comes first' {
    $findings = @(Invoke-Check 'PSK0002' @'
Import-Module PrtgSensorKit
Set-PrtgMessage 'ok'
'@)
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0002' 'Pass' 'PrtgSensorKit is imported before it is used.'
  }
}

Describe 'PSK0003 Restart-* inside the sensor block' {
  It 'reports one Error per Restart-* call inside the block' {
    $findings = @(Invoke-Check 'PSK0003' @'
Invoke-PrtgSensor {
  Restart-InPwsh
}
'@)
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0003' 'Error' "'Restart-InPwsh' is called inside the Invoke-PrtgSensor block. The relaunched child process output would be discarded by the output guard."
    $findings[0].Recommendation | Should -Be 'Move the Restart-* call to the top of the script, before Invoke-PrtgSensor.'
  }

  It 'passes when no Restart-* call is inside the block' {
    $findings = @(Invoke-Check 'PSK0003' @'
Restart-InPwsh
Invoke-PrtgSensor { }
'@)
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0003' 'Pass' 'No Restart-* call inside the sensor block.'
  }
}

Describe 'PSK0004 Restart-* placement' {
  It 'passes with the no-helpers wording when no Restart-* call exists' {
    $findings = @(Invoke-Check 'PSK0004' 'Invoke-PrtgSensor { }')
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0004' 'Pass' 'No Restart-* helpers used.'
  }

  It 'passes with the positioned-correctly wording when a Restart-* call is placed right' {
    $findings = @(Invoke-Check 'PSK0004' @'
Restart-InPwsh
Invoke-PrtgSensor { }
'@)
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0004' 'Pass' 'Restart-* calls are positioned correctly.'
  }

  It 'reports an Error when Restart-* runs after Invoke-PrtgSensor' {
    $findings = @(Invoke-Check 'PSK0004' @'
Invoke-PrtgSensor { }
Restart-InPwsh
'@)
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0004' 'Error' "'Restart-InPwsh' is called after Invoke-PrtgSensor; the sensor has already emitted its response by then."
    $findings[0].Recommendation | Should -Be 'Call Restart-* before Invoke-PrtgSensor.'
  }

  It 'reports an Error when another Import-Module runs before Restart-*' {
    $findings = @(Invoke-Check 'PSK0004' @'
Import-Module Az.Accounts
Restart-InPwsh
Invoke-PrtgSensor { }
'@)
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0004' 'Error' "'Import-Module' (other than PrtgSensorKit) runs before 'Restart-InPwsh' on line 2. The import happens in the wrong host and can fail before the relaunch."
    $findings[0].Recommendation | Should -Be 'Import dependency modules after the Restart-* call (only Import-Module PrtgSensorKit may come first).'
  }
}

Describe 'PSK0005 manual output inside the sensor block' {
  It 'reports one Error per manual output command inside the block' {
    $findings = @(Invoke-Check 'PSK0005' @'
Invoke-PrtgSensor {
  Write-PrtgOutput
}
'@)
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0005' 'Error' "'Write-PrtgOutput' inside the Invoke-PrtgSensor block is not supported; the wrapper owns the single response."
    $findings[0].Recommendation | Should -Be 'Remove the call. Use New-PrtgChannel | Add-PrtgChannel and Set-PrtgMessage inside the block, or drop Invoke-PrtgSensor and go fully low-level.'
  }

  It 'passes when the manual output command is outside the block' {
    $findings = @(Invoke-Check 'PSK0005' @'
Invoke-PrtgSensor { }
Write-PrtgOutput
'@)
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0005' 'Pass' 'No manual output commands inside the sensor block.'
  }
}

Describe 'PSK0006 Invoke-PrtgSensor present' {
  It 'reports Info when the script never calls Invoke-PrtgSensor' {
    $findings = @(Invoke-Check 'PSK0006' 'Get-Date')
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0006' 'Info' 'No Invoke-PrtgSensor call found; assuming low-level mode (manual Write-PrtgOutput / Write-PrtgError).'
    $findings[0].Recommendation | Should -Be 'If this is not intentional, wrap your sensor logic in Invoke-PrtgSensor { ... }.'
  }

  It 'passes when Invoke-PrtgSensor is used' {
    $findings = @(Invoke-Check 'PSK0006' 'Invoke-PrtgSensor { }')
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0006' 'Pass' 'Invoke-PrtgSensor is used.'
  }
}

Describe 'PSK0007 at most one Invoke-PrtgSensor call' {
  It 'reports an Error naming the count and the lines' {
    $findings = @(Invoke-Check 'PSK0007' @'
Invoke-PrtgSensor { }
Invoke-PrtgSensor { }
'@)
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0007' 'Error' 'Invoke-PrtgSensor is called 2 times (lines 1, 2); a sensor must emit exactly one response.'
    $findings[0].Recommendation | Should -Be 'Merge the logic into a single Invoke-PrtgSensor block.'
  }

  It 'passes on a single call' {
    $findings = @(Invoke-Check 'PSK0007' 'Invoke-PrtgSensor { }')
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0007' 'Pass' 'At most one Invoke-PrtgSensor call.'
  }
}

Describe 'PSK0008 statements after Invoke-PrtgSensor' {
  It 'warns once per trailing statement, quoting the statement' {
    $findings = @(Invoke-Check 'PSK0008' @'
Invoke-PrtgSensor { }
'trailing'
'@)
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0008' 'Warning' "Statement after Invoke-PrtgSensor could write to the output stream and corrupt the emitted JSON: 'trailing'"
    $findings[0].Recommendation | Should -Be 'Remove it, assign its result to a variable, or pipe it to Out-Null. PRTG reads everything on stdout.'
  }

  It 'passes when nothing follows the sensor call' {
    $findings = @(Invoke-Check 'PSK0008' 'Invoke-PrtgSensor { }')
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0008' 'Pass' 'No output-producing statements after Invoke-PrtgSensor.'
  }
}

Describe 'PSK0009 modern TLS for web cmdlets' {
  It 'passes with the no-web-cmdlets wording when the script makes no web calls' {
    $findings = @(Invoke-Check 'PSK0009' 'Invoke-PrtgSensor { }')
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0009' 'Pass' 'No web cmdlets used; TLS setup not needed.'
  }

  It 'passes with the TLS-set-up wording when a literal modern protocol is assigned' {
    $findings = @(Invoke-Check 'PSK0009' @'
[System.Net.ServicePointManager]::SecurityProtocol = 'Tls12'
Invoke-RestMethod -Uri 'https://example.com'
'@)
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0009' 'Pass' 'Web cmdlets are used and TLS is set up.'
  }

  It 'reports Info when the TLS value cannot be resolved statically' {
    $findings = @(Invoke-Check 'PSK0009' @'
$protocol = $env:PROTOCOL
[System.Net.ServicePointManager]::SecurityProtocol = $protocol
Invoke-RestMethod -Uri 'https://example.com'
'@)
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0009' 'Info' 'Web cmdlets are used and a TLS setup was found, but its value could not be verified statically (splatted or variable-based).'
    $findings[0].Recommendation | Should -Be 'Prefer -ForceModernTls on the Invoke-PrtgSensor call, or assign SecurityProtocol from a literal Tls12/Tls13 value.'
  }

  It 'reports Info when there is no TLS setup at all' {
    $findings = @(Invoke-Check 'PSK0009' "Invoke-RestMethod -Uri 'https://example.com'")
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0009' 'Info' 'Web cmdlets are used without -ForceModernTls or a manual SecurityProtocol assignment. Windows PowerShell 5.1 defaults can lack TLS 1.2.'
    $findings[0].Recommendation | Should -Be 'Add -ForceModernTls to the Invoke-PrtgSensor call.'
  }
}

Describe 'PSK0010 -DryRun left in the script' {
  It 'warns when -DryRun is passed' {
    $findings = @(Invoke-Check 'PSK0010' 'Invoke-PrtgSensor -DryRun { }')
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0010' 'Warning' 'Invoke-PrtgSensor is called with -DryRun. Deployed to PRTG, this emits an object dump instead of the PRTG JSON.'
    $findings[0].Recommendation | Should -Be 'Remove -DryRun before deploying the sensor.'
  }

  It 'reports Info when the parameters are splatted from an unresolvable value' {
    $findings = @(Invoke-Check 'PSK0010' @'
$splat = Get-SensorOptions
Invoke-PrtgSensor @splat { }
'@)
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0010' 'Info' 'Invoke-PrtgSensor parameters are splatted from a value that could not be resolved statically; unable to verify -DryRun is not left in.'
    $findings[0].Recommendation | Should -Be 'Build the splat hashtable as a literal in the script, or pass -DryRun directly, so the Doctor can check it.'
  }

  It 'passes when no -DryRun is left' {
    $findings = @(Invoke-Check 'PSK0010' 'Invoke-PrtgSensor { }')
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0010' 'Pass' 'No -DryRun left in the script.'
  }
}

Describe 'PSK0012 channel limits are a creation-time snapshot' {
  It 'reports Info when a Limit* parameter is used' {
    $findings = @(Invoke-Check 'PSK0012' "New-PrtgChannel -Channel 'A' -Value 1 -LimitMaxError 5")
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0012' 'Info' 'New-PrtgChannel is called with Limit* parameters. PRTG copies limit values into the channel settings ONLY when the sensor is first created; editing them in the script later has no effect on an existing sensor.'
    $findings[0].Recommendation | Should -Be 'To change limits on a deployed sensor, edit the channel settings in the PRTG UI or delete and recreate the sensor.'
  }

  It 'passes when no Limit* parameter is used' {
    $findings = @(Invoke-Check 'PSK0012' "New-PrtgChannel -Channel 'A' -Value 1")
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0012' 'Pass' 'No channel limit parameters used.'
  }
}

Describe 'PSK0013 DPAPI secrets are bound to the sensor account' {
  It 'reports Info when Get-PrtgSecret is used' {
    $findings = @(Invoke-Check 'PSK0013' "Get-PrtgSecret -Name 'token'")
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0013' 'Info' 'Get-PrtgSecret is used. DPAPI secrets only decrypt under the Windows account that saved them, and PRTG runs the sensor as the probe service account (usually Local System), not your console user.'
    $findings[0].Recommendation | Should -Be "Run Save-PrtgSecret under the same account the sensor runs as, and test the script under that account before deploying. See Docs/secrets.md ('Credentials and secrets') in the PrtgSensorKit repository."
  }

  It 'passes when Get-PrtgSecret is not used' {
    $findings = @(Invoke-Check 'PSK0013' 'Get-Date')
    $findings.Count | Should -Be 1
    Assert-Finding $findings[0] 'PSK0013' 'Pass' 'No Get-PrtgSecret usage; secret account binding not applicable.'
  }
}

Describe 'Check registration' {
  It 'runs, defines and documents the same set of checks' {
    # A check with tests but no call in the runner passes its own suite while never running
    # against a real script; one missing from the cmdlet's help ships as a wrong index.
    InModuleScope PrtgSensorKit {
      $nameForm = '^Test-PrtgDoctorPSK\d{4}$'

      $defined = @(Get-ChildItem -Path Function: |
        Where-Object { $_.Name -match $nameForm } |
        ForEach-Object { $_.Name } | Sort-Object)

      $runner = (Get-Command -Name Test-PrtgDoctorScript -CommandType Function).ScriptBlock.Ast
      $registered = @($runner.FindAll({
          $args[0] -is [System.Management.Automation.Language.CommandAst]
        }, $true) |
        ForEach-Object { $_.GetCommandName() } |
        Where-Object { $_ -match $nameForm } | Sort-Object)

      # The four environment identifiers have no per-check function; named here so the
      # documented list stays fully pinned rather than filtered.
      $expected = @($defined | ForEach-Object { $_ -replace '^Test-PrtgDoctor', '' }) +
        @('PSK0101', 'PSK0102', 'PSK0103', 'PSK0104') | Sort-Object

      # From the parsed help rather than from a run, matching how the rest of this file's
      # pins read declarations instead of observed behaviour.
      $helpText = ((Get-Help Invoke-PrtgSensorDoctor).Description | ForEach-Object { $_.Text }) -join "`n"
      $documented = @([regex]::Matches($helpText, 'PSK\d{4}') |
        ForEach-Object { $_.Value } | Sort-Object -Unique)

      $defined.Count | Should -Be 13
      $registered | Should -Be $defined

      # Set equality only. Registry order stays unpinned: the byte-reading check's second
      # position is deliberate, but a reorder is cosmetic where a missing check is not.
      $documented | Should -Be $expected
    }
  }
}
