# Dot-sourced at top level as well as in BeforeAll: -Skip: is evaluated at DISCOVERY time.
. $PSScriptRoot/_TestHelpers.ps1
$onWindows = Test-OnWindowsHost

BeforeAll {
  . $PSScriptRoot/_TestHelpers.ps1
  Import-ModuleUnderTest

  # Writes a fixture sensor script and runs the Doctor on it, capturing findings only
  # (the host summary goes to the information stream and is not asserted here).
  function Invoke-DoctorOn([string]$Content, [switch]$WithEnvironment) {
    $file = Join-Path $TestDrive "fixture-$(Get-Random).ps1"
    Set-Content -LiteralPath $file -Value $Content
    if ($WithEnvironment) { @(Invoke-PrtgSensorDoctor -ScriptPath $file 6>$null) }
    else { @(Invoke-PrtgSensorDoctor -ScriptPath $file -SkipEnvironmentChecks 6>$null) }
  }

  function Get-Finding($Findings, [string]$CheckId) {
    @($Findings | Where-Object CheckId -eq $CheckId)
  }

  $script:GoodSensor = @'
Import-Module PrtgSensorKit
Invoke-PrtgSensor {
  New-PrtgChannel -Channel 'A' -Value 1 | Add-PrtgChannel
  Set-PrtgMessage 'ok'
}
'@
}

Describe 'Invoke-PrtgSensorDoctor basics' {
  It 'throws on a missing script path' {
    { Invoke-PrtgSensorDoctor -ScriptPath (Join-Path $TestDrive 'does-not-exist.ps1') } | Should -Throw
  }

  It 'returns finding objects with the documented shape' {
    $findings = Invoke-DoctorOn $script:GoodSensor
    $findings.Count | Should -BeGreaterThan 0
    $first = $findings[0]
    @($first.PSObject.Properties.Name) | Should -Be @('CheckId', 'Severity', 'Message', 'Line', 'Recommendation')
  }

  It 'reports all script checks as Pass for a clean sensor' {
    $findings = Invoke-DoctorOn $script:GoodSensor
    $bad = @($findings | Where-Object { $_.CheckId -like 'PSK00*' -and $_.Severity -in 'Warning', 'Error' })
    $bad | Should -BeNullOrEmpty
  }

  It 'skips environment checks with an Info finding when asked to' {
    $findings = Invoke-DoctorOn $script:GoodSensor
    (Get-Finding $findings 'PSK0100').Severity | Should -Be 'Info'
    @($findings | Where-Object CheckId -like 'PSK01??' | Where-Object CheckId -ne 'PSK0100') | Should -BeNullOrEmpty
  }

  It 'auto-skips environment checks on non-Windows with an Info finding' -Skip:$onWindows {
    $findings = Invoke-DoctorOn $script:GoodSensor -WithEnvironment
    (Get-Finding $findings 'PSK0100').Message | Should -Match 'not running on Windows'
  }
}

