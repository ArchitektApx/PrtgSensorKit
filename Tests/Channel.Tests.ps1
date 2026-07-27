BeforeAll {
  . $PSScriptRoot/_TestHelpers.ps1
  Import-BuiltPrtgModule
}

Describe 'New-PrtgChannel' {
  It 'builds a basic channel with defaults' {
    $c = New-PrtgChannel -Channel 'Total' -Value 42
    $c.Channel | Should -Be 'Total'
    $c.Value   | Should -Be 42
    $c.Unit    | Should -Be 'Count'
  }

  It 'emits ShowChart/ShowTable as 0/1, never true/false' {
    $c = New-PrtgChannel -Channel 'X' -Value 1 -ShowChart $false -ShowTable $true
    $c.ShowChart | Should -Be 0
    $c.ShowTable | Should -Be 1
  }

  It 'tags the object with PSTypeName PrtgSensorKit.Channel' {
    $c = New-PrtgChannel -Channel 'X' -Value 1
    $c.PSObject.TypeNames | Should -Contain 'PrtgSensorKit.Channel'
  }

  It 'does NOT expose PSTypeName as a data property (would leak into JSON)' {
    $c = New-PrtgChannel -Channel 'X' -Value 1
    $c.PSObject.Properties.Name | Should -Not -Contain 'PSTypeName'
  }

  It 'adds Float=1 and doubles the value for decimal input' {
    $c = New-PrtgChannel -Channel 'CPU' -Value 78.5 -Unit Percent
    $c.Float | Should -Be 1
    $c.Value | Should -Be 78.5
  }

  It 'accepts BytesDisk without throwing (dynamic-param collection bug regression)' {
    { New-PrtgChannel -Channel 'Disk' -Value 100 -Unit BytesDisk } | Should -Not -Throw
  }

  It 'accepts CustomUnit when Unit is Custom' {
    $c = New-PrtgChannel -Channel 'X' -Value 1 -Unit Custom -CustomUnit 'req/s'
    $c.Unit       | Should -Be 'Custom'
    $c.CustomUnit | Should -Be 'req/s'
  }

  It 'converts LimitMode/NotifyChanged to 0/1' {
    $c = New-PrtgChannel -Channel 'X' -Value 1 -LimitMode $true -NotifyChanged
    $c.LimitMode      | Should -Be 1
    $c.NotifyChanged  | Should -Be 1
  }

  It 'sanitizes LimitErrorMsg / LimitWarningMsg (strips #)' {
    $c = New-PrtgChannel -Channel 'X' -Value 1 -LimitMode $true `
      -LimitErrorMsg 'over #limit' -LimitWarningMsg 'near #limit'
    $c.LimitErrorMsg   | Should -Not -Match '#'
    $c.LimitWarningMsg | Should -Not -Match '#'
  }

  It 'rejects a non-numeric Value' {
    { New-PrtgChannel -Channel 'X' -Value 'nope' -ErrorAction Stop } | Should -Throw
  }

  It 'binds numeric limit parameters (min/max error/warning)' {
    $c = New-PrtgChannel -Channel 'X' -Value 50 -LimitMode $true `
      -LimitMaxError 90 -LimitMaxWarning 80 -LimitMinWarning 20 -LimitMinError 10
    $c.LimitMaxError   | Should -Be 90
    $c.LimitMaxWarning | Should -Be 80
    $c.LimitMinWarning | Should -Be 20
    $c.LimitMinError   | Should -Be 10
  }

  It 'accepts string-typed limits' {
    $c = New-PrtgChannel -Channel 'X' -Value 1 -LimitMode $true -LimitMaxError '90'
    $c.LimitMaxError | Should -Be '90'
  }

  It 'exposes SpeedSize/SpeedTime dynamic params for BytesBandwidth' {
    $c = New-PrtgChannel -Channel 'Net' -Value 100 -Unit BytesBandwidth -SpeedSize Mega -SpeedTime Second
    $c.SpeedSize | Should -Be 'Mega'
    $c.SpeedTime | Should -Be 'Second'
  }

  It 'exposes VolumeSize dynamic param for BytesDisk' {
    $c = New-PrtgChannel -Channel 'Disk' -Value 100 -Unit BytesDisk -VolumeSize Giga
    $c.VolumeSize | Should -Be 'Giga'
  }

  It 'binds the remaining optional parameters' {
    $c = New-PrtgChannel -Channel 'X' -Value 5 -Unit Count -Mode Difference -DecimalMode All `
      -Warning -ValueLookup 'prtg.standardlookups.boolean'
    $c.Mode        | Should -Be 'Difference'
    $c.DecimalMode | Should -Be 'All'
    $c.Warning     | Should -Be 1
    $c.ValueLookup | Should -Be 'prtg.standardlookups.boolean'
  }
}

Describe 'New-PrtgChannel numeric value types' {
  It 'accepts <name> and keeps the value intact' -TestCases @(
    @{ Name = 'byte';    Value = [byte]5 }
    @{ Name = 'sbyte';   Value = [sbyte]5 }
    @{ Name = 'int16';   Value = [int16]5 }
    @{ Name = 'uint16';  Value = [uint16]5 }
    @{ Name = 'int32';   Value = [int32]5 }
    @{ Name = 'uint32';  Value = [uint32]5 }
    @{ Name = 'int64';   Value = [int64]5 }
    @{ Name = 'uint64';  Value = [uint64]5 }
    @{ Name = 'single';  Value = [single]5 }
    @{ Name = 'double';  Value = [double]5 }
    @{ Name = 'decimal'; Value = [decimal]5 }
  ) {
    param($Name, $Value)
    $c = New-PrtgChannel -Channel 'X' -Value $Value
    $c.Value | Should -Be 5
  }

  It 'keeps unsigned and small integers as integers (no Float flag)' {
    foreach ($v in @([byte]5, [uint16]5, [uint32]5, [uint64]5, [int16]5)) {
      $c = New-PrtgChannel -Channel 'X' -Value $v
      $c.PSObject.Properties.Name | Should -Not -Contain 'Float'
    }
  }

  It 'survives the JSON round-trip for a uint64 above 2^53' {
    Clear-PrtgOutput
    New-PrtgChannel -Channel 'Big' -Value ([uint64]18446744073709551615) | Add-PrtgChannel
    Write-PrtgOutput | Should -Match '18446744073709551615'
  }

  It 'rejects <name> for -Value' -TestCases @(
    @{ Name = 'string';   Value = 'nope' }
    @{ Name = 'bool';     Value = $true }
    @{ Name = 'datetime'; Value = [datetime]'2026-01-01' }
  ) {
    param($Name, $Value)
    { New-PrtgChannel -Channel 'X' -Value $Value -ErrorAction Stop } | Should -Throw
  }

  It 'rejects $null for -Value' {
    { New-PrtgChannel -Channel 'X' -Value $null -ErrorAction Stop } | Should -Throw
  }

  It 'accepts the widened numeric set on the Limit parameters' {
    $c = New-PrtgChannel -Channel 'X' -Value 1 -LimitMode $true `
      -LimitMaxError ([uint64]90) -LimitMaxWarning ([byte]80) `
      -LimitMinWarning ([int16]20) -LimitMinError ([single]10)
    $c.LimitMaxError   | Should -Be 90
    $c.LimitMaxWarning | Should -Be 80
    $c.LimitMinWarning | Should -Be 20
    $c.LimitMinError   | Should -Be 10
  }

  It 'still accepts strings on the Limit parameters' {
    $c = New-PrtgChannel -Channel 'X' -Value 1 -LimitMode $true -LimitMinError '5'
    $c.LimitMinError | Should -Be '5'
  }

  It 'still rejects a non-numeric, non-string limit' {
    { New-PrtgChannel -Channel 'X' -Value 1 -LimitMaxError $true -ErrorAction Stop } | Should -Throw
  }
}

Describe 'New-PrtgChannel common parameters' {
  It 'does not emit common parameters as channel properties' {
    $c = New-PrtgChannel -Channel 'A' -Value 1 -Verbose -ErrorAction SilentlyContinue `
      -WarningAction SilentlyContinue -OutVariable ov 4>$null
    ($c.PSObject.Properties.Name | Sort-Object) -join ',' |
      Should -Be 'Channel,ShowChart,ShowTable,Unit,Value'
  }

  It 'still emits real optional parameters' {
    # -Warning is a real New-PrtgChannel parameter, not a common one.
    $c = New-PrtgChannel -Channel 'A' -Value 1 -Mode Difference -ValueLookup 'x' -Warning
    $c.Mode        | Should -Be 'Difference'
    $c.ValueLookup | Should -Be 'x'
    $c.Warning     | Should -Be 1
  }
}

Describe 'Add-PrtgChannel' {
  BeforeEach { Clear-PrtgOutput }

  It 'appends channels to module-scope output' {
    New-PrtgChannel -Channel 'A' -Value 1 | Add-PrtgChannel
    New-PrtgChannel -Channel 'B' -Value 2 | Add-PrtgChannel
    (Write-PrtgOutput | ConvertFrom-Json).prtg.result.Count | Should -Be 2
  }

  It 'throws past the 50-channel PRTG limit' {
    {
      1..51 | ForEach-Object { New-PrtgChannel -Channel "C$_" -Value $_ | Add-PrtgChannel }
    } | Should -Throw
  }

  It 'adds every channel from a single multi-item pipeline' {
    1..3 | ForEach-Object { New-PrtgChannel -Channel "C$_" -Value $_ } | Add-PrtgChannel
    (Write-PrtgOutput | ConvertFrom-Json).prtg.result.Count | Should -Be 3
  }
}
