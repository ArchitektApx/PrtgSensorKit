BeforeAll {
  . $PSScriptRoot/_TestHelpers.ps1
  Import-BuiltPrtgModule

  # Opens the exclusive lock handle the way the module does, to simulate a concurrent run.
  function Get-TestLockHandle([string]$LockFile) {
    [System.IO.FileStream]::new(
      $LockFile,
      [System.IO.FileMode]::OpenOrCreate,
      [System.IO.FileAccess]::ReadWrite,
      [System.IO.FileShare]::None)
  }
}

Describe 'Save/Get-PrtgSensorState round-trip' {
  BeforeEach { $dir = Join-Path $TestDrive "state-$(Get-Random)" }

  It 'round-trips a simple value with a UTC timestamp' {
    Save-PrtgSensorState -Key 'k' -Value 42 -Path $dir
    $entries = @(Get-PrtgSensorState -Key 'k' -Path $dir)
    $entries.Count | Should -Be 1
    $entries[0].Value | Should -Be 42
    ([DateTime]::UtcNow - $entries[0].Timestamp.ToUniversalTime()).TotalMinutes | Should -BeLessThan 1
  }

  It 'preserves nested structure deeper than the Clixml default depth of 2' {
    $nested = @{ a = @{ b = @{ c = @{ d = 'deep' } } } }
    Save-PrtgSensorState -Key 'nested' -Value $nested -Path $dir
    $got = Get-PrtgSensorState -Key 'nested' -Path $dir -Latest
    $got.a.b.c.d | Should -Be 'deep'
  }

  It 'returns entries newest first' {
    1..3 | ForEach-Object { Save-PrtgSensorState -Key 'multi' -Value $_ -Path $dir; Start-Sleep -Milliseconds 20 }
    $entries = @(Get-PrtgSensorState -Key 'multi' -Path $dir)
    $entries.Count | Should -Be 3
    $entries[0].Value | Should -Be 3
    $entries[2].Value | Should -Be 1
  }

  It '-Latest returns the bare value of the newest entry' {
    Save-PrtgSensorState -Key 'latest' -Value 'old' -Path $dir
    Start-Sleep -Milliseconds 20
    Save-PrtgSensorState -Key 'latest' -Value 'new' -Path $dir
    Get-PrtgSensorState -Key 'latest' -Path $dir -Latest | Should -Be 'new'
  }

  It 'returns $null for a missing key' {
    Get-PrtgSensorState -Key 'nope' -Path $dir | Should -BeNullOrEmpty
  }

  It 'returns -Default for a missing key' {
    Get-PrtgSensorState -Key 'nope' -Path $dir -Default 99 | Should -Be 99
    Get-PrtgSensorState -Key 'nope' -Path $dir -Latest -Default 99 | Should -Be 99
  }

  It 'filters entries older than -MaxAge (and falls back to -Default when all are too old)' {
    # Hand-written state file in the module's format, with one stale and one fresh entry.
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    @(
      [PSCustomObject]@{ Value = 'stale'; Timestamp = [DateTime]::UtcNow.AddHours(-2) }
      [PSCustomObject]@{ Value = 'fresh'; Timestamp = [DateTime]::UtcNow }
    ) | Export-Clixml -LiteralPath (Join-Path $dir 'aged.clixml')

    $entries = @(Get-PrtgSensorState -Key 'aged' -Path $dir -MaxAge (New-TimeSpan -Hours 1))
    $entries.Count | Should -Be 1
    $entries[0].Value | Should -Be 'fresh'

    Get-PrtgSensorState -Key 'aged' -Path $dir -MaxAge (New-TimeSpan -Minutes 30) -Latest -Default 'gone' |
      Should -Be 'fresh'
    Get-PrtgSensorState -Key 'aged' -Path $dir -MaxAge (New-TimeSpan -Seconds 0) -Default 'gone' |
      Should -Be 'gone'
  }

  It '-MaxEntries keeps only the newest N entries' {
    1..5 | ForEach-Object { Save-PrtgSensorState -Key 'capped' -Value $_ -Path $dir -MaxEntries 3; Start-Sleep -Milliseconds 20 }
    $entries = @(Get-PrtgSensorState -Key 'capped' -Path $dir)
    $entries.Count | Should -Be 3
    $entries[0].Value | Should -Be 5
    $entries[2].Value | Should -Be 3
  }

  It 'warns and starts fresh on a corrupt state file (Save)' {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'corrupt.clixml') -Value 'this is not clixml'
    Save-PrtgSensorState -Key 'corrupt' -Value 'recovered' -Path $dir -WarningVariable warns -WarningAction SilentlyContinue
    $warns | Should -Not -BeNullOrEmpty
    Get-PrtgSensorState -Key 'corrupt' -Path $dir -Latest | Should -Be 'recovered'
  }

  It 'warns and returns -Default on a corrupt state file (Get)' {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'corrupt.clixml') -Value 'this is not clixml'
    Get-PrtgSensorState -Key 'corrupt' -Path $dir -Default 'fallback' -WarningVariable warns -WarningAction SilentlyContinue |
      Should -Be 'fallback'
    $warns | Should -Not -BeNullOrEmpty
  }

  It 'rejects keys outside the allowed pattern' {
    { Save-PrtgSensorState -Key 'bad/key' -Value 1 -Path $dir } | Should -Throw
    { Get-PrtgSensorState -Key 'bad key' -Path $dir } | Should -Throw
    { Clear-PrtgSensorState -Key 'bad#key' -Path $dir } | Should -Throw
  }
}

