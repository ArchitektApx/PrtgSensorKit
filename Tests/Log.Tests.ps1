BeforeAll {
  . $PSScriptRoot/_TestHelpers.ps1
  Import-BuiltPrtgModule

  # One log file per PROCESS is the production contract; tests share a process, so the
  # cached run file and session settings are reset before every test.
  function Reset-PrtgLogState {
    InModuleScope PrtgSensorKit {
      $script:PrtgLogFile = $null
      $script:PrtgLogDirectory = $null
      $script:PrtgLogMaxLogs = 30
    }
  }
}

Describe 'Write-PrtgLog run files' {
  BeforeEach {
    Reset-PrtgLogState
    $dir = Join-Path $TestDrive "logs-$(Get-Random)"
  }

  It 'creates one run file named <scriptname>_<timestamp>_<PID>.log' {
    [void] (Invoke-PrtgSensor -EnableLogging -LogPath $dir { Set-PrtgMessage 'ok' })
    $files = @(Get-ChildItem -LiteralPath $dir -Filter '*.log')
    $files.Count | Should -Be 1
    $files[0].Name | Should -Match "^Log\.Tests_\d{8}-\d{6}_$([regex]::Escape("$PID"))\.log$"
  }

  It 'appends every call in the invocation to the same file' {
    [void] (Invoke-PrtgSensor -EnableLogging -LogPath $dir {
      Write-PrtgLog 'first'
      Write-PrtgLog 'second'
      Set-PrtgMessage 'ok'
    })
    $files = @(Get-ChildItem -LiteralPath $dir -Filter '*.log')
    $files.Count | Should -Be 1
    $lines = @(Get-Content -LiteralPath $files[0].FullName)
    # sensor start + first + second + sensor ok
    $lines.Count | Should -Be 4
  }

  It 'formats lines as ISO local timestamp with offset, level tag, message' {
    InModuleScope PrtgSensorKit -Parameters @{ dir = $dir } { param($dir) $script:PrtgLogDirectory = $dir }
    Write-PrtgLog -Level Warning 'something odd'
    $file = @(Get-ChildItem -LiteralPath $dir -Filter '*.log')[0].FullName
    @(Get-Content -LiteralPath $file)[0] |
      Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+[+-]\d{2}:\d{2} \[WARNING\] something odd$'
  }

  It 'preserves non-ASCII message content as UTF-8' {
    InModuleScope PrtgSensorKit -Parameters @{ dir = $dir } { param($dir) $script:PrtgLogDirectory = $dir }
    $umlaut = [char]0x00E4
    Write-PrtgLog "gr${umlaut}n"
    $file = @(Get-ChildItem -LiteralPath $dir -Filter '*.log')[0].FullName
    (Get-Content -LiteralPath $file -Encoding UTF8 -Raw) | Should -BeLike "*gr${umlaut}n*"
  }

  It 'writes to the default directory when no session directory is set' {
    Write-PrtgLog 'standalone entry'
    $file = InModuleScope PrtgSensorKit { $script:PrtgLogFile }
    $file | Should -Not -BeNullOrEmpty
    $file | Should -BeLike (Join-Path (Join-Path '*PrtgSensorKit' 'Logs') '*')
    Get-Content -LiteralPath $file -Raw | Should -BeLike '*standalone entry*'
    Remove-Item -LiteralPath $file -Force
  }

  It 'never throws, even when the target directory cannot be created' {
    $blocker = Join-Path $TestDrive "blocker-$(Get-Random)"
    Set-Content -LiteralPath $blocker -Value 'a file where the log directory should go'
    InModuleScope PrtgSensorKit -Parameters @{ dir = $blocker } { param($dir) $script:PrtgLogDirectory = $dir }
    { Write-PrtgLog 'dropped' } | Should -Not -Throw
  }

  It 'writes nothing to the output stream' {
    InModuleScope PrtgSensorKit -Parameters @{ dir = $dir } { param($dir) $script:PrtgLogDirectory = $dir }
    $output = Write-PrtgLog 'quiet'
    $output | Should -BeNullOrEmpty
  }
}

