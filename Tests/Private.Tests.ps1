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

Describe 'Invoke-PrtgStateLock parameter names cannot shadow a caller block variable' {
  It 'exposes no ordinary parameter name' {
    # The block runs via '& $PrtgLockBlock' and resolves unqualified names up the DYNAMIC
    # chain - this frame first - so any unprefixed name here silently shadows the caller's
    # variable of the same name. The 'PrtgLock' prefix is the only thing preventing that,
    # and this test is what keeps a future parameter from reopening the hole.
    InModuleScope PrtgSensorKit {
      $names = (Get-Command Invoke-PrtgStateLock).Parameters.Keys
      foreach ($leaky in 'TimeoutSeconds', 'Force', 'ScriptBlock', 'LockFile', 'DeleteLockOnRelease') {
        $names | Should -Not -Contain $leaky
      }
    }
  }

  It 'has every non-common parameter prefixed PrtgLock' {
    InModuleScope PrtgSensorKit {
      $common = [System.Management.Automation.PSCmdlet]::CommonParameters
      $own = (Get-Command Invoke-PrtgStateLock).Parameters.Keys | Where-Object { $_ -notin $common }
      foreach ($name in $own) {
        $name | Should -BeLike 'PrtgLock*'
      }
    }
  }
}