Describe 'Doctor script checks' {
  It 'PSK0001: flags syntax errors with line numbers and still runs on parse failure' {
    $findings = Invoke-DoctorOn "Invoke-PrtgSensor {`n  if (`$true {`n}"
    $f = Get-Finding $findings 'PSK0001'
    $f[0].Severity | Should -Be 'Error'
    $f[0].Line | Should -Not -BeNullOrEmpty
  }

  It 'PSK0001: passes for a parseable script' {
    $findings = Invoke-DoctorOn $script:GoodSensor
    (Get-Finding $findings 'PSK0001').Severity | Should -Be 'Pass'
  }

  It 'PSK0002: warns when Import-Module PrtgSensorKit is missing' {
    $findings = Invoke-DoctorOn @'
Invoke-PrtgSensor { Set-PrtgMessage 'ok' }
'@
    (Get-Finding $findings 'PSK0002').Severity | Should -Be 'Warning'
  }

  It 'PSK0002: warns when the kit is used before it is imported' {
    $findings = Invoke-DoctorOn @'
Invoke-PrtgSensor { Set-PrtgMessage 'ok' }
Import-Module PrtgSensorKit
'@
    $f = Get-Finding $findings 'PSK0002'
    $f.Severity | Should -Be 'Warning'
    $f.Message | Should -Match 'before'
  }

  It 'PSK0003: errors on Restart-* inside the sensor block' {
    $findings = Invoke-DoctorOn @'
Import-Module PrtgSensorKit
Invoke-PrtgSensor {
  Restart-InPwsh
  Set-PrtgMessage 'ok'
}
'@
    (Get-Finding $findings 'PSK0003').Severity | Should -Be 'Error'
  }

  It 'PSK0004: errors on Restart-* after Invoke-PrtgSensor' {
    $findings = Invoke-DoctorOn @'
Import-Module PrtgSensorKit
Invoke-PrtgSensor { Set-PrtgMessage 'ok' }
Restart-InPwsh
'@
    @(Get-Finding $findings 'PSK0004' | Where-Object Severity -eq 'Error') | Should -Not -BeNullOrEmpty
  }

  It 'PSK0004: errors when another module is imported before Restart-*' {
    $findings = Invoke-DoctorOn @'
Import-Module PrtgSensorKit
Import-Module SqlServer
Restart-As64BitPowershell
Invoke-PrtgSensor { Set-PrtgMessage 'ok' }
'@
    $f = @(Get-Finding $findings 'PSK0004' | Where-Object Severity -eq 'Error')
    $f | Should -Not -BeNullOrEmpty
    $f[0].Message | Should -Match 'Import-Module'
  }

  It 'PSK0004: passes for correctly placed Restart-* (PrtgSensorKit import exempt)' {
    $findings = Invoke-DoctorOn @'
Import-Module PrtgSensorKit
Restart-As64BitPowershell
Invoke-PrtgSensor {
  Import-Module SqlServer
  Set-PrtgMessage 'ok'
}
'@
    (Get-Finding $findings 'PSK0004').Severity | Should -Be 'Pass'
  }

  It 'PSK0005: errors on manual output commands inside the block' {
    $findings = Invoke-DoctorOn @'
Import-Module PrtgSensorKit
Invoke-PrtgSensor {
  New-PrtgChannel -Channel 'A' -Value 1 | Add-PrtgChannel
  Write-PrtgOutput
}
'@
    $f = Get-Finding $findings 'PSK0005'
    $f.Severity | Should -Be 'Error'
    $f.Message | Should -Match 'Write-PrtgOutput'
  }

  It 'PSK0006: informs when no Invoke-PrtgSensor is used (low-level mode)' {
    $findings = Invoke-DoctorOn @'
Import-Module PrtgSensorKit
Clear-PrtgOutput
New-PrtgChannel -Channel 'A' -Value 1 | Add-PrtgChannel
Write-PrtgOutput
'@
    (Get-Finding $findings 'PSK0006').Severity | Should -Be 'Info'
  }

  It 'PSK0007: errors on multiple Invoke-PrtgSensor calls' {
    $findings = Invoke-DoctorOn @'
Import-Module PrtgSensorKit
Invoke-PrtgSensor { Set-PrtgMessage 'one' }
Invoke-PrtgSensor { Set-PrtgMessage 'two' }
'@
    (Get-Finding $findings 'PSK0007').Severity | Should -Be 'Error'
  }

  It 'PSK0008: warns about output-producing statements after Invoke-PrtgSensor' {
    $findings = Invoke-DoctorOn @'
Import-Module PrtgSensorKit
Invoke-PrtgSensor { Set-PrtgMessage 'ok' }
Get-Date
'@
    $f = Get-Finding $findings 'PSK0008'
    $f.Severity | Should -Be 'Warning'
    $f.Message | Should -Match 'Get-Date'
  }

  It 'PSK0009: recommends -ForceModernTls for web cmdlets without TLS setup' {
    $findings = Invoke-DoctorOn @'
Import-Module PrtgSensorKit
Invoke-PrtgSensor {
  $data = Invoke-RestMethod -Uri 'https://example.com'
  New-PrtgChannel -Channel 'A' -Value $data.value | Add-PrtgChannel
}
'@
    $f = Get-Finding $findings 'PSK0009'
    $f.Severity | Should -Be 'Info'
    $f.Recommendation | Should -Match 'ForceModernTls'
  }

  It 'PSK0009: passes when -ForceModernTls is used' {
    $findings = Invoke-DoctorOn @'
Import-Module PrtgSensorKit
Invoke-PrtgSensor -ForceModernTls {
  $data = Invoke-RestMethod -Uri 'https://example.com'
  New-PrtgChannel -Channel 'A' -Value $data.value | Add-PrtgChannel
}
'@
    (Get-Finding $findings 'PSK0009').Severity | Should -Be 'Pass'
  }

  It 'PSK0009: passes when SecurityProtocol is set manually' {
    $findings = Invoke-DoctorOn @'
Import-Module PrtgSensorKit
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-PrtgSensor {
  $data = Invoke-RestMethod -Uri 'https://example.com'
  New-PrtgChannel -Channel 'A' -Value $data.value | Add-PrtgChannel
}
'@
    (Get-Finding $findings 'PSK0009').Severity | Should -Be 'Pass'
  }

  It 'PSK0009: does not accept -ForceModernTls:$false as TLS setup' {
    $findings = Invoke-DoctorOn @'
Import-Module PrtgSensorKit
Invoke-PrtgSensor -ForceModernTls:$false {
  $data = Invoke-RestMethod -Uri 'https://example.com'
  New-PrtgChannel -Channel 'A' -Value $data.value | Add-PrtgChannel
}
'@
    (Get-Finding $findings 'PSK0009').Severity | Should -Be 'Info'
  }

  It 'PSK0009: does not accept a mere SecurityProtocol-named variable as TLS setup' {
    $findings = Invoke-DoctorOn @'
Import-Module PrtgSensorKit
$SecurityProtocolBackup = 'nothing to do with TLS'
Invoke-PrtgSensor {
  $data = Invoke-RestMethod -Uri 'https://example.com'
  New-PrtgChannel -Channel 'A' -Value $data.value | Add-PrtgChannel
}
'@
    (Get-Finding $findings 'PSK0009').Severity | Should -Be 'Info'
  }

  It 'PSK0009: does not accept an SSL3-only SecurityProtocol assignment as TLS setup' {
    $findings = Invoke-DoctorOn @'
Import-Module PrtgSensorKit
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Ssl3
Invoke-PrtgSensor {
  $data = Invoke-RestMethod -Uri 'https://example.com'
  New-PrtgChannel -Channel 'A' -Value $data.value | Add-PrtgChannel
}
'@
    (Get-Finding $findings 'PSK0009').Severity | Should -Be 'Info'
  }

  It 'PSK0010: does not flag -DryRun:$false (dry run disabled)' {
    $findings = Invoke-DoctorOn @'
Import-Module PrtgSensorKit
Invoke-PrtgSensor -DryRun:$false { Set-PrtgMessage 'ok' }
'@
    (Get-Finding $findings 'PSK0010').Severity | Should -Be 'Pass'
  }

  It 'PSK0010: warns when -DryRun is left in the call' {
    $findings = Invoke-DoctorOn @'
Import-Module PrtgSensorKit
Invoke-PrtgSensor -DryRun { Set-PrtgMessage 'ok' }
'@
    $f = Get-Finding $findings 'PSK0010'
    $f.Severity | Should -Be 'Warning'
    $f.Recommendation | Should -Match 'Remove -DryRun'
  }
}

