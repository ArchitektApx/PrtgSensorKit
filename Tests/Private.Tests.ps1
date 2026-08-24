BeforeAll {
  . $PSScriptRoot/_TestHelpers.ps1
  Import-BuiltPrtgModule
}

# Dot-sourced at top level as well as in BeforeAll: -Skip: is evaluated at DISCOVERY time.
. $PSScriptRoot/_TestHelpers.ps1
$onWindows = Test-OnWindowsHost

Describe 'Private helpers' {
  It 'Test-PrtgWindows reflects the host edition' {
    $expected = ($PSVersionTable.PSEdition -eq 'Desktop') -or [bool]$IsWindows
    (InModuleScope PrtgSensorKit { Test-PrtgWindows }) | Should -Be $expected
  }

  It 'Get-PrtgNewestEntry returns $null for an empty history' {
    # The callers only reach it with entries, so this guard has no coverage through them.
    InModuleScope PrtgSensorKit {
      Get-PrtgNewestEntry -Entries @() | Should -BeNullOrEmpty
      Get-PrtgNewestEntry -Entries $null | Should -BeNullOrEmpty
    }
  }

  It 'Get-PrtgNewestEntry breaks a timestamp tie in favour of the later entry' {
    InModuleScope PrtgSensorKit {
      $ts = [DateTime]::UtcNow
      $newest = Get-PrtgNewestEntry -Entries @(
        [PSCustomObject]@{ Value = 'older'; Timestamp = $ts }
        [PSCustomObject]@{ Value = 'newer'; Timestamp = $ts }
      )
      $newest.Value | Should -Be 'newer'
    }
  }

  It 'Format-PrtgMessage strips # and truncates to 2000' {
    InModuleScope PrtgSensorKit {
      (Format-PrtgMessage 'a#b') | Should -Be 'ab'
      (Format-PrtgMessage ('y' * 3000)).Length | Should -Be 2000
      (Format-PrtgMessage '') | Should -BeExactly ''
    }
  }
}

# The pwsh-absent branch of Restart-InPwsh is reachable in-process only on Desktop edition, by
# mocking away pwsh. The success branch relaunches and calls exit, so it stays covered by the
# child-process relaunch tests in Restart.Tests.ps1 instead.
Describe 'Restart-InPwsh when pwsh is absent (Windows)' -Tag 'Windows' -Skip:(-not $onWindows) {
  It 'warns and returns without relaunching' {
    InModuleScope PrtgSensorKit {
      Mock Get-Command -MockWith { $null } -ParameterFilter { $Name -eq 'pwsh' }
      Restart-InPwsh -WarningAction SilentlyContinue | Should -BeNullOrEmpty
    }
  }
}

Describe 'Test-PrtgNumeric' {
  It 'is true for every built-in numeric type' {
    InModuleScope PrtgSensorKit {
      foreach ($v in @([byte]1, [sbyte]1, [int16]1, [uint16]1, [int32]1, [uint32]1,
                       [int64]1, [uint64]1, [single]1, [double]1, [decimal]1)) {
        Test-PrtgNumeric $v | Should -BeTrue -Because "$($v.GetType().Name) is numeric"
      }
    }
  }

  It 'is false for non-numeric value types and for null' {
    InModuleScope PrtgSensorKit {
      Test-PrtgNumeric $true              | Should -BeFalse
      Test-PrtgNumeric 'x'                | Should -BeFalse
      Test-PrtgNumeric ([datetime]::Now)  | Should -BeFalse
      Test-PrtgNumeric ([timespan]::Zero) | Should -BeFalse
      Test-PrtgNumeric ([guid]::Empty)    | Should -BeFalse
      Test-PrtgNumeric ([char]'a')        | Should -BeFalse
      Test-PrtgNumeric $null              | Should -BeFalse
    }
  }
}

