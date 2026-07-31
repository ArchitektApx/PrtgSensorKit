BeforeAll {
  . $PSScriptRoot/_TestHelpers.ps1
  Import-BuiltPrtgModule
}

# Dot-sourced at top level as well as in BeforeAll: -Skip: is evaluated at DISCOVERY time.
. $PSScriptRoot/_TestHelpers.ps1
$onWindows = Test-OnWindowsHost

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

Describe 'Sensor state coverage gaps' {
  It 'round-trips through the DEFAULT state folder when -Path is omitted' {
    # Every other test passes -Path; this one deliberately exercises the
    # ProgramData/temp default resolution. Cleans up after itself.
    $key = "CoverageProbe-$(Get-Random)"
    try {
      Save-PrtgSensorState -Key $key -Value 'default-folder'
      Get-PrtgSensorState -Key $key -Latest | Should -Be 'default-folder'
    } finally {
      Clear-PrtgSensorState -Key $key -ClearLock
    }
  }

  It 'warns and deletes when Clear-PrtgSensorState -MaxAge meets a corrupt state file' {
    $dir = Join-Path $TestDrive "state-$(Get-Random)"
    [void] (New-Item -ItemType Directory -Path $dir)
    $file = Join-Path $dir 'corrupt.clixml'
    Set-Content -LiteralPath $file -Value 'this is not clixml'
    Clear-PrtgSensorState -Key 'corrupt' -Path $dir -MaxAge (New-TimeSpan -Minutes 5) -WarningVariable warnings 3>$null
    @($warnings) -join ' ' | Should -BeLike '*unreadable*'
    Test-Path -LiteralPath $file | Should -BeFalse
  }

  It 'fails fast with the access-denied wording when the lock folder is not writable (unix)' -Skip:$onWindows {
    # A read-only folder yields UnauthorizedAccessException on lock creation, which must NOT be
    # retried until the timeout (ACL denial is not transient).
    $dir = Join-Path $TestDrive "readonly-$(Get-Random)"
    [void] (New-Item -ItemType Directory -Path $dir)
    chmod 555 $dir
    try {
      { Save-PrtgSensorState -Key 'denied' -Value 1 -Path $dir -TimeoutSeconds 30 } |
        Should -Throw '*Access denied*'
    } finally {
      chmod 755 $dir
    }
  }

  It 'fails fast with the access-denied wording when the lock folder is not writable (windows)' -Tag 'Windows' -Skip:(-not $onWindows) {
    # Same contract as the unix case, via a Deny ACE. Only CreateFiles is denied: the owner keeps
    # ChangePermissions, so the finally can always remove the ACE again and TestDrive stays
    # deletable. Denying more (or denying Delete) can strand the folder.
    $dir = Join-Path $TestDrive "denied-$(Get-Random)"
    [void] (New-Item -ItemType Directory -Path $dir)
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $deny = [System.Security.AccessControl.FileSystemAccessRule]::new(
      $me, 'CreateFiles', 'ContainerInherit,ObjectInherit', 'None', 'Deny')
    $acl = Get-Acl -LiteralPath $dir
    $acl.AddAccessRule($deny)
    Set-Acl -LiteralPath $dir -AclObject $acl
    try {
      { Save-PrtgSensorState -Key 'denied' -Value 1 -Path $dir -TimeoutSeconds 30 } |
        Should -Throw '*Access denied*'
    } finally {
      $restore = Get-Acl -LiteralPath $dir
      [void]$restore.RemoveAccessRule($deny)
      Set-Acl -LiteralPath $dir -AclObject $restore
    }
  }
}

Describe 'Timestamp tie-breaking' {
  # UtcNow has ~15 ms resolution on .NET Framework: two quick saves can carry identical
  # timestamps. The crafted files below make the tie deterministic instead of relying on
  # a fast machine to reproduce the race (which is how CI caught it).
  BeforeEach {
    $dir = Join-Path $TestDrive "tie-$(Get-Random)"
    [void] (New-Item -ItemType Directory -Path $dir)
    $ts = [DateTime]::UtcNow
    @(
      [PSCustomObject]@{ Value = 'older'; Timestamp = $ts }
      [PSCustomObject]@{ Value = 'newer'; Timestamp = $ts }
    ) | Export-Clixml -LiteralPath (Join-Path $dir 'tie.clixml')
  }

  It '-Latest returns the last-appended entry when timestamps tie' {
    Get-PrtgSensorState -Key 'tie' -Path $dir -Latest | Should -Be 'newer'
  }
}

