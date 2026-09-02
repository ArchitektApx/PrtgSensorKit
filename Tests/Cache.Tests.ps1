BeforeAll {
  . $PSScriptRoot/_TestHelpers.ps1
  Import-ModuleUnderTest

  $script:FiveMinutes = New-TimeSpan -Minutes 5
}

Describe 'Use-PrtgCachedResult hit and miss' {
  BeforeEach { $dir = New-TestStore 'cache' }

  It 'runs the block on a miss, persists the result, and returns it' {
    $counter = @{ n = 0 }
    $value = Use-PrtgCachedResult -Key 'k' -MaxAge $script:FiveMinutes -Path $dir { $counter.n++; 'fresh' }
    $value | Should -Be 'fresh'
    $counter.n | Should -Be 1
    Test-Path (Join-Path $dir 'k.clixml') | Should -BeTrue
  }

  It 'serves a hit within MaxAge without invoking the block' {
    $counter = @{ n = 0 }
    [void] (Use-PrtgCachedResult -Key 'k' -MaxAge $script:FiveMinutes -Path $dir { $counter.n++; 'fresh' })
    $second = Use-PrtgCachedResult -Key 'k' -MaxAge $script:FiveMinutes -Path $dir { $counter.n++; 'refetched' }
    $second | Should -Be 'fresh'
    $counter.n | Should -Be 1
  }

  It 'refetches when the entry is older than MaxAge' {
    Save-PrtgSensorState -Key 'k' -Value 'stale' -Path $dir
    $value = Use-PrtgCachedResult -Key 'k' -MaxAge (New-TimeSpan -Seconds 0) -Path $dir { 'refetched' }
    $value | Should -Be 'refetched'
  }

  It 'caches and serves a $null result' {
    $counter = @{ n = 0 }
    $first = Use-PrtgCachedResult -Key 'nullable' -MaxAge $script:FiveMinutes -Path $dir { $counter.n++; $null }
    $second = Use-PrtgCachedResult -Key 'nullable' -MaxAge $script:FiveMinutes -Path $dir { $counter.n++; 'never' }
    $first | Should -BeNullOrEmpty
    $second | Should -BeNullOrEmpty
    $counter.n | Should -Be 1
  }

  It 'lets the block see caller-scope variables' {
    $flavor = 'vanilla'
    Use-PrtgCachedResult -Key 'scope' -MaxAge $script:FiveMinutes -Path $dir { $flavor } | Should -Be 'vanilla'
  }

  It 'rehydrates structured values as property bags on a hit' {
    [void] (Use-PrtgCachedResult -Key 'obj' -MaxAge $script:FiveMinutes -Path $dir {
      [PSCustomObject]@{ queueDepth = 17; status = 'ok' }
    })
    $hit = Use-PrtgCachedResult -Key 'obj' -MaxAge $script:FiveMinutes -Path $dir { 'never' }
    $hit.queueDepth | Should -Be 17
    $hit.status | Should -Be 'ok'
  }

  It 'validates the key pattern' {
    { Use-PrtgCachedResult -Key 'bad/key' -MaxAge $script:FiveMinutes -Path $dir { 1 } } | Should -Throw
  }
}

Describe 'Use-PrtgCachedResult error handling' {
  BeforeEach { $dir = New-TestStore 'cache' }

  It 'propagates a throwing block and keeps the stale entry' {
    Save-PrtgSensorState -Key 'k' -Value 'stale' -Path $dir
    { Use-PrtgCachedResult -Key 'k' -MaxAge (New-TimeSpan -Seconds 0) -Path $dir { throw 'fetch failed' } } |
      Should -Throw '*fetch failed*'
    Get-PrtgSensorState -Key 'k' -Path $dir -Latest | Should -Be 'stale'
  }
}

