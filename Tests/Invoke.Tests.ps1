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

Describe 'Invoke-PrtgSensor -DryRun' {
  It 'returns an inspectable object, not a JSON string' {
    $out = Invoke-PrtgSensor -DryRun {
      New-PrtgChannel -Channel 'A' -Value 1 | Add-PrtgChannel
      Set-PrtgMessage 'ok'
    }
    $out -is [string] | Should -BeFalse
    $out.prtg.text | Should -Be 'ok'
    @($out.prtg.result).Count | Should -Be 1
    $out.prtg.result[0].channel | Should -Be 'A'
  }

  It 'matches the JSON shape of a normal run exactly' {
    $block = {
      New-PrtgChannel -Channel 'A' -Value 1 -Unit Percent | Add-PrtgChannel
      New-PrtgChannel -Channel 'B' -Value 2.5 -Float | Add-PrtgChannel
      Set-PrtgMessage 'shape'
    }
    $normalJson = Invoke-PrtgSensor $block
    $dry = Invoke-PrtgSensor -DryRun $block
    ($dry | ConvertTo-Json -Depth 10) | Should -Be $normalJson
  }

  It 'rethrows the original error instead of emitting a PRTG error response' {
    { Invoke-PrtgSensor -DryRun { throw 'kaboom' } } | Should -Throw '*kaboom*'
  }

  It 'returns a detached copy - mutating it does not affect the next run' {
    $dry = Invoke-PrtgSensor -DryRun { Set-PrtgMessage 'original' }
    $dry.prtg.text = 'mutated'
    $obj = (Invoke-PrtgSensor { Set-PrtgMessage 'fresh' }) | ConvertFrom-Json
    $obj.prtg.text | Should -Be 'fresh'
  }

  It 'emits an empty result array when no channels were added, like a real run' {
    $dry = Invoke-PrtgSensor -DryRun { Set-PrtgMessage 'no channels' }
    @($dry.prtg.result).Count | Should -Be 0
  }
}

Describe 'Invoke-PrtgSensor -RetryCount' {
  It 'retries a throwing block and decorates the message on eventual success' {
    $state = @{ Attempts = 0 }
    $obj = (Invoke-PrtgSensor -RetryCount 2 {
      $state.Attempts++
      if ($state.Attempts -lt 2) { throw 'transient' }
      New-PrtgChannel -Channel 'A' -Value 1 | Add-PrtgChannel
      Set-PrtgMessage 'ok'
    }) | ConvertFrom-Json
    $state.Attempts | Should -Be 2
    $obj.prtg.text | Should -Be 'ok (1/2 retries attempted)'
    $obj.prtg.result.Count | Should -Be 1
  }

  It 'emits the retry-prefixed error text when all attempts fail' {
    $state = @{ Attempts = 0 }
    $obj = (Invoke-PrtgSensor -RetryCount 2 {
      $state.Attempts++
      throw 'kaboom'
    }) | ConvertFrom-Json
    $state.Attempts | Should -Be 3
    $obj.prtg.error | Should -Be 1
    $obj.prtg.text | Should -Match '^unsuccessful after 2 retries: '
    $obj.prtg.text | Should -Match 'kaboom'
  }

  It 'clears partial output between attempts' {
    $state = @{ Attempts = 0 }
    $obj = (Invoke-PrtgSensor -RetryCount 1 {
      $state.Attempts++
      if ($state.Attempts -eq 1) {
        New-PrtgChannel -Channel 'Stale' -Value 1 | Add-PrtgChannel
        throw 'first attempt fails after adding a channel'
      }
      New-PrtgChannel -Channel 'Fresh' -Value 2 | Add-PrtgChannel
    }) | ConvertFrom-Json
    $obj.prtg.result.Count | Should -Be 1
    $obj.prtg.result[0].channel | Should -Be 'Fresh'
  }

  It 'uses the bare suffix when the block sets no message' {
    $state = @{ Attempts = 0 }
    $obj = (Invoke-PrtgSensor -RetryCount 1 {
      $state.Attempts++
      if ($state.Attempts -lt 2) { throw 'transient' }
      New-PrtgChannel -Channel 'A' -Value 1 | Add-PrtgChannel
    }) | ConvertFrom-Json
    $obj.prtg.text | Should -Be '(1/1 retries attempted)'
  }

  It 'does not decorate the message when the first attempt succeeds' {
    $obj = (Invoke-PrtgSensor -RetryCount 3 { Set-PrtgMessage 'clean' }) | ConvertFrom-Json
    $obj.prtg.text | Should -Be 'clean'
  }

  It 'honors -RetryDelaySeconds between attempts' {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Invoke-PrtgSensor -RetryCount 1 -RetryDelaySeconds 1 { throw 'always' } | Out-Null
    $sw.Stop()
    $sw.Elapsed.TotalSeconds | Should -BeGreaterThan 0.9
  }

  It 'rethrows after exhausted retries under -DryRun' {
    $state = @{ Attempts = 0 }
    { Invoke-PrtgSensor -DryRun -RetryCount 1 { $state.Attempts++; throw 'always' } } | Should -Throw '*always*'
    $state.Attempts | Should -Be 2
  }

  It 'shows the retry suffix in the -DryRun object' {
    $state = @{ Attempts = 0 }
    $dry = Invoke-PrtgSensor -DryRun -RetryCount 1 {
      $state.Attempts++
      if ($state.Attempts -lt 2) { throw 'transient' }
      Set-PrtgMessage 'ok'
    }
    $dry.prtg.text | Should -Be 'ok (1/1 retries attempted)'
  }
}

Describe 'Invoke-PrtgSensor -ForceModernTls' {
  BeforeAll {
    $script:InitialTls = [System.Net.ServicePointManager]::SecurityProtocol
  }
  AfterEach {
    [System.Net.ServicePointManager]::SecurityProtocol = $script:InitialTls
  }

  It 'sets SecurityProtocol to include TLS 1.2' {
    Invoke-PrtgSensor -ForceModernTls { Set-PrtgMessage 'tls' } | Out-Null
    $tls12 = [System.Net.SecurityProtocolType]::Tls12
    ([System.Net.ServicePointManager]::SecurityProtocol -band $tls12) | Should -Be $tls12
  }

  It 'leaves SecurityProtocol untouched without the switch' {
    $before = [System.Net.ServicePointManager]::SecurityProtocol
    Invoke-PrtgSensor { Set-PrtgMessage 'no tls' } | Out-Null
    [System.Net.ServicePointManager]::SecurityProtocol | Should -Be $before
  }
}