Describe 'Get-PrtgSensorState -Latest null handling' {
  BeforeEach { $dir = Join-Path $TestDrive "statenull-$(Get-Random)" }

  It '-Latest falls back to -Default when the newest stored value is null' {
    Save-PrtgSensorState -Key 'k' -Value $null -Path $dir
    Get-PrtgSensorState -Key 'k' -Path $dir -Latest -Default 0 | Should -Be 0
  }

  It '-Latest returns $null when the value is null and no -Default was given' {
    Save-PrtgSensorState -Key 'k' -Value $null -Path $dir
    Get-PrtgSensorState -Key 'k' -Path $dir -Latest | Should -BeNullOrEmpty
  }

  It '-Latest still returns a stored zero' {
    # 0 must not trigger the fallback.
    Save-PrtgSensorState -Key 'z' -Value 0 -Path $dir
    Get-PrtgSensorState -Key 'z' -Path $dir -Latest -Default 99 | Should -Be 0
  }

  It '-Latest still returns a stored empty string' {
    Save-PrtgSensorState -Key 'e' -Value '' -Path $dir
    Get-PrtgSensorState -Key 'e' -Path $dir -Latest -Default 'fallback' | Should -BeExactly ''
  }

  It '-Latest still returns a stored $false' {
    Save-PrtgSensorState -Key 'b' -Value $false -Path $dir
    Get-PrtgSensorState -Key 'b' -Path $dir -Latest -Default $true | Should -BeFalse
  }

  It 'falls back to -Default when the newest of several entries is null' {
    Save-PrtgSensorState -Key 'mix' -Value 5 -Path $dir
    Start-Sleep -Milliseconds 20
    Save-PrtgSensorState -Key 'mix' -Value $null -Path $dir
    Get-PrtgSensorState -Key 'mix' -Path $dir -Latest -Default 0 | Should -Be 0
  }
}

Describe 'State writes are atomic' {
  BeforeEach { $dir = Join-Path $TestDrive "atomic-$(Get-Random)" }

  It 'keeps the whole history when a save fails part-way' {
    # Export-Clixml truncates before it writes, so writing straight to the state file would
    # destroy the entire entry history - the one thing a delta counter cannot reconstruct.
    Save-PrtgSensorState -Key 'hist' -Value 'first' -Path $dir
    Save-PrtgSensorState -Key 'hist' -Value 'second' -Path $dir
    Mock -CommandName Export-Clixml -ModuleName PrtgSensorKit -MockWith { throw 'simulated write failure' }
    { Save-PrtgSensorState -Key 'hist' -Value 'third' -Path $dir -ErrorAction Stop } | Should -Throw
    @(Get-PrtgSensorState -Key 'hist' -Path $dir).Value | Should -Be @('second', 'first')
  }

  It 'keeps the whole history when a prune fails part-way' {
    Save-PrtgSensorState -Key 'prune' -Value 'kept' -Path $dir
    Mock -CommandName Export-Clixml -ModuleName PrtgSensorKit -MockWith { throw 'simulated write failure' }
    { Clear-PrtgSensorState -Key 'prune' -MaxAge (New-TimeSpan -Hours 1) -Path $dir -ErrorAction Stop } |
      Should -Throw
    @(Get-PrtgSensorState -Key 'prune' -Path $dir).Value | Should -Be 'kept'
  }

  It 'leaves no temp files behind on a successful save' {
    Save-PrtgSensorState -Key 'clean' -Value 1 -Path $dir
    @(Get-ChildItem -LiteralPath $dir -Filter '*.tmp') | Should -BeNullOrEmpty
  }
}

