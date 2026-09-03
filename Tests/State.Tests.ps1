BeforeAll {
  . $PSScriptRoot/_TestHelpers.ps1
  Import-ModuleUnderTest
}

# Dot-sourced at top level as well as in BeforeAll: -Skip: is evaluated at DISCOVERY time.
. $PSScriptRoot/_TestHelpers.ps1
$onWindows = Test-OnWindowsHost

# Also discovery-time. The mixed-kind ordering tests only discriminate where the host's UTC
# offset is nonzero: at offset zero the raw and the normalized comparison agree (ADR 0002).
$noUtcOffset = ([TimeZoneInfo]::Local.GetUtcOffset([DateTime]::UtcNow) -eq [TimeSpan]::Zero)

Describe 'Save/Get-PrtgSensorState round-trip' {
  BeforeEach { $dir = New-TestStore 'state' }

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
    Set-Content -LiteralPath (Join-Path $dir 'corrupt.clixml') -Value 'this is not clixml'
    Save-PrtgSensorState -Key 'corrupt' -Value 'recovered' -Path $dir -WarningVariable warns -WarningAction SilentlyContinue
    $warns | Should -Not -BeNullOrEmpty
    Get-PrtgSensorState -Key 'corrupt' -Path $dir -Latest | Should -Be 'recovered'
  }

  It 'warns and returns -Default on a corrupt state file (Get)' {
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
  BeforeEach { $dir = New-TestStore 'clear' }

  It 'deletes the state file without -MaxAge' {
    Save-PrtgSensorState -Key 'gone' -Value 1 -Path $dir
    Clear-PrtgSensorState -Key 'gone' -Path $dir
    Test-Path (Join-Path $dir 'gone.clixml') | Should -BeFalse
    Get-PrtgSensorState -Key 'gone' -Path $dir -Default 'empty' | Should -Be 'empty'
  }

  It 'prunes only entries older than -MaxAge' {
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

Describe 'Clear-PrtgSensorState -ClearLock -Force' {
  # Success is silent and failure only warns, so the two outcomes need two tests.
  BeforeEach { $dir = New-TestStore 'clearforce' }

  It 'removes the sidecar and says nothing when nothing holds the lock' {
    Save-PrtgSensorState -Key 'freelock' -Value 1 -Path $dir
    $lock = Join-Path $dir 'freelock.clixml.lock'
    Test-Path $lock | Should -BeTrue

    Clear-PrtgSensorState -Key 'freelock' -Path $dir -ClearLock -Force `
      -WarningVariable warnings -WarningAction SilentlyContinue

    Test-Path $lock | Should -BeFalse
    Test-Path (Join-Path $dir 'freelock.clixml') | Should -BeFalse
    $warnings | Should -BeNullOrEmpty
  }

  It 'warns and leaves the sidecar when the removal fails' -Tag 'Windows' -Skip:(-not $onWindows) {
    # The lock helper's exclusive sharing blocks a second OPEN everywhere but blocks a DELETE
    # only on Windows; on a POSIX host the removal succeeds and there is no failure to observe.
    Save-PrtgSensorState -Key 'heldlock' -Value 1 -Path $dir
    $lock = Join-Path $dir 'heldlock.clixml.lock'
    $handle = Get-TestLockHandle $lock
    try {
      # Redirection rather than -ErrorVariable: a caught -ErrorAction Stop record still lands in
      # -ErrorVariable, so only the streams show what an operator actually sees.
      $records = & { Clear-PrtgSensorState -Key 'heldlock' -Path $dir -ClearLock -Force } 3>&1 2>&1
      $emitted = @($records | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
      $failures = @($records | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })

      # The operator's only signal that the lock file is still there.
      $emitted.Count | Should -Be 1 -Because 'a failed lock removal must reach the warning stream on every call path'
      "$emitted" | Should -Match 'could not remove lock file'
      "$emitted" | Should -Match 'probably held by a live run'
      "$emitted" | Should -Match 'heldlock\.clixml\.lock'
      Test-Path $lock | Should -BeTrue

      # Reported once, as that warning, and not also as a raw Remove-Item error.
      $failures | Should -BeNullOrEmpty

      # Best-effort: the rest of the work still happened.
      Test-Path (Join-Path $dir 'heldlock.clixml') | Should -BeFalse
    } finally {
      $handle.Dispose()
    }
  }
}

Describe 'Sensor state locking' {
  BeforeEach {
    $dir = New-TestStore 'lock'
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

      Save-PrtgSensorState -Key 'shared' -Value 'waited' -Path $dir -TimeoutSeconds 5
      Get-PrtgSensorState -Key 'shared' -Path $dir -Latest | Should -Be 'waited'
    } finally {
      [void] $ps.EndInvoke($async)
      $ps.Dispose()
    }
  }

  It 'releases the lock even when the locked operation fails (finally path)' {
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
    $dir = New-TestStore 'state'
    $file = Join-Path $dir 'corrupt.clixml'
    Set-Content -LiteralPath $file -Value 'this is not clixml'
    Clear-PrtgSensorState -Key 'corrupt' -Path $dir -MaxAge (New-TimeSpan -Minutes 5) -WarningVariable warnings 3>$null
    @($warnings) -join ' ' | Should -BeLike '*unreadable*'
    Test-Path -LiteralPath $file | Should -BeFalse
  }

  It 'fails fast with the access-denied wording when the lock folder is not writable (unix)' -Skip:$onWindows {
    # A read-only folder yields UnauthorizedAccessException on lock creation, which must NOT be
    # retried until the timeout (ACL denial is not transient).
    $dir = New-TestStore 'readonly'
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
    # ChangePermissions, so the finally can drop the ACE again and TestDrive stays deletable.
    $dir = New-TestStore 'denied'
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
  # UtcNow has ~15 ms resolution on .NET Framework, so two saves can tie. The crafted files
  # make the tie deterministic.
  BeforeEach {
    $dir = New-TestStore 'tie'
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
  BeforeEach { $dir = New-TestStore 'statenull' }

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
  BeforeEach { $dir = New-TestStore 'atomic' }

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
  BeforeEach { $dir = New-TestStore 'partial' }

  It 'warns about malformed entries but still returns the valid ones' {
    # A READABLE file whose entry list is partly corrupt, as opposed to an unreadable file.
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
    # DirectoryNotFoundException derives from IOException, so without its own handling it spins
    # to the deadline blaming a concurrent run. A -Path on a vanished share reaches this code.
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
    # An unprefixed parameter on Invoke-PrtgStateLock would shadow these caller names (ADR 0001).
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

  It 'does not bind EITHER frame when the block crosses the envelope and the lock' {
    # Two frames sit between a cmdlet and its block, Invoke-PrtgStateOperation above
    # Invoke-PrtgStateLock; the prefixes must protect the caller's values through both (ADR 0001).
    $dir = New-TestStore 'twoframe'

    $seen = InModuleScope PrtgSensorKit -Parameters @{ StorePath = $dir } {
      param($StorePath)
      # Every name either frame could plausibly have wanted, set to a value only this scope has.
      $Key = 'caller-key'
      $Path = 'caller-path'
      $file = 'caller-file'
      $LockFile = 'caller-lockfile'
      $State = 'caller-state'
      $TimeoutSeconds = 999
      $Force = 'caller-force'
      $ScriptBlock = 'caller-scriptblock'
      $DeleteLockOnRelease = 'caller-delete'

      Invoke-PrtgStateOperation -PrtgOpKey 'twoframe' -PrtgOpPath $StorePath -PrtgOpTimeout 5 -PrtgOpBlock {
        param($PrtgOpState)
        [PSCustomObject]@{
          Key                 = $Key
          Path                = $Path
          File                = $file
          LockFile            = $LockFile
          State               = $State
          TimeoutSeconds      = $TimeoutSeconds
          Force               = $Force
          ScriptBlock         = $ScriptBlock
          DeleteLockOnRelease = $DeleteLockOnRelease
          Resolved            = $PrtgOpState.File
        }
      }
    }

    $seen.Key | Should -Be 'caller-key'
    $seen.Path | Should -Be 'caller-path'
    $seen.File | Should -Be 'caller-file'
    $seen.LockFile | Should -Be 'caller-lockfile'
    $seen.State | Should -Be 'caller-state'
    $seen.TimeoutSeconds | Should -Be 999
    $seen.Force | Should -Be 'caller-force'
    $seen.ScriptBlock | Should -Be 'caller-scriptblock'
    $seen.DeleteLockOnRelease | Should -Be 'caller-delete'
    # The resolved paths reach the block as an explicit argument, not by dynamic lookup, so
    # the caller's own $file above is untouched by it.
    $seen.Resolved | Should -Be (Join-Path $dir 'twoframe.clixml')
  }

  It 'still honours a non-default -TimeoutSeconds and -Force on the public cmdlets' {
    $dir = New-TestStore 'state-lockargs'
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

Describe 'Corruption warnings the operator relies on' {
  # The consequence clause tells the operator what happens to their data, the noun frames the
  # file, and the cmdlet name identifies the sensor when several run at once.
  BeforeEach { $dir = New-TestStore 'warn' }

  Context 'an unreadable file' {
    It 'Save-PrtgSensorState says the state file will be replaced' {
      Set-Content -LiteralPath (Join-Path $dir 'badsave.clixml') -Value 'this is not clixml'

      Save-PrtgSensorState -Key 'badsave' -Value 'recovered' -Path $dir -WarningVariable warnings 3>$null

      (@($warnings) -join ' ') | Should -BeLike `
        "Save-PrtgSensorState: existing state file '*badsave.clixml' is unreadable and will be replaced. (*)"
    }

    It 'Get-PrtgSensorState says the state file is treated as empty' {
      Set-Content -LiteralPath (Join-Path $dir 'badget.clixml') -Value 'this is not clixml'

      Get-PrtgSensorState -Key 'badget' -Path $dir -WarningVariable warnings 3>$null | Out-Null

      (@($warnings) -join ' ') | Should -BeLike `
        "Get-PrtgSensorState: state file '*badget.clixml' is unreadable, treating it as empty. (*)"
    }

    It 'Clear-PrtgSensorState says the state file will be deleted, and deletes it' {
      $file = Join-Path $dir 'badclear.clixml'
      Set-Content -LiteralPath $file -Value 'this is not clixml'

      Clear-PrtgSensorState -Key 'badclear' -Path $dir -MaxAge (New-TimeSpan -Minutes 5) `
        -WarningVariable warnings 3>$null

      (@($warnings) -join ' ') | Should -BeLike `
        "Clear-PrtgSensorState: state file '*badclear.clixml' is unreadable and will be deleted. (*)"
      # The clause promises deletion, so the promise is asserted alongside the wording.
      Test-Path -LiteralPath $file | Should -BeFalse
    }

    It 'Use-PrtgCachedResult says the cache file is refetched' {
      Set-Content -LiteralPath (Join-Path $dir 'badcache.clixml') -Value 'this is not clixml'

      $value = Use-PrtgCachedResult -Key 'badcache' -MaxAge (New-TimeSpan -Minutes 5) -Path $dir `
        -WarningVariable warnings 3>$null { 'refetched' }

      $value | Should -Be 'refetched'
      (@($warnings) -join ' ') | Should -BeLike `
        "Use-PrtgCachedResult: cache file '*badcache.clixml' is unreadable, refetching. (*)"
    }
  }

  Context 'malformed entries inside a readable file' {
    # One valid entry and two unusable ones, so the reported count discriminates: a warning that
    # merely said "some entries" would pass a looser assertion.
    BeforeEach {
      $script:MakePartialFile = {
        param([string]$Folder, [string]$Key)
        [void] (New-Item -ItemType Directory -Path $Folder -Force)
        @(
          [PSCustomObject]@{ Value = 'good'; Timestamp = [DateTime]::UtcNow }
          [PSCustomObject]@{ Value = 'no timestamp property' }
          'not an entry object at all'
        ) | Export-Clixml -LiteralPath (Join-Path $Folder "$Key.clixml") -Depth 5
      }
    }

    It 'Save-PrtgSensorState reports the dropped count for a state file' {
      & $script:MakePartialFile $dir 'partsave'

      Save-PrtgSensorState -Key 'partsave' -Value 'new' -Path $dir -WarningVariable warnings 3>$null

      (@($warnings) -join ' ') | Should -BeLike `
        "Save-PrtgSensorState: state file '*partsave.clixml' had 2 malformed entries (corrupted on disk), ignoring them."
    }

    It 'Get-PrtgSensorState reports the dropped count for a state file' {
      & $script:MakePartialFile $dir 'partget'

      Get-PrtgSensorState -Key 'partget' -Path $dir -WarningVariable warnings 3>$null | Out-Null

      (@($warnings) -join ' ') | Should -BeLike `
        "Get-PrtgSensorState: state file '*partget.clixml' had 2 malformed entries (corrupted on disk), ignoring them."
    }

    It 'Clear-PrtgSensorState reports the dropped count for a state file' {
      & $script:MakePartialFile $dir 'partclear'

      Clear-PrtgSensorState -Key 'partclear' -Path $dir -MaxAge (New-TimeSpan -Hours 1) `
        -WarningVariable warnings 3>$null

      (@($warnings) -join ' ') | Should -BeLike `
        "Clear-PrtgSensorState: state file '*partclear.clixml' had 2 malformed entries (corrupted on disk), ignoring them."
    }

    It 'Use-PrtgCachedResult reports the dropped count for a cache file' {
      & $script:MakePartialFile $dir 'partcache'

      $value = Use-PrtgCachedResult -Key 'partcache' -MaxAge (New-TimeSpan -Minutes 5) -Path $dir `
        -WarningVariable warnings 3>$null { 'refetched' }

      $value | Should -Be 'good'
      (@($warnings) -join ' ') | Should -BeLike `
        "Use-PrtgCachedResult: cache file '*partcache.clixml' had 2 malformed entries (corrupted on disk), ignoring them."
    }
  }
}

Describe 'Get-PrtgSensorState names one newest entry on both paths' {
  BeforeAll {
    # A history whose raw timestamp comparison and whose UTC comparison point opposite ways,
    # whichever sign the host's offset has. 'stale' is out of range for any plausible -MaxAge.
    function New-MixedKindHistory {
      [OutputType([PSCustomObject])]
      param([string]$Folder, [string]$Key)

      [void] (New-Item -ItemType Directory -Path $Folder -Force)
      $utcOffset = [TimeZoneInfo]::Local.GetUtcOffset([DateTime]::UtcNow)
      $anchor = [DateTime]::UtcNow
      $localRaw = [DateTime]::SpecifyKind($anchor.AddTicks([long]($utcOffset.Ticks / 2)), [DateTimeKind]::Local)

      @(
        [PSCustomObject]@{ Value = 'stale'; Timestamp = $anchor.AddDays(-10) }
        [PSCustomObject]@{ Value = 'utc-marked'; Timestamp = $anchor }
        [PSCustomObject]@{ Value = 'local-marked'; Timestamp = $localRaw }
      ) | Export-Clixml -LiteralPath (Join-Path $Folder "$Key.clixml") -Depth 5

      [PSCustomObject]@{
        Offset = $utcOffset
        Newest = if ($utcOffset.Ticks -gt 0) { 'utc-marked' } else { 'local-marked' }
      }
    }
  }

  BeforeEach { $dir = New-TestStore 'order' }

  It 'agrees with -Latest on a history holding both a UTC-marked and a local-marked timestamp' -Skip:$noUtcOffset {
    $expected = New-MixedKindHistory -Folder $dir -Key 'mixed'

    $fromHistory = @(Get-PrtgSensorState -Key 'mixed' -Path $dir)[0].Value
    $fromLatest = Get-PrtgSensorState -Key 'mixed' -Path $dir -Latest

    $fromHistory | Should -Be $fromLatest
    $fromHistory | Should -Be $expected.Newest
  }

  It 'filters by age and orders by the same clock' -Skip:$noUtcOffset {
    $expected = New-MixedKindHistory -Folder $dir -Key 'aged'
    $maxAge = New-TimeSpan -Days 1

    $kept = @(Get-PrtgSensorState -Key 'aged' -Path $dir -MaxAge $maxAge)

    $kept.Value | Should -Not -Contain 'stale'
    $kept[0].Value | Should -Be $expected.Newest
    Get-PrtgSensorState -Key 'aged' -Path $dir -MaxAge $maxAge -Latest | Should -Be $expected.Newest
  }

  It 'names the last-appended entry as newest when timestamps are identical' {
    # Two saves inside one clock tick are enough to produce this on an ordinary probe; five
    # entries because Sort-Object can happen to leave a shorter list in its input order.
    $tick = [DateTime]::UtcNow
    @(1..5 | ForEach-Object { [PSCustomObject]@{ Value = "e$_"; Timestamp = $tick } }) |
      Export-Clixml -LiteralPath (Join-Path $dir 'tie.clixml') -Depth 5

    @(Get-PrtgSensorState -Key 'tie' -Path $dir)[0].Value | Should -Be 'e5'
    Get-PrtgSensorState -Key 'tie' -Path $dir -Latest | Should -Be 'e5'
  }
}

Describe 'Corruption warnings cross the state lock frame' {
  # The warnings are raised one frame deeper than the cmdlet that owns them, so both ways an
  # operator controls them have to keep working through that frame. This is the silencing half.
  BeforeEach {
    $dir = New-TestStore 'suppress'
    foreach ($key in 'supsave', 'supget', 'supclear', 'supcache') {
      Set-Content -LiteralPath (Join-Path $dir "$key.clixml") -Value 'this is not clixml'
    }
  }

  It 'emits nothing on the warning stream under -WarningAction SilentlyContinue' {
    $records = @(
      & { Save-PrtgSensorState -Key 'supsave' -Value 1 -Path $dir -WarningAction SilentlyContinue } 3>&1
      & { Get-PrtgSensorState -Key 'supget' -Path $dir -WarningAction SilentlyContinue } 3>&1
      & { Clear-PrtgSensorState -Key 'supclear' -Path $dir -MaxAge (New-TimeSpan -Minutes 5) -WarningAction SilentlyContinue } 3>&1
      & { Use-PrtgCachedResult -Key 'supcache' -MaxAge (New-TimeSpan -Minutes 5) -Path $dir -WarningAction SilentlyContinue { 'v' } } 3>&1
    ) | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }

    @($records).Count | Should -Be 0
  }
}