Describe 'Write-PrtgLog pruning' {
  BeforeEach {
    Reset-PrtgLogState
    $dir = Join-Path $TestDrive "logs-$(Get-Random)"
    [void] (New-Item -ItemType Directory -Path $dir)
    foreach ($i in 1..5) {
      $stale = Join-Path $dir "old_$i.log"
      Set-Content -LiteralPath $stale -Value 'old run'
      (Get-Item -LiteralPath $stale).LastWriteTime = (Get-Date).AddHours(-$i)
    }
  }

  It 'keeps only the newest MaxLogs files, counting the new run file' {
    [void] (Invoke-PrtgSensor -EnableLogging -LogPath $dir -MaxLogs 3 { Set-PrtgMessage 'ok' })
    $files = @(Get-ChildItem -LiteralPath $dir -Filter '*.log' | Sort-Object LastWriteTime -Descending)
    $files.Count | Should -Be 3
    $files[0].Name | Should -BeLike 'Log.Tests_*'
  }

  It 'keeps everything with -MaxLogs 0' {
    [void] (Invoke-PrtgSensor -EnableLogging -LogPath $dir -MaxLogs 0 { Set-PrtgMessage 'ok' })
    @(Get-ChildItem -LiteralPath $dir -Filter '*.log').Count | Should -Be 6
  }
}

Describe 'Invoke-PrtgSensor -EnableLogging lifecycle' {
  BeforeEach {
    Reset-PrtgLogState
    $dir = Join-Path $TestDrive "logs-$(Get-Random)"
  }

  It 'logs start and a success summary with channel count, message, and duration' {
    [void] (Invoke-PrtgSensor -EnableLogging -LogPath $dir {
      New-PrtgChannel -Channel 'A' -Value 1 | Add-PrtgChannel
      Set-PrtgMessage 'all good'
    })
    $content = Get-Content -LiteralPath @(Get-ChildItem -LiteralPath $dir -Filter '*.log')[0].FullName -Raw
    $content | Should -BeLike '*sensor start (attempt 1/1)*'
    $content | Should -BeLike "*sensor ok: 1 channels, message 'all good',*ms*"
  }

  It 'logs full error details on final failure' {
    [void] (Invoke-PrtgSensor -EnableLogging -LogPath $dir { throw 'kaboom' })
    $content = Get-Content -LiteralPath @(Get-ChildItem -LiteralPath $dir -Filter '*.log')[0].FullName -Raw
    $content | Should -BeLike '*[ERROR]*sensor failed:*'
    $content | Should -BeLike '*message: kaboom*'
    $content | Should -BeLike '*stack trace:*'
  }

  It 'logs each retry with the one-line error' {
    [void] (Invoke-PrtgSensor -EnableLogging -LogPath $dir -RetryCount 1 { throw 'flaky' })
    $content = Get-Content -LiteralPath @(Get-ChildItem -LiteralPath $dir -Filter '*.log')[0].FullName -Raw
    $content | Should -BeLike '*attempt 1 failed: flaky; retrying in 0s*'
    $content | Should -BeLike '*sensor failed:*'
  }

  It 'logs the same lifecycle for a dry run' {
    $result = Invoke-PrtgSensor -DryRun -EnableLogging -LogPath $dir {
      New-PrtgChannel -Channel 'A' -Value 1 | Add-PrtgChannel
      Set-PrtgMessage 'ok'
    }
    $result.prtg.text | Should -Be 'ok'
    $content = Get-Content -LiteralPath @(Get-ChildItem -LiteralPath $dir -Filter '*.log')[0].FullName -Raw
    $content | Should -BeLike '*sensor ok: 1 channels*'
  }

  It 'restores the session log directory and retention afterwards' {
    [void] (Invoke-PrtgSensor -EnableLogging -LogPath $dir -MaxLogs 5 { Set-PrtgMessage 'ok' })
    InModuleScope PrtgSensorKit { $script:PrtgLogDirectory } | Should -BeNullOrEmpty
    InModuleScope PrtgSensorKit { $script:PrtgLogMaxLogs } | Should -Be 30
  }

  It 'creates no files without -EnableLogging' {
    [void] (Invoke-PrtgSensor { Set-PrtgMessage 'ok' })
    InModuleScope PrtgSensorKit { $script:PrtgLogFile } | Should -BeNullOrEmpty
  }

  It 'resolves a relative -LogPath against the script folder, not the CWD' {
    $relative = "RelLogs-$(Get-Random)"
    $expected = Join-Path $PSScriptRoot $relative
    try {
      Push-Location $TestDrive
      try {
        [void] (Invoke-PrtgSensor -EnableLogging -LogPath $relative { Set-PrtgMessage 'ok' })
      } finally {
        Pop-Location
      }
      Test-Path -LiteralPath $expected | Should -BeTrue
      @(Get-ChildItem -LiteralPath $expected -Filter '*.log').Count | Should -Be 1
    } finally {
      if (Test-Path -LiteralPath $expected) { Remove-Item -LiteralPath $expected -Recurse -Force }
    }
  }

  It 'starts a new run file when -EnableLogging -LogPath points at a different folder' {
    [void] (Invoke-PrtgSensor -EnableLogging -LogPath $dir { Set-PrtgMessage 'ok' })
    $dir2 = Join-Path $TestDrive "logs2-$(Get-Random)"
    [void] (Invoke-PrtgSensor -EnableLogging -LogPath $dir2 { Set-PrtgMessage 'ok' })
    @(Get-ChildItem -LiteralPath $dir2 -Filter '*.log').Count | Should -Be 1
  }

  It 'rejects -LogPath without -EnableLogging' {
    { Invoke-PrtgSensor -LogPath $dir { Set-PrtgMessage 'ok' } } | Should -Throw '*EnableLogging*'
  }

  It 'rejects -MaxLogs without -EnableLogging' {
    { Invoke-PrtgSensor -MaxLogs 5 { Set-PrtgMessage 'ok' } } | Should -Throw '*EnableLogging*'
  }
}

