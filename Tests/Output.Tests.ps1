BeforeAll {
  . $PSScriptRoot/_TestHelpers.ps1
  Import-BuiltPrtgModule
}

Describe 'Sensor message' {
  BeforeEach { Clear-PrtgOutput }

  It 'round-trips via Set/Get-PrtgMessage' {
    Set-PrtgMessage 'all good'
    Get-PrtgMessage | Should -Be 'all good'
  }

  It 'strips # from the message' {
    Set-PrtgMessage 'has #hash inside'
    Get-PrtgMessage | Should -Not -Match '#'
  }

  It 'truncates the message to 2000 characters' {
    Set-PrtgMessage ('x' * 5000)
    (Get-PrtgMessage).Length | Should -BeLessOrEqual 2000
  }

  It 'returns empty string for an empty/null message' {
    Set-PrtgMessage ''
    Get-PrtgMessage | Should -BeExactly ''
  }
}

Describe 'Write-PrtgOutput' {
  BeforeEach { Clear-PrtgOutput }

  It 'emits valid JSON with the PRTG shape' {
    New-PrtgChannel -Channel 'A' -Value 1 | Add-PrtgChannel
    Set-PrtgMessage 'ok'
    $obj = Write-PrtgOutput | ConvertFrom-Json
    $obj.prtg.result.Count | Should -Be 1
    $obj.prtg.text | Should -Be 'ok'
  }

  It 'does not leak PSTypeName into the JSON' {
    New-PrtgChannel -Channel 'A' -Value 1 | Add-PrtgChannel
    (Write-PrtgOutput) | Should -Not -Match 'PSTypeName|PrtgSensorKit\.Channel'
  }
}

Describe 'State management' {
  It 'Clear-PrtgOutput resets channels and text' {
    New-PrtgChannel -Channel 'A' -Value 1 | Add-PrtgChannel
    Set-PrtgMessage 'stuff'
    Clear-PrtgOutput
    $obj = Write-PrtgOutput | ConvertFrom-Json
    $obj.prtg.result.Count | Should -Be 0
    $obj.prtg.text | Should -BeNullOrEmpty
  }

  It 'Set-PrtgOutput replaces the whole object' {
    $custom = [PSCustomObject]@{ prtg = [PSCustomObject]@{
      result = [System.Collections.ArrayList]@(); text = 'replaced' } }
    Set-PrtgOutput $custom
    Get-PrtgMessage | Should -Be 'replaced'
  }

  It 'does not pollute the global scope on import' {
    Get-Variable -Name OutputObject -Scope Global -ErrorAction SilentlyContinue |
      Should -BeNullOrEmpty
  }
}