Describe 'Doctor environment checks (mocked probes)' {
  It 'PSK0101 passes/fails with the probe result' {
    InModuleScope PrtgSensorKit {
      Mock Invoke-PrtgDoctorModuleProbe { $true }
      Mock Get-PrtgDoctorHostPath { 'C:\fake\powershell.exe' }
      $f = @(Test-PrtgDoctorEnvironment) | Where-Object CheckId -eq 'PSK0101'
      $f.Severity | Should -Be 'Pass'

      Mock Invoke-PrtgDoctorModuleProbe { $false }
      $f = @(Test-PrtgDoctorEnvironment) | Where-Object CheckId -eq 'PSK0101'
      $f.Severity | Should -Be 'Error'
      $f.Recommendation | Should -Match 'Install-Module'
    }
  }

  It 'PSK0102 is checked only when Restart-As64BitPowershell is used' {
    InModuleScope PrtgSensorKit {
      Mock Invoke-PrtgDoctorModuleProbe { $false }
      Mock Get-PrtgDoctorHostPath { 'C:\fake\powershell.exe' }

      $f = @(Test-PrtgDoctorEnvironment) | Where-Object CheckId -eq 'PSK0102'
      $f.Severity | Should -Be 'Pass'   # not applicable

      $f = @(Test-PrtgDoctorEnvironment -UsesRestart64Bit $true) | Where-Object CheckId -eq 'PSK0102'
      $f.Severity | Should -Be 'Error'
    }
  }

  It 'PSK0103 errors when pwsh is missing, and when the module is missing in pwsh' {
    InModuleScope PrtgSensorKit {
      Mock Get-PrtgDoctorHostPath { 'C:\fake\powershell.exe' }
      Mock Invoke-PrtgDoctorModuleProbe { $true }
      Mock Get-Command { $null } -ParameterFilter { $Name -eq 'pwsh' }
      $f = @(Test-PrtgDoctorEnvironment -UsesRestartInPwsh $true) | Where-Object CheckId -eq 'PSK0103'
      $f.Severity | Should -Be 'Error'
      $f.Message | Should -Match 'not found'

      Mock Get-Command { [PSCustomObject]@{ Source = 'C:\fake\pwsh.exe' } } -ParameterFilter { $Name -eq 'pwsh' }
      Mock Invoke-PrtgDoctorModuleProbe { $false } -ParameterFilter { $Executable -eq 'C:\fake\pwsh.exe' }
      Mock Invoke-PrtgDoctorModuleProbe { $true } -ParameterFilter { $Executable -ne 'C:\fake\pwsh.exe' }
      $f = @(Test-PrtgDoctorEnvironment -UsesRestartInPwsh $true) | Where-Object CheckId -eq 'PSK0103'
      $f.Severity | Should -Be 'Error'
      $f.Message | Should -Match 'own module path'
    }
  }

  It 'PSK0104 warns about dependency modules missing in the target host' {
    InModuleScope PrtgSensorKit {
      Mock Get-PrtgDoctorHostPath { 'C:\fake\powershell.exe' }
      Mock Invoke-PrtgDoctorModuleProbe { $ModuleName -eq 'PrtgSensorKit' }
      $f = @(Test-PrtgDoctorEnvironment -StaticModuleNames @('SqlServer', 'PrtgSensorKit')) | Where-Object CheckId -eq 'PSK0104'
      $f.Severity | Should -Be 'Warning'
      $f.Message | Should -Match 'SqlServer'

      Mock Invoke-PrtgDoctorModuleProbe { $true }
      $f = @(Test-PrtgDoctorEnvironment -StaticModuleNames @('SqlServer')) | Where-Object CheckId -eq 'PSK0104'
      $f.Severity | Should -Be 'Pass'
    }
  }
}

