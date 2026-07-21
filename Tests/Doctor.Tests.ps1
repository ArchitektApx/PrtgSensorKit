BeforeAll {
  . $PSScriptRoot/_TestHelpers.ps1
  Import-BuiltPrtgModule

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

  It 'auto-skips environment checks on non-Windows with an Info finding' -Skip:(($PSVersionTable.PSEdition -eq 'Desktop') -or [bool]$IsWindows) {
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
