BeforeAll {
  . $PSScriptRoot/_TestHelpers.ps1
  Import-BuiltPrtgModule
}

$onWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows

Describe 'Private helpers' {
  It 'Test-PrtgWindows reflects the host edition' {
    $expected = ($PSVersionTable.PSEdition -eq 'Desktop') -or [bool]$IsWindows
    (InModuleScope PrtgSensorKit { Test-PrtgWindows }) | Should -Be $expected
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