Describe 'Doctor module probe input hardening' {
  It 'refuses module names outside the safe pattern without spawning a child process' {
    InModuleScope PrtgSensorKit {
      $sw = [System.Diagnostics.Stopwatch]::StartNew()
      $result = Invoke-PrtgDoctorModuleProbe -Executable 'no-such-executable' -ModuleName "Foo'; Write-Host pwned #"
      $sw.Stop()
      $result | Should -BeFalse
      # Validation must reject BEFORE any child-process attempt; a spawn try would be slow.
      $sw.Elapsed.TotalSeconds | Should -BeLessThan 1
    }
  }

  It 'still probes well-formed module names (catch path on bogus executable)' {
    InModuleScope PrtgSensorKit {
      Invoke-PrtgDoctorModuleProbe -Executable 'no-such-executable' -ModuleName 'Az.Accounts' | Should -BeFalse
    }
  }

  It 'injection-shaped Import-Module literals surface as unresolvable, not executed' {
    InModuleScope PrtgSensorKit {
      Mock Get-PrtgDoctorHostPath { 'C:\fake\powershell.exe' }
      Mock Invoke-PrtgDoctorModuleProbe { $ModuleName -eq 'PrtgSensorKit' }
      $f = @(Test-PrtgDoctorEnvironment -StaticModuleNames @("Foo'; Remove-Item x #")) | Where-Object CheckId -eq 'PSK0104'
      $f.Severity | Should -Be 'Warning'
    }
  }
}

Describe 'Doctor static import extraction' {
  It 'collects positional, -Name, array, path, and #Requires module names' {
    InModuleScope PrtgSensorKit {
      $file = Join-Path $TestDrive 'imports.ps1'
      Set-Content -LiteralPath $file -Value @'
#Requires -Modules Az.Accounts
Import-Module PrtgSensorKit
Import-Module SqlServer
Import-Module -Name Posh-SSH -Force
Import-Module 'C:\modules\MyTools\MyTools.psd1'
Import-Module ModA, ModB
'@
      $parsed = Get-PrtgDoctorAst -ScriptPath $file
      $names = @(Get-PrtgDoctorImportedModuleName -Parsed $parsed)
      $names | Should -Contain 'Az.Accounts'
      $names | Should -Contain 'SqlServer'
      $names | Should -Contain 'Posh-SSH'
      $names | Should -Contain 'MyTools'
      $names | Should -Contain 'ModA'
      $names | Should -Contain 'ModB'
    }
  }
}