Describe 'Use-PrtgCachedResult and the state tooling' {
  BeforeEach { $dir = New-TestStore 'cache' }

  It 'writes entries Get-PrtgSensorState can read' {
    [void] (Use-PrtgCachedResult -Key 'shared' -MaxAge $script:FiveMinutes -Path $dir { 42 })
    Get-PrtgSensorState -Key 'shared' -Path $dir -Latest | Should -Be 42
  }

  It 'is cleared by Clear-PrtgSensorState' {
    $counter = @{ n = 0 }
    [void] (Use-PrtgCachedResult -Key 'clearable' -MaxAge $script:FiveMinutes -Path $dir { $counter.n++; 'v1' })
    Clear-PrtgSensorState -Key 'clearable' -Path $dir
    [void] (Use-PrtgCachedResult -Key 'clearable' -MaxAge $script:FiveMinutes -Path $dir { $counter.n++; 'v2' })
    $counter.n | Should -Be 2
  }
}

Describe 'Use-PrtgCachedResult locking' {
  BeforeEach { $dir = New-TestStore 'cache' }

  It 'throws on lock timeout instead of fetching' {
    $handle = Get-TestLockHandle (Join-Path $dir 'held.clixml.lock')
    try {
      { Use-PrtgCachedResult -Key 'held' -MaxAge $script:FiveMinutes -Path $dir -TimeoutSeconds 0 { 'x' } } |
        Should -Throw '*lock*'
    } finally {
      $handle.Dispose()
    }
  }

  It 'bypasses the lock with -Force' {
    $handle = Get-TestLockHandle (Join-Path $dir 'forced.clixml.lock')
    try {
      Use-PrtgCachedResult -Key 'forced' -MaxAge $script:FiveMinutes -Path $dir -Force { 'anyway' } | Should -Be 'anyway'
    } finally {
      $handle.Dispose()
    }
  }

  It 'holds the lock across the fetch so a concurrent caller hits the fresh entry (herd test)' {
    $manifest = Get-ModuleUnderTestPath
    $marker = Join-Path $dir 'fetches.txt'
    $ps = [PowerShell]::Create()
    [void] $ps.AddScript(@"
Import-Module '$manifest' -Force
Use-PrtgCachedResult -Key 'herd' -MaxAge (New-TimeSpan -Minutes 5) -Path '$dir' {
  Start-Sleep -Seconds 2
  Add-Content -LiteralPath '$marker' -Value 'fetch'
  'from-first'
}
"@)
    $async = $ps.BeginInvoke()

    # Wait until the concurrent runspace actually holds the lock (module import is slow),
    # then race it: this caller must block on the lock and come back with the FIRST
    # caller's result, not run its own fetch.
    $lockFile = Join-Path $dir 'herd.clixml.lock'
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    $held = $false
    while (-not $held -and [DateTime]::UtcNow -lt $deadline) {
      if (Test-Path -LiteralPath $lockFile) {
        try {
          $probe = Get-TestLockHandle $lockFile
          $probe.Dispose()
        } catch [System.IO.IOException] {
          $held = $true
        }
      }
      if (-not $held) { Start-Sleep -Milliseconds 100 }
    }
    $held | Should -BeTrue

    $counter = @{ n = 0 }
    $second = Use-PrtgCachedResult -Key 'herd' -MaxAge $script:FiveMinutes -Path $dir { $counter.n++; 'from-second' }
    [void] $ps.EndInvoke($async)
    $ps.Dispose()

    $second | Should -Be 'from-first'
    $counter.n | Should -Be 0
    @(Get-Content -LiteralPath $marker).Count | Should -Be 1
  }
}

Describe 'Use-PrtgCachedResult resilience' {
  BeforeEach { $dir = New-TestStore 'cache' }

  It 'warns and refetches when the cache file is corrupt' {
    Set-Content -LiteralPath (Join-Path $dir 'corrupt.clixml') -Value 'this is not clixml'
    $value = Use-PrtgCachedResult -Key 'corrupt' -MaxAge $script:FiveMinutes -Path $dir -WarningVariable warnings 3>$null { 'refetched' }
    $value | Should -Be 'refetched'
    @($warnings) -join ' ' | Should -BeLike '*unreadable*'
  }

  It 'keeps the previous cached value when the refresh write fails part-way' {
    # Export-Clixml truncates before it writes, so refreshing straight into the cache file would
    # corrupt the entry every sensor on the probe shares. The refresh writes a temp file first.
    Use-PrtgCachedResult -Key 'atomic' -MaxAge ([TimeSpan]::FromMilliseconds(1)) -Path $dir { 'original' } | Out-Null
    Start-Sleep -Milliseconds 20
    Mock -CommandName Export-Clixml -ModuleName PrtgSensorKit -MockWith { throw 'simulated write failure' }
    { Use-PrtgCachedResult -Key 'atomic' -MaxAge ([TimeSpan]::FromMilliseconds(1)) -Path $dir -ErrorAction Stop { 'replacement' } } |
      Should -Throw
    (Import-Clixml -LiteralPath (Join-Path $dir 'atomic.clixml')).Value | Should -Be 'original'
  }

  It 'leaves no temp files behind on a successful refresh' {
    Use-PrtgCachedResult -Key 'notemp' -MaxAge $script:FiveMinutes -Path $dir { 'v' } | Out-Null
    @(Get-ChildItem -LiteralPath $dir -Filter '*.tmp') | Should -BeNullOrEmpty
  }

  It 'leaves a fresh temp file alone and clears an old one' {
    # -Force skips the lock, so two instances can be in the write at once; only a temp file old
    # enough to be a leftover from a killed run is removed.
    $fresh = Join-Path $dir 'sweep.clixml.aaa.tmp'
    $old = Join-Path $dir 'sweep.clixml.bbb.tmp'
    Set-Content -LiteralPath $fresh -Value 'in flight'
    Set-Content -LiteralPath $old -Value 'leftover'
    (Get-Item -LiteralPath $old).LastWriteTimeUtc = [DateTime]::UtcNow.AddHours(-2)
    Use-PrtgCachedResult -Key 'sweep' -MaxAge $script:FiveMinutes -Path $dir { 'v' } | Out-Null
    Test-Path -LiteralPath $fresh | Should -BeTrue
    Test-Path -LiteralPath $old | Should -BeFalse
  }

  It 'honours -Depth instead of always exporting at the hardcoded default' {
    # Depth only bites on rich .NET objects (a FileInfo's Directory, a CIM instance), not on
    # PSCustomObject trees, so a FileInfo is what makes the parameter observable: at depth 1 its
    # Directory flattens to a string, at the default it survives as an object.
    $probe = New-Item -ItemType File -Path (Join-Path $dir 'probe.txt')
    Use-PrtgCachedResult -Key 'shallow' -MaxAge $script:FiveMinutes -Path $dir -Depth 1 { $probe } | Out-Null
    $flat = Use-PrtgCachedResult -Key 'shallow' -MaxAge $script:FiveMinutes -Path $dir { 'never' }
    $flat.Directory | Should -BeOfType [string]

    Use-PrtgCachedResult -Key 'full' -MaxAge $script:FiveMinutes -Path $dir { $probe } | Out-Null
    $kept = Use-PrtgCachedResult -Key 'full' -MaxAge $script:FiveMinutes -Path $dir { 'never' }
    $kept.Directory | Should -Not -BeOfType [string]
  }

  It 'serves the newest entry when the file holds a history' {
    Save-PrtgSensorState -Key 'hist' -Value 'older' -Path $dir
    Start-Sleep -Milliseconds 50
    Save-PrtgSensorState -Key 'hist' -Value 'newer' -Path $dir
    Use-PrtgCachedResult -Key 'hist' -MaxAge $script:FiveMinutes -Path $dir { 'never' } | Should -Be 'newer'
  }
}

Describe 'Use-PrtgCachedResult timestamp tie-breaking' {
  It 'serves the last-appended entry when timestamps tie' {
    $dir = New-TestStore 'cache'
    $ts = [DateTime]::UtcNow
    @(
      [PSCustomObject]@{ Value = 'older'; Timestamp = $ts }
      [PSCustomObject]@{ Value = 'newer'; Timestamp = $ts }
    ) | Export-Clixml -LiteralPath (Join-Path $dir 'tie.clixml')
    Use-PrtgCachedResult -Key 'tie' -MaxAge $script:FiveMinutes -Path $dir { 'refetched' } | Should -Be 'newer'
  }
}

Describe 'Use-PrtgCachedResult -SkipNullCache' {
  BeforeEach { $dir = New-TestStore 'cache-null' }

  It 'refetches instead of serving a cached $null' {
    $counter = @{ n = 0 }
    $first = Use-PrtgCachedResult -Key 'nullable' -MaxAge $script:FiveMinutes -Path $dir -SkipNullCache { $counter.n++; $null }
    $second = Use-PrtgCachedResult -Key 'nullable' -MaxAge $script:FiveMinutes -Path $dir -SkipNullCache { $counter.n++; 'fresh' }
    $first  | Should -BeNullOrEmpty
    $second | Should -Be 'fresh'
    $counter.n | Should -Be 2
  }

  It 'does not write a $null result to the cache file' {
    Use-PrtgCachedResult -Key 'nowrite' -MaxAge $script:FiveMinutes -Path $dir -SkipNullCache { $null } | Out-Null
    Test-Path -LiteralPath (Join-Path $dir 'nowrite.clixml') | Should -BeFalse
  }

  It 'caches a non-null result normally' {
    $counter = @{ n = 0 }
    Use-PrtgCachedResult -Key 'real' -MaxAge $script:FiveMinutes -Path $dir -SkipNullCache { $counter.n++; 'value' } | Out-Null
    Use-PrtgCachedResult -Key 'real' -MaxAge $script:FiveMinutes -Path $dir -SkipNullCache { $counter.n++; 'never' } |
      Should -Be 'value'
    $counter.n | Should -Be 1
  }

  It 'still caches a stored 0 and empty string' {
    $counter = @{ n = 0 }
    Use-PrtgCachedResult -Key 'zero' -MaxAge $script:FiveMinutes -Path $dir -SkipNullCache { $counter.n++; 0 } | Out-Null
    Use-PrtgCachedResult -Key 'zero' -MaxAge $script:FiveMinutes -Path $dir -SkipNullCache { $counter.n++; 99 } |
      Should -Be 0
    Use-PrtgCachedResult -Key 'empty' -MaxAge $script:FiveMinutes -Path $dir -SkipNullCache { $counter.n++; '' } | Out-Null
    Use-PrtgCachedResult -Key 'empty' -MaxAge $script:FiveMinutes -Path $dir -SkipNullCache { $counter.n++; 'x' } |
      Should -BeExactly ''
    $counter.n | Should -Be 2
  }

  It 'leaves an existing stale entry in place when the fetch returns $null' {
    Save-PrtgSensorState -Key 'keepstale' -Value 'stale' -Path $dir
    Use-PrtgCachedResult -Key 'keepstale' -MaxAge (New-TimeSpan -Seconds 0) -Path $dir -SkipNullCache { $null } |
      Should -BeNullOrEmpty
    Get-PrtgSensorState -Key 'keepstale' -Path $dir -Latest | Should -Be 'stale'
  }

  It 'serves a cached $null when the switch is absent (default behaviour unchanged)' {
    $counter = @{ n = 0 }
    Use-PrtgCachedResult -Key 'default' -MaxAge $script:FiveMinutes -Path $dir { $counter.n++; $null } | Out-Null
    Use-PrtgCachedResult -Key 'default' -MaxAge $script:FiveMinutes -Path $dir { $counter.n++; 'never' } |
      Should -BeNullOrEmpty
    $counter.n | Should -Be 1
  }
}