Describe 'Clear-PrtgSensorState' {
  BeforeEach { $dir = Join-Path $TestDrive "clear-$(Get-Random)" }

  It 'deletes the state file without -MaxAge' {
    Save-PrtgSensorState -Key 'gone' -Value 1 -Path $dir
    Clear-PrtgSensorState -Key 'gone' -Path $dir
    Test-Path (Join-Path $dir 'gone.clixml') | Should -BeFalse
    Get-PrtgSensorState -Key 'gone' -Path $dir -Default 'empty' | Should -Be 'empty'
  }

  It 'prunes only entries older than -MaxAge' {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    @(
      [PSCustomObject]@{ Value = 'stale'; Timestamp = [DateTime]::UtcNow.AddHours(-2) }
      [PSCustomObject]@{ Value = 'fresh'; Timestamp = [DateTime]::UtcNow }
    ) | Export-Clixml -LiteralPath (Join-Path $dir 'prune.clixml')

    Clear-PrtgSensorState -Key 'prune' -Path $dir -MaxAge (New-TimeSpan -Hours 1)
    $entries = @(Get-PrtgSensorState -Key 'prune' -Path $dir)
    $entries.Count | Should -Be 1
    $entries[0].Value | Should -Be 'fresh'
  }

  It 'deletes the file when -MaxAge prunes everything' {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    @([PSCustomObject]@{ Value = 'stale'; Timestamp = [DateTime]::UtcNow.AddHours(-2) }) |
      Export-Clixml -LiteralPath (Join-Path $dir 'allold.clixml')
    Clear-PrtgSensorState -Key 'allold' -Path $dir -MaxAge (New-TimeSpan -Hours 1)
    Test-Path (Join-Path $dir 'allold.clixml') | Should -BeFalse
  }

  It 'is a no-op for a missing key' {
    { Clear-PrtgSensorState -Key 'never-existed' -Path $dir } | Should -Not -Throw
  }

  It 'leaves the lock sidecar by default and removes it with -ClearLock' {
    Save-PrtgSensorState -Key 'locky' -Value 1 -Path $dir
    $lock = Join-Path $dir 'locky.clixml.lock'
    Test-Path $lock | Should -BeTrue

    Clear-PrtgSensorState -Key 'locky' -Path $dir
    Test-Path $lock | Should -BeTrue

    Clear-PrtgSensorState -Key 'locky' -Path $dir -ClearLock
    Test-Path $lock | Should -BeFalse
  }

  It '-ClearLock refuses while another run holds the lock' {
    Save-PrtgSensorState -Key 'held' -Value 1 -Path $dir
    $handle = Get-TestLockHandle (Join-Path $dir 'held.clixml.lock')
    try {
      { Clear-PrtgSensorState -Key 'held' -Path $dir -ClearLock -TimeoutSeconds 0 } | Should -Throw '*lock*'
    } finally {
      $handle.Dispose()
    }
  }
}