Describe 'Doctor v1.2.0 script checks (PSK0011-PSK0013)' {
  BeforeAll {
    # PSK0011 needs byte-exact files; the shared fixture helper controls content, not encoding.
    function Invoke-DoctorOnBytes([string]$Content, [System.Text.Encoding]$Encoding) {
      $file = Join-Path $TestDrive "enc-$(Get-Random).ps1"
      [System.IO.File]::WriteAllText($file, $Content, $Encoding)
      @(Invoke-PrtgSensorDoctor -ScriptPath $file -SkipEnvironmentChecks 6>$null)
    }
    $script:NonAsciiSensor = "Import-Module PrtgSensorKit`nInvoke-PrtgSensor { Set-PrtgMessage 'gr$([char]0x00FC)n' }"
  }

  It 'PSK0011: warns on non-ASCII content without a BOM' {
    $findings = Invoke-DoctorOnBytes $script:NonAsciiSensor ([System.Text.UTF8Encoding]::new($false))
    $f = Get-Finding $findings 'PSK0011'
    $f.Severity | Should -Be 'Warning'
    $f.Line | Should -BeNullOrEmpty
    $f.Recommendation | Should -Match 'BOM'
  }

  It 'PSK0011: passes non-ASCII content with a UTF-8 BOM' {
    $findings = Invoke-DoctorOnBytes $script:NonAsciiSensor ([System.Text.UTF8Encoding]::new($true))
    (Get-Finding $findings 'PSK0011').Severity | Should -Be 'Pass'
  }

  It 'PSK0011: passes non-ASCII content with a UTF-16 LE BOM' {
    $findings = Invoke-DoctorOnBytes $script:NonAsciiSensor ([System.Text.Encoding]::Unicode)
    (Get-Finding $findings 'PSK0011').Severity | Should -Be 'Pass'
  }

  It 'PSK0011: passes non-ASCII content with a UTF-16 BE BOM' {
    $findings = Invoke-DoctorOnBytes $script:NonAsciiSensor ([System.Text.Encoding]::BigEndianUnicode)
    (Get-Finding $findings 'PSK0011').Severity | Should -Be 'Pass'
  }

  It 'PSK0011: passes non-ASCII content with a UTF-32 BE BOM' {
    $findings = Invoke-DoctorOnBytes $script:NonAsciiSensor ([System.Text.Encoding]::GetEncoding('utf-32BE'))
    (Get-Finding $findings 'PSK0011').Severity | Should -Be 'Pass'
  }

  It 'PSK0011: passes an all-ASCII file without a BOM' {
    $findings = Invoke-DoctorOn $script:GoodSensor
    (Get-Finding $findings 'PSK0011').Severity | Should -Be 'Pass'
  }

  It 'PSK0012: informs when New-PrtgChannel uses Limit* parameters, with the line' {
    $findings = Invoke-DoctorOn @'
Import-Module PrtgSensorKit
Invoke-PrtgSensor {
  New-PrtgChannel -Channel 'A' -Value 1 | Add-PrtgChannel
  New-PrtgChannel -Channel 'B' -Value 2 -LimitMaxError 10 -LimitMode $true | Add-PrtgChannel
}
'@
    $f = Get-Finding $findings 'PSK0012'
    $f.Severity | Should -Be 'Info'
    $f.Line | Should -Be 4
    $f.Message | Should -Match 'first created'
  }

  It 'PSK0012: passes without limit parameters' {
    $findings = Invoke-DoctorOn $script:GoodSensor
    (Get-Finding $findings 'PSK0012').Severity | Should -Be 'Pass'
  }

  It 'PSK0013: informs when Get-PrtgSecret is used, pointing at the account binding' {
    $findings = Invoke-DoctorOn @'
Import-Module PrtgSensorKit
Invoke-PrtgSensor {
  $token = Get-PrtgSecret -Name 'Api' -AsPlainText
  Set-PrtgMessage 'ok'
}
'@
    $f = Get-Finding $findings 'PSK0013'
    $f.Severity | Should -Be 'Info'
    $f.Line | Should -Be 3
    $f.Recommendation | Should -Match 'same account'
  }

  It 'PSK0013: passes without Get-PrtgSecret' {
    $findings = Invoke-DoctorOn $script:GoodSensor
    (Get-Finding $findings 'PSK0013').Severity | Should -Be 'Pass'
  }
}

