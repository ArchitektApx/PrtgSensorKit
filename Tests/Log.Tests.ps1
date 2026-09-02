BeforeAll {
  . $PSScriptRoot/_TestHelpers.ps1
  Import-ModuleUnderTest

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
    $dir = New-TestStore 'logs'
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
    $dir = New-TestStore 'logs'
    # Run files this script would have written itself: '<scriptname>_<stamp>_<pid>.log'.
    # Only these are prunable - see the 'never prunes files it did not create' cases below.
    foreach ($i in 1..5) {
      $stale = Join-Path $dir ('Log.Tests_2026010{0}-00000{0}_100{0}.log' -f $i)
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

Describe 'Write-PrtgLog pruning never deletes files it did not create' {
  BeforeEach {
    Reset-PrtgLogState
    $dir = New-TestStore 'shared-logs'
  }

  It 'leaves unrelated application logs alone' {
    # The -LogPath a user is told to use ("$PSScriptRoot\Logs") can already hold other logs.
    foreach ($name in 'unrelated.log', 'otherapp.log') {
      Set-Content -LiteralPath (Join-Path $dir $name) -Value 'production log'
    }
    [void] (Invoke-PrtgSensor -EnableLogging -LogPath $dir -MaxLogs 1 { Set-PrtgMessage 'ok' })
    Test-Path -LiteralPath (Join-Path $dir 'unrelated.log') | Should -BeTrue
    Test-Path -LiteralPath (Join-Path $dir 'otherapp.log') | Should -BeTrue
  }

  It 'leaves another sensor script run files alone' {
    foreach ($i in 1..4) {
      Set-Content -LiteralPath (Join-Path $dir ('beta_2026010{0}-00000{0}_200{0}.log' -f $i)) -Value 'beta run'
    }
    [void] (Invoke-PrtgSensor -EnableLogging -LogPath $dir -MaxLogs 1 { Set-PrtgMessage 'ok' })
    @(Get-ChildItem -LiteralPath $dir -Filter 'beta_*.log').Count | Should -Be 4
  }

  It 'leaves a sibling script sharing our name prefix alone' {
    # The case a bare StartsWith("$scriptName`_") test would fail: 'Log.Tests_extra' also
    # starts with 'Log.Tests_'. Only the fully anchored run-file pattern excludes it.
    foreach ($i in 1..4) {
      Set-Content -LiteralPath (Join-Path $dir ('Log.Tests_extra_2026010{0}-00000{0}_300{0}.log' -f $i)) -Value 'sibling run'
    }
    [void] (Invoke-PrtgSensor -EnableLogging -LogPath $dir -MaxLogs 1 { Set-PrtgMessage 'ok' })
    @(Get-ChildItem -LiteralPath $dir -Filter 'Log.Tests_extra_*.log').Count | Should -Be 4
  }

  It 'still prunes its own run files past MaxLogs' {
    # Guards against "fixing" the above by disabling retention altogether.
    foreach ($i in 1..4) {
      $own = Join-Path $dir ('Log.Tests_2026010{0}-00000{0}_400{0}.log' -f $i)
      Set-Content -LiteralPath $own -Value 'own run'
      (Get-Item -LiteralPath $own).LastWriteTime = (Get-Date).AddHours(-$i)
    }
    [void] (Invoke-PrtgSensor -EnableLogging -LogPath $dir -MaxLogs 2 { Set-PrtgMessage 'ok' })
    @(Get-ChildItem -LiteralPath $dir -Filter 'Log.Tests_*.log').Count | Should -Be 2
  }
}

Describe 'Invoke-PrtgSensor -EnableLogging lifecycle' {
  BeforeEach {
    Reset-PrtgLogState
    $dir = New-TestStore 'logs'
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

  It 'keeps the run file it created, so later Write-PrtgLog calls append to it' {
    # Regression: the run file was captured before the call created it and restored
    # unconditionally, so a later Write-PrtgLog in the same script started a SECOND run file.
    # Only -LogPath discards the run file, so only -LogPath may restore it.
    InModuleScope PrtgSensorKit -Parameters @{ Dir = $dir } {
      param($Dir)
      $script:PrtgLogDirectory = $Dir
      [void] (Invoke-PrtgSensor -EnableLogging { Set-PrtgMessage 'ok' })
      $script:PrtgLogFile | Should -Not -BeNullOrEmpty
      Write-PrtgLog 'a later line in the same script'
      @(Get-ChildItem -LiteralPath $Dir -Filter '*.log').Count | Should -Be 1
      (Get-Content -LiteralPath $script:PrtgLogFile -Raw) | Should -BeLike '*a later line in the same script*'
    }
  }

  It 'restores the previous run file when -LogPath sent this call elsewhere' {
    $other = New-TestStore 'logs-other'
    InModuleScope PrtgSensorKit -Parameters @{ Dir = $dir; Other = $other } {
      param($Dir, $Other)
      $script:PrtgLogDirectory = $Dir
      Write-PrtgLog 'first line, pins the run file'
      $pinned = $script:PrtgLogFile
      [void] (Invoke-PrtgSensor -EnableLogging -LogPath $Other { Set-PrtgMessage 'ok' })
      $script:PrtgLogFile | Should -Be $pinned
    }
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
    $dir2 = New-TestStore 'logs2'
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
    $dir = New-TestStore 'logs'
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

Describe 'Invoke-PrtgSensor -LogPath run file restore' {
  BeforeEach { Reset-PrtgLogState }

  It 'restores the run file after the call so later lines go back to the original folder' {
    $a = New-TestStore 'log-a'
    $b = New-TestStore 'log-b'

    InModuleScope PrtgSensorKit -Parameters @{ Dir = $a } { param($Dir) $script:PrtgLogDirectory = $Dir }
    Write-PrtgLog 'before'
    [void] (Invoke-PrtgSensor -EnableLogging -LogPath $b { Set-PrtgMessage 'ok' })
    Write-PrtgLog 'after'

    $aFiles = @(Get-ChildItem -LiteralPath $a -Filter '*.log')
    $bFiles = @(Get-ChildItem -LiteralPath $b -Filter '*.log')
    $aFiles.Count | Should -Be 1
    $bFiles.Count | Should -Be 1

    $aContent = Get-Content -LiteralPath $aFiles[0].FullName -Raw
    $aContent | Should -BeLike '*before*'
    $aContent | Should -BeLike '*after*'

    $bContent = Get-Content -LiteralPath $bFiles[0].FullName -Raw
    $bContent | Should -BeLike '*sensor start*'
    $bContent | Should -Not -BeLike '*after*'
    $bContent | Should -Not -BeLike '*before*'
  }

  It 'restores the run file even when the block throws' {
    $a = New-TestStore 'log-a2'
    $b = New-TestStore 'log-b2'
    InModuleScope PrtgSensorKit -Parameters @{ Dir = $a } { param($Dir) $script:PrtgLogDirectory = $Dir }
    Write-PrtgLog 'before'
    [void] (Invoke-PrtgSensor -EnableLogging -LogPath $b { throw 'boom' })
    Write-PrtgLog 'after'
    (Get-Content -LiteralPath @(Get-ChildItem -LiteralPath $a -Filter '*.log')[0].FullName -Raw) |
      Should -BeLike '*after*'
  }

  It 'still restores the directory and retention settings' {
    $a = New-TestStore 'log-a3'
    $b = New-TestStore 'log-b3'
    InModuleScope PrtgSensorKit -Parameters @{ Dir = $a } { param($Dir) $script:PrtgLogDirectory = $Dir }
    [void] (Invoke-PrtgSensor -EnableLogging -LogPath $b -MaxLogs 3 { Set-PrtgMessage 'ok' })
    InModuleScope PrtgSensorKit { $script:PrtgLogDirectory } | Should -Be $a
    InModuleScope PrtgSensorKit { $script:PrtgLogMaxLogs } | Should -Be 30
  }
}

Describe 'Push-PrtgLogScope and Pop-PrtgLogScope' {
  BeforeEach { Reset-PrtgLogState }
  AfterEach { Reset-PrtgLogState }

  It 'keeps the run file the scope itself created' {
    # Nothing was discarded, so nothing is restored; an unconditional restore would null the
    # run file this scope created and the next Write-PrtgLog would start a second file.
    $dir = New-TestStore 'scope-created'
    $seen = InModuleScope PrtgSensorKit -Parameters @{ Dir = $dir } {
      param($Dir)
      $token = Push-PrtgLogScope -LogPath $Dir
      Write-PrtgLog 'creates the run file'
      $created = $script:PrtgLogFile
      Pop-PrtgLogScope $token
      [PSCustomObject]@{ RestoreFile = $token.RestoreFile; Created = $created; After = $script:PrtgLogFile }
    }

    $seen.Created | Should -Not -BeNullOrEmpty
    $seen.RestoreFile | Should -BeFalse
    $seen.After | Should -Be $seen.Created
  }

  It 'restores the earlier run file the scope discarded' {
    # An earlier call pinned a run file elsewhere; the push discarded it, so the pop restores it.
    $a = New-TestStore 'scope-a'
    $b = New-TestStore 'scope-b'
    $seen = InModuleScope PrtgSensorKit -Parameters @{ A = $a; B = $b } {
      param($A, $B)
      $script:PrtgLogDirectory = $A
      Write-PrtgLog 'pins the run file in A'
      $pinned = $script:PrtgLogFile
      $token = Push-PrtgLogScope -LogPath $B
      $inside = $script:PrtgLogFile
      Pop-PrtgLogScope $token
      [PSCustomObject]@{ RestoreFile = $token.RestoreFile; Pinned = $pinned; Inside = $inside; After = $script:PrtgLogFile }
    }

    $seen.Pinned | Should -Not -BeNullOrEmpty
    $seen.RestoreFile | Should -BeTrue
    $seen.Inside | Should -BeNullOrEmpty
    $seen.After | Should -Be $seen.Pinned
  }

  It 'anchors a relative log path to the sensor script folder, not the working directory' {
    $relative = "RelScope-$(Get-Random)"
    $expected = Join-Path $PSScriptRoot $relative
    $elsewhere = New-TestStore 'scope-cwd'

    $resolved = InModuleScope PrtgSensorKit -Parameters @{ Relative = $relative; Elsewhere = $elsewhere } {
      param($Relative, $Elsewhere)
      $token = $null
      Push-Location $Elsewhere
      try {
        $token = Push-PrtgLogScope -LogPath $Relative
        $script:PrtgLogDirectory
      } finally {
        Pop-Location
        Pop-PrtgLogScope $token
      }
    }

    $resolved | Should -Be $expected
    $resolved | Should -Not -BeLike (Join-Path $elsewhere '*')
    # The push only resolves; the folder is created lazily by the first log write.
    Test-Path -LiteralPath $expected | Should -BeFalse
  }

  It 'restores the session directory and retention, and tolerates a null token' {
    $dir = New-TestStore 'scope-settings'
    $seen = InModuleScope PrtgSensorKit -Parameters @{ Dir = $dir } {
      param($Dir)
      $script:PrtgLogDirectory = $Dir
      $script:PrtgLogMaxLogs = 7
      $token = Push-PrtgLogScope -LogPath (Join-Path $Dir 'nested') -MaxLogs 2
      $inside = [PSCustomObject]@{ Directory = $script:PrtgLogDirectory; MaxLogs = $script:PrtgLogMaxLogs }
      Pop-PrtgLogScope $token
      Pop-PrtgLogScope $null
      [PSCustomObject]@{
        Inside    = $inside
        Directory = $script:PrtgLogDirectory
        MaxLogs   = $script:PrtgLogMaxLogs
      }
    }

    $seen.Inside.Directory | Should -Be (Join-Path $dir 'nested')
    $seen.Inside.MaxLogs | Should -Be 2
    $seen.Directory | Should -Be $dir
    $seen.MaxLogs | Should -Be 7
  }
}
