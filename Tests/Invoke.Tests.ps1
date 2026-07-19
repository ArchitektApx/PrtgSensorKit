BeforeAll {
  . $PSScriptRoot/_TestHelpers.ps1
  Import-BuiltPrtgModule
}

Describe 'Invoke-PrtgSensor' {
  It 'emits one JSON result on success' {
    $out = Invoke-PrtgSensor {
      New-PrtgChannel -Channel 'A' -Value 1 | Add-PrtgChannel
      Set-PrtgMessage 'ok'
    }
    ($out | Measure-Object).Count | Should -Be 1
    $obj = $out | ConvertFrom-Json
    $obj.prtg.result.Count | Should -Be 1
    $obj.prtg.text | Should -Be 'ok'
  }

  It 'discards stray output so stdout stays a single clean JSON' {
    $out = Invoke-PrtgSensor {
      Write-Host 'noise'
      Write-Output 'garbage that would corrupt stdout'
      New-PrtgChannel -Channel 'A' -Value 1 | Add-PrtgChannel
    }
    ($out | Measure-Object).Count | Should -Be 1
    $out | Should -Not -Match 'garbage|noise'
    { $out | ConvertFrom-Json } | Should -Not -Throw
  }

  It 'emits a PRTG error response when the block throws' {
    $obj = (Invoke-PrtgSensor { throw 'kaboom' }) | ConvertFrom-Json
    $obj.prtg.error | Should -Be 1
    $obj.prtg.text  | Should -Match 'kaboom'
  }

  It 'sees variables from the calling scope (sensor params work)' {
    $threshold = 'value-from-outer-scope'
    $obj = (Invoke-PrtgSensor { Set-PrtgMessage $threshold }) | ConvertFrom-Json
    $obj.prtg.text | Should -Be 'value-from-outer-scope'
  }

  It 'starts from a clean state each run' {
    Invoke-PrtgSensor { 1..3 | ForEach-Object { New-PrtgChannel -Channel "C$_" -Value $_ | Add-PrtgChannel } } | Out-Null
    $obj = (Invoke-PrtgSensor { New-PrtgChannel -Channel 'Solo' -Value 1 | Add-PrtgChannel }) | ConvertFrom-Json
    $obj.prtg.result.Count | Should -Be 1
  }
}