Describe 'Doctor script check edge branches' {
  It 'PSK0002: informs when the script uses no kit commands at all' {
    $findings = Invoke-DoctorOn 'Get-Date'
    (Get-Finding $findings 'PSK0002').Severity | Should -Be 'Info'
  }

  It 'PSK0008: flags control flow after Invoke-PrtgSensor that can write to stdout' {
    $findings = Invoke-DoctorOn @'
Import-Module PrtgSensorKit
Invoke-PrtgSensor { Set-PrtgMessage 'ok' }
if ($true) { Get-Date }
'@
    (Get-Finding $findings 'PSK0008').Severity | Should -Be 'Warning'
  }

  It 'PSK0009: reports an unverifiable manual TLS value as Info' {
    $findings = Invoke-DoctorOn @'
Import-Module PrtgSensorKit
$proto = Get-ProtoFromSomewhere
[Net.ServicePointManager]::SecurityProtocol = $proto
Invoke-PrtgSensor { $x = Invoke-RestMethod -Uri 'https://example.com' }
'@
    $f = Get-Finding $findings 'PSK0009'
    $f.Severity | Should -Be 'Info'
    $f.Message | Should -Match 'could not be verified'
  }

  It 'PSK0010: resolves -DryRun from a literal splat hashtable' {
    $findings = Invoke-DoctorOn @'
Import-Module PrtgSensorKit
$params = @{ DryRun = $true }
Invoke-PrtgSensor @params { Set-PrtgMessage 'ok' }
'@
    (Get-Finding $findings 'PSK0010').Severity | Should -Be 'Warning'
  }

  It 'PSK0010: reports an unresolvable splat as Info' {
    $findings = Invoke-DoctorOn @'
Import-Module PrtgSensorKit
$params = Get-SensorParams
Invoke-PrtgSensor @params { Set-PrtgMessage 'ok' }
'@
    (Get-Finding $findings 'PSK0010').Severity | Should -Be 'Info'
  }
}

Describe 'Doctor argument resolution on shapes no other fixture produces' {

  It 'PSK0010: reads -DryRun out of a splat whose other key is not a plain string literal' {
    # The hashtable's first key is a variable, so the Doctor cannot read it as a name. That must
    # not stop it reading the keys it CAN read: -DryRun is still found and still flagged.
    $findings = Invoke-DoctorOn @'
Import-Module PrtgSensorKit
$key = 'RetryCount'
$params = @{ $key = 2; DryRun = $true }
Invoke-PrtgSensor @params { Set-PrtgMessage 'ok' }
'@
    $f = Get-Finding $findings 'PSK0010'
    $f.Severity | Should -Be 'Warning'
    $f.Message  | Should -Match '-DryRun'
    $f.Line     | Should -Be 4
  }

  It 'PSK0009: refuses to pass when SecurityProtocol comes from a variable it cannot resolve' {
    # $ProtocolFromCaller is never assigned in the script, so its value is unknowable statically.
    # Reporting a Pass here would tell an operator that TLS is set up when it may not be.
    $findings = Invoke-DoctorOn @'
Import-Module PrtgSensorKit
[Net.ServicePointManager]::SecurityProtocol = $ProtocolFromCaller
Invoke-PrtgSensor { $x = Invoke-RestMethod -Uri 'https://example.com' }
'@
    $f = Get-Finding $findings 'PSK0009'
    $f.Severity | Should -Not -Be 'Pass'
    $f.Severity | Should -Be 'Info'
    $f.Message  | Should -Match 'could not be verified statically'
    $f.Line     | Should -Be 3
  }

  It 'PSK0009: passes when SecurityProtocol comes from a variable it CAN resolve to a modern value' {
    $findings = Invoke-DoctorOn @'
Import-Module PrtgSensorKit
$proto = [Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::SecurityProtocol = $proto
Invoke-PrtgSensor { $x = Invoke-RestMethod -Uri 'https://example.com' }
'@
    $f = Get-Finding $findings 'PSK0009'
    $f.Severity | Should -Be 'Pass'
    $f.Message  | Should -Match 'TLS is set up'
  }

  It 'PSK0002: does not read another parameter''s value as the imported module name' {
    # -Prefix carries the string 'PrtgSensorKit'. Taking it for the module name would report the
    # kit as imported when the script imports SqlServer and never imports the kit at all.
    $findings = Invoke-DoctorOn @'
Import-Module SqlServer -Prefix 'PrtgSensorKit'
Invoke-PrtgSensor { Set-PrtgMessage 'ok' }
'@
    $f = Get-Finding $findings 'PSK0002'
    $f.Severity | Should -Be 'Warning'
    $f.Message  | Should -Match "No 'Import-Module PrtgSensorKit' found"
    $f.Line     | Should -Be 2
  }
}

Describe 'Doctor environment check dispatch' -Tag 'Windows' {
  It 'runs the real environment checks on Windows and reports PSK0101' -Skip:(-not $onWindows) {
    # Machine state (installed modules, pwsh presence) decides the severities, so this
    # asserts only that the dispatch ran and the probe checks reported back.
    $findings = Invoke-DoctorOn $script:GoodSensor -WithEnvironment
    @(Get-Finding $findings 'PSK0101').Count | Should -Be 1
    @(Get-Finding $findings 'PSK0100') | Should -BeNullOrEmpty
  }
}

# The PSK0101-0104 tests above mock Invoke-PrtgDoctorModuleProbe and Get-PrtgDoctorHostPath, so
# the real bodies never run. These exercise them for real against a machine that actually has the
# module installed for all users, which is the state a PRTG probe is in.
$moduleInstalledForReal = $onWindows -and [bool](
  Get-Module -ListAvailable -Name PrtgSensorKit -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -notlike '*Dist*' })

