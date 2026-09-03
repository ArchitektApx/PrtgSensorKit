# Tests for the test harness itself, not for the module. Imports nothing.

Describe 'Test runner' {
  # Tools/tests.ps1 lowers $ErrorActionPreference to 'Continue' around Invoke-Pester. Under
  # 'Stop' the Write-Error below terminates the function instead of writing to the stream.
  It 'lets a command write a non-terminating error to the stream' {
    function Invoke-ErrorWriter { [CmdletBinding()] param() Write-Error 'expected'; 'result' }
    $out = Invoke-ErrorWriter 2>&1
    $errors = @($out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    $errors.Count | Should -Be 1
    $errors[0].ToString() | Should -Match 'expected'
    $out | Where-Object { $_ -eq 'result' } | Should -Not -BeNullOrEmpty
  }
}