Describe 'Block-passing frame parameter names cannot shadow a caller block variable' {
  # A function that invokes a caller-supplied block is a frame in the DYNAMIC scope chain the
  # block resolves through - this frame first - so any unprefixed name it declares silently
  # shadows the calling cmdlet's variable of the same name. The prefix is the only thing
  # preventing that, and these two assertions are what keep a future parameter from reopening
  # the hole. Every such frame in the module belongs in the tables below.
  It 'exposes no ordinary parameter name' {
    InModuleScope PrtgSensorKit {
      $frames = @(
        @{ Name = 'Invoke-PrtgStateLock'
          Leaky = @('TimeoutSeconds', 'Force', 'ScriptBlock', 'LockFile', 'DeleteLockOnRelease')
        }
        @{ Name = 'Export-PrtgClixmlAtomic'
          Leaky = @('InputObject', 'LiteralPath', 'Depth', 'Path', 'File', 'Folder', 'BeforeWrite', 'AfterSwap')
        }
      )
      foreach ($frame in $frames) {
        $names = (Get-Command $frame.Name).Parameters.Keys
        foreach ($leaky in $frame.Leaky) {
          $names | Should -Not -Contain $leaky -Because "$($frame.Name) would shadow a block's own `$$leaky"
        }
      }
    }
  }

  It 'has every non-common parameter carrying its frame prefix' {
    InModuleScope PrtgSensorKit {
      $common = [System.Management.Automation.PSCmdlet]::CommonParameters
      $frames = @(
        @{ Name = 'Invoke-PrtgStateLock'; Prefix = 'PrtgLock' }
        @{ Name = 'Export-PrtgClixmlAtomic'; Prefix = 'PrtgWrite' }
      )
      foreach ($frame in $frames) {
        $own = (Get-Command $frame.Name).Parameters.Keys | Where-Object { $_ -notin $common }
        foreach ($name in $own) {
          $name | Should -BeLike "$($frame.Prefix)*" -Because "$($frame.Name) invokes a caller-supplied block"
        }
      }
    }
  }
}

Describe 'Get-PrtgSecretPath' {
  # The whole point of the resolver: through the public seam this behaviour is reachable only via
  # DPAPI-dependent cmdlets, which is why parts of the secret suite pass only on the VM after a
  # console logon. These three need no DPAPI, no console logon, and no secret ever saved.
  It 'returns the ProgramData default on Windows' {
    InModuleScope PrtgSensorKit {
      Mock Test-PrtgWindows -MockWith { $true }
      $saved = $env:ProgramData
      try {
        $env:ProgramData = Join-Path ([System.IO.Path]::GetTempPath()) 'ProgramDataProbe'
        Get-PrtgSecretPath | Should -Be (Join-Path $env:ProgramData 'PrtgSensorKit\Secrets')
      } finally {
        $env:ProgramData = $saved
      }
    }
  }

  It 'returns the temp-folder default off Windows' {
    InModuleScope PrtgSensorKit {
      Mock Test-PrtgWindows -MockWith { $false }
      Get-PrtgSecretPath |
        Should -Be (Join-Path ([System.IO.Path]::GetTempPath()) 'PrtgSensorKit/Secrets')
    }
  }

  It 'passes an explicit path through untouched, relative one included' {
    InModuleScope PrtgSensorKit {
      Get-PrtgSecretPath -Path '/tmp/explicit-secrets' | Should -BeExactly '/tmp/explicit-secrets'
      # Not resolved here on purpose: resolving would turn stored paths absolute and change the
      # paths printed in the not-found and corrupt messages.
      Get-PrtgSecretPath -Path 'relative/secrets' | Should -BeExactly 'relative/secrets'
    }
  }

  It 'does not create the folder it resolves' {
    InModuleScope PrtgSensorKit {
      $probe = Join-Path ([System.IO.Path]::GetTempPath()) "secretpath-$(Get-Random)"
      Get-PrtgSecretPath -Path $probe | Out-Null
      Test-Path -LiteralPath $probe | Should -BeFalse
    }
  }
}