Describe 'Partially malformed state and cache files' {
  BeforeEach { $dir = Join-Path $TestDrive "partial-$(Get-Random)" }

  It 'warns about malformed entries but still returns the valid ones' {
    # A READABLE file whose entry list is partly corrupt, as opposed to an unreadable file.
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    @(
      [PSCustomObject]@{ Value = 'good'; Timestamp = [DateTime]::UtcNow }
      [PSCustomObject]@{ Value = 'no timestamp property' }
      'not an entry object at all'
    ) | Export-Clixml -LiteralPath (Join-Path $dir 'partial.clixml') -Depth 5

    $value = Get-PrtgSensorState -Key 'partial' -Path $dir -Latest -WarningVariable warnings 3>$null
    $value | Should -Be 'good'
    ($warnings -join ' ') | Should -BeLike '*malformed entries*'
  }

  It 'warns about malformed entries when saving' {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    @(
      [PSCustomObject]@{ Value = 'good'; Timestamp = [DateTime]::UtcNow }
      [PSCustomObject]@{ Value = 'no timestamp property' }
    ) | Export-Clixml -LiteralPath (Join-Path $dir 'partialsave.clixml') -Depth 5

    Save-PrtgSensorState -Key 'partialsave' -Value 'new' -Path $dir -WarningVariable warnings 3>$null
    ($warnings -join ' ') | Should -BeLike '*malformed entries*'
    # The malformed entry is dropped, the valid one and the new one survive.
    @(Get-PrtgSensorState -Key 'partialsave' -Path $dir).Count | Should -Be 2
  }

  It 'warns about malformed entries when pruning with -MaxAge' {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    @(
      [PSCustomObject]@{ Value = 'fresh'; Timestamp = [DateTime]::UtcNow }
      [PSCustomObject]@{ Value = 'no timestamp property' }
    ) | Export-Clixml -LiteralPath (Join-Path $dir 'partialclear.clixml') -Depth 5

    Clear-PrtgSensorState -Key 'partialclear' -MaxAge (New-TimeSpan -Hours 1) -Path $dir `
      -WarningVariable warnings 3>$null
    ($warnings -join ' ') | Should -BeLike '*malformed entries*'
    Get-PrtgSensorState -Key 'partialclear' -Path $dir -Latest | Should -Be 'fresh'
  }

  It 'warns about malformed cache entries but still serves a fresh one' {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    @(
      [PSCustomObject]@{ Value = 'cached'; Timestamp = [DateTime]::UtcNow }
      [PSCustomObject]@{ Value = 'no timestamp property' }
    ) | Export-Clixml -LiteralPath (Join-Path $dir 'partialcache.clixml') -Depth 5

    $counter = @{ n = 0 }
    $value = Use-PrtgCachedResult -Key 'partialcache' -MaxAge (New-TimeSpan -Minutes 5) -Path $dir `
      -WarningVariable warnings 3>$null { $counter.n++; 'refetched' }
    $value | Should -Be 'cached'
    $counter.n | Should -Be 0
    ($warnings -join ' ') | Should -BeLike '*malformed entries*'
  }
}

Describe 'Relative -Path resolves against the PowerShell location, not the process CWD' {
  BeforeEach {
    $psLocationDir = Join-Path $TestDrive "psloc-$(Get-Random)"
    $processCwdDir = Join-Path $TestDrive "proccwd-$(Get-Random)"
    foreach ($base in $psLocationDir, $processCwdDir) {
      [void] (New-Item -ItemType Directory -Path (Join-Path $base 'store') -Force)
    }
    $originalLocation = (Get-Location).Path
    $originalCwd = [Environment]::CurrentDirectory
  }

  AfterEach {
    Set-Location -LiteralPath $originalLocation
    [Environment]::CurrentDirectory = $originalCwd
  }

  It 'puts the state file and its lock sidecar in the same directory' {
    # .NET resolves the lock path against the PROCESS working directory. With both folders
    # existing the split is silent - the lock guards a file in another directory.
    Set-Location -LiteralPath $psLocationDir
    [Environment]::CurrentDirectory = $processCwdDir

    Save-PrtgSensorState -Key 'k' -Value 42 -Path 'store'

    Test-Path -LiteralPath (Join-Path $psLocationDir 'store/k.clixml') | Should -BeTrue
    Test-Path -LiteralPath (Join-Path $psLocationDir 'store/k.clixml.lock') | Should -BeTrue
    Test-Path -LiteralPath (Join-Path $processCwdDir 'store/k.clixml.lock') | Should -BeFalse
  }

  It 'reads back a value written through a relative -Path' {
    Set-Location -LiteralPath $psLocationDir
    [Environment]::CurrentDirectory = $processCwdDir

    Save-PrtgSensorState -Key 'roundtrip' -Value 'hello' -Path 'store'
    Get-PrtgSensorState -Key 'roundtrip' -Path 'store' -Latest | Should -Be 'hello'
  }
}

