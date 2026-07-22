BeforeAll {
  . $PSScriptRoot/_TestHelpers.ps1
  Import-BuiltPrtgModule

  $script:FiveMinutes = New-TimeSpan -Minutes 5
}

Describe 'Use-PrtgCachedResult hit and miss' {
  BeforeEach { $dir = Join-Path $TestDrive "cache-$(Get-Random)" }

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
  BeforeEach { $dir = Join-Path $TestDrive "cache-$(Get-Random)" }

  It 'propagates a throwing block and keeps the stale entry' {
    Save-PrtgSensorState -Key 'k' -Value 'stale' -Path $dir
    { Use-PrtgCachedResult -Key 'k' -MaxAge (New-TimeSpan -Seconds 0) -Path $dir { throw 'fetch failed' } } |
      Should -Throw '*fetch failed*'
    Get-PrtgSensorState -Key 'k' -Path $dir -Latest | Should -Be 'stale'
  }
}

Describe 'Use-PrtgCachedResult and the state tooling' {
  BeforeEach { $dir = Join-Path $TestDrive "cache-$(Get-Random)" }

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
  BeforeEach { $dir = Join-Path $TestDrive "cache-$(Get-Random)" }

  It 'throws on lock timeout instead of fetching' {
    [void] (New-Item -ItemType Directory -Path $dir)
    $handle = Get-TestLockHandle (Join-Path $dir 'held.clixml.lock')
    try {
      { Use-PrtgCachedResult -Key 'held' -MaxAge $script:FiveMinutes -Path $dir -TimeoutSeconds 0 { 'x' } } |
        Should -Throw '*lock*'
    } finally {
      $handle.Dispose()
    }
  }

  It 'bypasses the lock with -Force' {
    [void] (New-Item -ItemType Directory -Path $dir)
    $handle = Get-TestLockHandle (Join-Path $dir 'forced.clixml.lock')
    try {
      Use-PrtgCachedResult -Key 'forced' -MaxAge $script:FiveMinutes -Path $dir -Force { 'anyway' } | Should -Be 'anyway'
    } finally {
      $handle.Dispose()
    }
  }

  It 'holds the lock across the fetch so a concurrent caller hits the fresh entry (herd test)' {
    $manifest = Get-BuiltPrtgManifest
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
  BeforeEach { $dir = Join-Path $TestDrive "cache-$(Get-Random)" }

  It 'warns and refetches when the cache file is corrupt' {
    [void] (New-Item -ItemType Directory -Path $dir)
    Set-Content -LiteralPath (Join-Path $dir 'corrupt.clixml') -Value 'this is not clixml'
    $value = Use-PrtgCachedResult -Key 'corrupt' -MaxAge $script:FiveMinutes -Path $dir -WarningVariable warnings 3>$null { 'refetched' }
    $value | Should -Be 'refetched'
    @($warnings) -join ' ' | Should -BeLike '*unreadable*'
  }

  It 'serves the newest entry when the file holds a history' {
    Save-PrtgSensorState -Key 'hist' -Value 'older' -Path $dir
    Start-Sleep -Milliseconds 50
    Save-PrtgSensorState -Key 'hist' -Value 'newer' -Path $dir
    Use-PrtgCachedResult -Key 'hist' -MaxAge $script:FiveMinutes -Path $dir { 'never' } | Should -Be 'newer'
  }
}