Describe 'Get-PrtgDoctorHostPath (unmocked, Windows)' -Tag 'Windows' -Skip:(-not $onWindows) {
  It 'resolves a real powershell.exe for both bitnesses' {
    InModuleScope PrtgSensorKit {
      foreach ($bitness in 'x86', 'x64') {
        $path = Get-PrtgDoctorHostPath -Bitness $bitness
        $path | Should -BeLike '*WindowsPowerShell\v1.0\powershell.exe'
        # Sysnative is visible only to a 32-bit process, so a 64-bit run cannot Test-Path it.
        if ($path -notlike '*Sysnative*') {
          Test-Path -LiteralPath $path | Should -BeTrue -Because "$bitness host should exist at $path"
        }
      }
    }
  }

  It 'escapes WOW64 redirection correctly for the current process bitness' {
    InModuleScope PrtgSensorKit {
      $x64 = Get-PrtgDoctorHostPath -Bitness 'x64'
      $x86 = Get-PrtgDoctorHostPath -Bitness 'x86'
      $x64 | Should -Not -Be $x86
      if ([System.Environment]::Is64BitProcess) {
        $x64 | Should -BeLike '*System32*'
        $x86 | Should -BeLike '*SysWOW64*'
      } else {
        $x64 | Should -BeLike '*Sysnative*'
        $x86 | Should -BeLike '*System32*'
      }
    }
  }
}

Describe 'Doctor environment probes against a real installed module' -Tag 'Windows' -Skip:(-not $moduleInstalledForReal) {
  # Skipped unless PrtgSensorKit resolves from a real module path (not Dist), i.e. the probe
  # machine. In CI the module is built but never installed, so these do not run there.
  It 'PSK0102 passes when the module really is resolvable in 64-bit Windows PowerShell' {
    $f = InModuleScope PrtgSensorKit { @(Test-PrtgDoctorEnvironment -UsesRestart64Bit $true) } |
      Where-Object CheckId -eq 'PSK0102'
    $f.Severity | Should -Be 'Pass'
    $f.Message  | Should -BeLike '*resolvable in 64-bit Windows PowerShell*'
  }

  It 'PSK0103 passes when pwsh is present and the module resolves there' {
    $f = InModuleScope PrtgSensorKit { @(Test-PrtgDoctorEnvironment -UsesRestartInPwsh $true) } |
      Where-Object CheckId -eq 'PSK0103'
    $f.Severity | Should -Be 'Pass'
    $f.Message  | Should -BeLike '*pwsh is available*'
  }

  It 'PSK0101 passes for the current host' {
    $f = InModuleScope PrtgSensorKit { @(Test-PrtgDoctorEnvironment) } | Where-Object CheckId -eq 'PSK0101'
    $f.Severity | Should -Be 'Pass'
  }
}