Describe 'Write-PrtgLog edge paths' {
  BeforeEach {
    Reset-PrtgLogState
    $dir = Join-Path $TestDrive "logs-$(Get-Random)"
  }

  It 'falls back to a console run file and the CWD when no script is on the call stack' {
    Mock -ModuleName PrtgSensorKit Get-PrtgLogCallerScriptPath { $null }
    try {
      Push-Location $TestDrive
      [void] (Invoke-PrtgSensor -EnableLogging -LogPath 'ConsoleLogs' { Set-PrtgMessage 'ok' })
      $files = @(Get-ChildItem -LiteralPath (Join-Path $TestDrive 'ConsoleLogs') -Filter 'console_*.log')
      $files.Count | Should -Be 1
    } finally {
      Pop-Location
    }
  }

  It 'swallows prune failures and keeps logging' {
    Mock -ModuleName PrtgSensorKit Remove-Item { throw 'delete denied' }
    [void] (New-Item -ItemType Directory -Path $dir)
    foreach ($i in 1..3) {
      $stale = Join-Path $dir "old_$i.log"
      Set-Content -LiteralPath $stale -Value 'old run'
      (Get-Item -LiteralPath $stale).LastWriteTime = (Get-Date).AddHours(-$i)
    }
    { [void] (Invoke-PrtgSensor -EnableLogging -LogPath $dir -MaxLogs 1 { Set-PrtgMessage 'ok' }) } | Should -Not -Throw
    # The new run file exists and got its lifecycle lines despite every delete failing.
    $run = @(Get-ChildItem -LiteralPath $dir -Filter 'Log.Tests_*.log')
    $run.Count | Should -Be 1
    Get-Content -LiteralPath $run[0].FullName -Raw | Should -BeLike '*sensor ok*'
  }
}
