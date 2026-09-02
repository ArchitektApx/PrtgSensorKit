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

  It 'accepts the message by name' {
    Set-PrtgMessage -Text 'direct'
    Get-PrtgMessage | Should -Be 'direct'
  }

  It 'sets an empty message when called with no argument' {
    Set-PrtgMessage 'earlier'
    Set-PrtgMessage
    Get-PrtgMessage | Should -BeExactly ''
  }

  It 'accepts one string from the pipeline' {
    'hello' | Set-PrtgMessage
    Get-PrtgMessage | Should -Be 'hello'
  }

  It 'keeps the last of several piped strings' {
    'a', 'b' | Set-PrtgMessage
    Get-PrtgMessage | Should -Be 'b'
  }

  It 'leaves the message untouched on an empty pipeline' {
    Set-PrtgMessage 'kept'
    @() | Set-PrtgMessage
    Get-PrtgMessage | Should -Be 'kept'
  }

  It 'sets an empty message from a piped null item' {
    Set-PrtgMessage 'earlier'
    $null | Set-PrtgMessage
    Get-PrtgMessage | Should -BeExactly ''
  }

  It 'binds a piped object as its string form, not by property name' {
    [pscustomobject]@{ Text = 'x'; n = 1 } | Set-PrtgMessage
    Get-PrtgMessage | Should -Be '@{Text=x; n=1}'
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
  # Without this the leftover channel from the previous Describe carries over: the
  # uniqueness check in Add-PrtgChannel turns that cross-file state leak into a failure.
  BeforeEach { Clear-PrtgOutput }

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

Describe 'A null output document' {
  # Four consumers behave four different ways on a null document, and that is deliberate: the
  # two that fail today name what went wrong, and the two that are silent today stay silent,
  # because making a silent path throw could turn a sensor that is green today red on upgrade.
  AfterEach { Clear-PrtgOutput }

  It 'is accepted by Set-PrtgOutput without an error' {
    # Validating here instead would move the failure earlier, which is the behaviour change
    # the compatibility promise forbids.
    { Set-PrtgOutput $null } | Should -Not -Throw
  }

  It 'makes Add-PrtgChannel name the cause and itself' {
    Set-PrtgOutput $null
    $channel = New-PrtgChannel -Channel 'A' -Value 1
    { $channel | Add-PrtgChannel } | Should -Throw '*Add-PrtgChannel*output document is null*'
    { $channel | Add-PrtgChannel } | Should -Throw '*Set-PrtgOutput*'
  }

  It 'makes Set-PrtgMessage name the cause and itself' {
    Set-PrtgOutput $null
    { Set-PrtgMessage 'x' } | Should -Throw '*Set-PrtgMessage*output document is null*'
    { Set-PrtgMessage 'x' } | Should -Throw '*Clear-PrtgOutput*'
  }

  It 'makes Set-PrtgMessage name the cause and itself on piped input' {
    Set-PrtgOutput $null
    { 'x' | Set-PrtgMessage } | Should -Throw '*Set-PrtgMessage*output document is null*'
    { 'x' | Set-PrtgMessage } | Should -Throw '*Clear-PrtgOutput*'
  }

  It 'fails no earlier than it did before' {
    Set-PrtgOutput $null
    # New-PrtgChannel never touches the document, so it must still succeed.
    { New-PrtgChannel -Channel 'A' -Value 1 } | Should -Not -Throw

    # The channel-limit and duplicate checks still run against a null document without
    # throwing, so the named error is what surfaces rather than either of theirs.
    $failure = { New-PrtgChannel -Channel 'A' -Value 1 | Add-PrtgChannel } | Should -Throw -PassThru
    "$($failure.Exception.Message)" | Should -Not -Match 'maximum of 50 channels'
    "$($failure.Exception.Message)" | Should -Not -Match 'already added'
  }

  It 'leaves Get-PrtgMessage returning null silently' {
    Set-PrtgOutput $null
    $result = Get-PrtgMessage
    $result | Should -BeNullOrEmpty
  }

  It 'leaves Write-PrtgOutput emitting without failing' {
    Set-PrtgOutput $null
    $records = & { Write-PrtgOutput } 2>&1
    @($records | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) |
      Should -BeNullOrEmpty
    # What it emits differs by host: pwsh 7 serializes the literal 'null', Windows PowerShell
    # 5.1 emits nothing. Both are unchanged behaviour, so neither value is pinned here. What
    # matters is that it does not fail and does not invent a document.
    "$records" | Should -Not -Match 'prtg'
  }

  It 'recovers with Clear-PrtgOutput' {
    Set-PrtgOutput $null
    Clear-PrtgOutput
    { New-PrtgChannel -Channel 'A' -Value 1 | Add-PrtgChannel } | Should -Not -Throw
    (Write-PrtgOutput | ConvertFrom-Json).prtg.result.Count | Should -Be 1
  }
}

Describe 'One factory owns the output document shape' {
  It 'gives Clear-PrtgOutput and the import-time document the same shape' {
    # Imported fresh so the document under test is the one the module built at import time, and
    # read BEFORE Clear-PrtgOutput replaces it. Clearing first would compare one document with
    # itself, and the drift this guards against is exactly between those two.
    Import-BuiltPrtgModule
    $atImport = Write-PrtgOutput | ConvertFrom-Json

    Clear-PrtgOutput
    $afterClear = Write-PrtgOutput | ConvertFrom-Json

    foreach ($document in @($atImport, $afterClear)) {
      @($document.PSObject.Properties.Name) | Should -Be @('prtg')
      (@($document.prtg.PSObject.Properties.Name) | Sort-Object) -join ',' | Should -Be 'result,text'
      $document.prtg.text | Should -BeExactly ''
      @($document.prtg.result).Count | Should -Be 0
    }
  }

  It 'returns a fresh document each time, not a shared one' {
    Clear-PrtgOutput
    New-PrtgChannel -Channel 'A' -Value 1 | Add-PrtgChannel
    Clear-PrtgOutput
    (Write-PrtgOutput | ConvertFrom-Json).prtg.result.Count | Should -Be 0
  }
}
