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