Describe 'Sensor state locking' {
  BeforeEach {
    $dir = Join-Path $TestDrive "lock-$(Get-Random)"
    Save-PrtgSensorState -Key 'shared' -Value 'seed' -Path $dir
    $lockFile = Join-Path $dir 'shared.clixml.lock'
  }

  It 'fails fast with -TimeoutSeconds 0 while the lock is held' {
    $handle = Get-TestLockHandle $lockFile
    try {
      { Save-PrtgSensorState -Key 'shared' -Value 'x' -Path $dir -TimeoutSeconds 0 } | Should -Throw '*lock*'
      { Clear-PrtgSensorState -Key 'shared' -Path $dir -TimeoutSeconds 0 } | Should -Throw '*lock*'
    } finally {
      $handle.Dispose()
    }
  }

  It 'throws on lock timeout even when -Default is set (Get)' {
    $handle = Get-TestLockHandle $lockFile
    try {
      { Get-PrtgSensorState -Key 'shared' -Path $dir -TimeoutSeconds 0 -Default 'fallback' } | Should -Throw '*lock*'
    } finally {
      $handle.Dispose()
    }
  }

  It '-Force reads and writes past a held lock' {
    $handle = Get-TestLockHandle $lockFile
    try {
      Save-PrtgSensorState -Key 'shared' -Value 'forced' -Path $dir -Force
      Get-PrtgSensorState -Key 'shared' -Path $dir -Latest -Force | Should -Be 'forced'
    } finally {
      $handle.Dispose()
    }
  }

  It 'waits for a lock released by a concurrent holder' {
    $ps = [PowerShell]::Create()
    [void] $ps.AddScript({
      param($LockFile)
      $h = [System.IO.FileStream]::new($LockFile, [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
      Start-Sleep -Milliseconds 500
      $h.Dispose()
    }).AddArgument($lockFile)
    $async = $ps.BeginInvoke()

    try {
      # Wait until the holder ACTUALLY owns the lock (runspace startup time varies wildly
      # on slow machines; a fixed sleep is racy). The probe open failing = holder has it.
      $holderOwnsLock = $false
      $deadline = [DateTime]::UtcNow.AddSeconds(5)
      while ([DateTime]::UtcNow -lt $deadline) {
        try {
          $probe = Get-TestLockHandle $lockFile
          $probe.Dispose()
          Start-Sleep -Milliseconds 20
        } catch {
          $holderOwnsLock = $true
          break
        }
      }
      $holderOwnsLock | Should -BeTrue

      # Must block until the holder releases, then succeed within the timeout.
      Save-PrtgSensorState -Key 'shared' -Value 'waited' -Path $dir -TimeoutSeconds 5
      Get-PrtgSensorState -Key 'shared' -Path $dir -Latest | Should -Be 'waited'
    } finally {
      [void] $ps.EndInvoke($async)
      $ps.Dispose()
    }
  }

  It 'releases the lock even when the locked operation fails (finally path)' {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'shared.clixml') -Value 'corrupt'
    # Corrupt file makes the read warn inside the locked section; afterwards the lock must be free.
    Get-PrtgSensorState -Key 'shared' -Path $dir -WarningAction SilentlyContinue | Out-Null
    $handle = Get-TestLockHandle $lockFile
    try {
      $handle | Should -Not -BeNullOrEmpty
    } finally {
      $handle.Dispose()
    }
  }

  It 'recovers from a stale lock after the holder goes away (handle disposed)' {
    $handle = Get-TestLockHandle $lockFile
    $handle.Dispose()   # simulates the holding process dying: the OS releases the handle
    Save-PrtgSensorState -Key 'shared' -Value 'recovered' -Path $dir -TimeoutSeconds 0
    Get-PrtgSensorState -Key 'shared' -Path $dir -Latest | Should -Be 'recovered'
  }
}
