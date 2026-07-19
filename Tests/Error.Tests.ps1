BeforeAll {
  . $PSScriptRoot/_TestHelpers.ps1
  Import-BuiltPrtgModule
}

Describe 'Write-PrtgError' {
  It 'emits a PRTG error response for -ErrorString' {
    $obj = (Write-PrtgError -ErrorString 'boom') | ConvertFrom-Json
    $obj.prtg.error | Should -Be 1
    $obj.prtg.text  | Should -Be 'boom'
  }

  It 'sanitizes # in -ErrorString' {
    $obj = (Write-PrtgError -ErrorString 'bad #thing') | ConvertFrom-Json
    $obj.prtg.text | Should -Not -Match '#'
  }

  It 'builds an error from a caught ErrorRecord and sanitizes it' {
    $rec = try { throw 'kaboom #99' } catch { $_ }
    $obj = ($rec | Write-PrtgError) | ConvertFrom-Json
    $obj.prtg.error | Should -Be 1
    $obj.prtg.text  | Should -Match 'kaboom'
    $obj.prtg.text  | Should -Not -Match '#'
  }

  It 'emits a single response even if multiple errors are piped (one error per sensor)' {
    $errs = 1..2 | ForEach-Object { try { throw "e$_" } catch { $_ } }
    ($errs | Write-PrtgError | Measure-Object).Count | Should -Be 1
  }
}