Describe 'State lock fails fast when its folder does not exist' {
  It 'throws the missing-folder message instead of stalling for the full timeout' {
    # DirectoryNotFoundException derives from IOException, so without its own handling it
    # lands in the retry arm and spins to the deadline blaming a concurrent run. Unreachable
    # through the public cmdlets now that Get-PrtgStatePath creates the folder, so this
    # exercises the lock helper directly - a -Path on a vanished network share reaches the
    # same code.
    $missing = Join-Path $TestDrive "gone-$(Get-Random)/deeper/k.clixml.lock"

    # Returned rather than parked in $script:, which inside InModuleScope IS the module's own
    # scope and would leave the values there for every later test in the session.
    $result = InModuleScope PrtgSensorKit -Parameters @{ LockPath = $missing } {
      param($LockPath)
      $sw = [System.Diagnostics.Stopwatch]::StartNew()
      $message = $null
      try {
        Invoke-PrtgStateLock -PrtgLockFile $LockPath -PrtgLockTimeout 10 -PrtgLockBlock { 'never runs' }
      } catch {
        $message = $_.Exception.Message
      }
      $sw.Stop()
      [PSCustomObject]@{ Message = $message; Elapsed = $sw.Elapsed.TotalSeconds }
    }

    $result.Message | Should -Not -BeNullOrEmpty
    $result.Message | Should -BeLike '*does not exist*'
    $result.Elapsed | Should -BeLessThan 2
  }
}

Describe 'A caller script block sees its OWN variables inside the state lock' {
  It 'does not bind the lock function frame for names it used to declare' {
    # '& $PrtgLockBlock' resolves unqualified names up the dynamic chain, so an unprefixed
    # parameter on Invoke-PrtgStateLock would shadow these caller variables.
    $lock = Join-Path $TestDrive "shadow-$(Get-Random).lock"
    [void] (New-Item -ItemType Directory -Path (Split-Path -Parent $lock) -Force)

    $seen = InModuleScope PrtgSensorKit -Parameters @{ LockPath = $lock } {
      param($LockPath)
      $TimeoutSeconds = 999
      $Force = 'caller-force'
      $LockFile = 'caller-lockfile'
      $ScriptBlock = 'caller-scriptblock'
      $DeleteLockOnRelease = 'caller-delete'

      Invoke-PrtgStateLock -PrtgLockFile $LockPath -PrtgLockTimeout 5 -PrtgLockBlock {
        [PSCustomObject]@{
          TimeoutSeconds      = $TimeoutSeconds
          Force               = $Force
          LockFile            = $LockFile
          ScriptBlock         = $ScriptBlock
          DeleteLockOnRelease = $DeleteLockOnRelease
        }
      }
    }

    $seen.TimeoutSeconds | Should -Be 999
    $seen.Force | Should -Be 'caller-force'
    $seen.LockFile | Should -Be 'caller-lockfile'
    $seen.ScriptBlock | Should -Be 'caller-scriptblock'
    $seen.DeleteLockOnRelease | Should -Be 'caller-delete'
  }

  It 'still honours a non-default -TimeoutSeconds and -Force on the public cmdlets' {
    $dir = Join-Path $TestDrive "state-lockargs-$(Get-Random)"
    Save-PrtgSensorState -Key 'k' -Value 1 -Path $dir -TimeoutSeconds 3
    Get-PrtgSensorState -Key 'k' -Path $dir -TimeoutSeconds 3 -Latest | Should -Be 1
    Save-PrtgSensorState -Key 'k' -Value 2 -Path $dir -Force
    Get-PrtgSensorState -Key 'k' -Path $dir -Force -Latest | Should -Be 2
    Use-PrtgCachedResult -Key 'c' -MaxAge (New-TimeSpan -Minutes 5) -Path $dir -TimeoutSeconds 3 { 'fetched' } |
      Should -Be 'fetched'
    Clear-PrtgSensorState -Key 'k' -Path $dir -TimeoutSeconds 3
    Test-Path -LiteralPath (Join-Path $dir 'k.clixml') | Should -BeFalse
  }
}
