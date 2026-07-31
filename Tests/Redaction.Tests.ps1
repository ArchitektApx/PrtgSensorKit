BeforeAll {
  . $PSScriptRoot/_TestHelpers.ps1
  Import-BuiltPrtgModule
}

AfterAll {
  # $script:PrtgRedactions is module scope and is never reset by the module itself, so a
  # secret registered here would mask text in every later test file of the same session.
  InModuleScope PrtgSensorKit { $script:PrtgRedactions.Clear() }
}

Describe 'Protect-PrtgSecretText masking rule' {
  BeforeEach {
    InModuleScope PrtgSensorKit { $script:PrtgRedactions.Clear() }
  }

  AfterEach {
    InModuleScope PrtgSensorKit { $script:PrtgRedactions.Clear() }
  }

  It 'reveals the first six characters of a 16-character secret' {
    InModuleScope PrtgSensorKit {
      Add-PrtgRedaction 'abc-def124903949'
      Protect-PrtgSecretText -Text 'GET https://api/?key=abc-def124903949 failed' |
        Should -Be 'GET https://api/?key=abc-de***** failed'
    }
  }

  It 'masks a short secret completely' {
    InModuleScope PrtgSensorKit {
      Add-PrtgRedaction 'Pass123'
      Protect-PrtgSecretText -Text 'login as Pass123 denied' | Should -Be 'login as ***** denied'
    }
  }

  It 'never registers a secret shorter than six characters' {
    InModuleScope PrtgSensorKit {
      Add-PrtgRedaction 'abc'
      $script:PrtgRedactions.Count | Should -Be 0
      # Redacting a 3-character string would mangle ordinary prose for no real protection.
      Protect-PrtgSecretText -Text 'the abc of it' | Should -Be 'the abc of it'
    }
  }

  It 'returns text containing no secret byte-identical' {
    InModuleScope PrtgSensorKit {
      Add-PrtgRedaction 'Sup3rSecret!Pa55'
      $text = 'nothing sensitive here, just a long ordinary sentence.'
      Protect-PrtgSecretText -Text $text | Should -BeExactly $text
    }
  }

  It 'does not disclose the secret length through the mask width' {
    InModuleScope PrtgSensorKit {
      $short = 'abcdef1234567890'
      $long = 'abcdef' + ('x' * 60)
      Add-PrtgRedaction $short
      $a = Protect-PrtgSecretText -Text $short
      $script:PrtgRedactions.Clear()
      Add-PrtgRedaction $long
      $b = Protect-PrtgSecretText -Text $long
      $a | Should -Be 'abcdef*****'
      $b | Should -Be 'abcdef*****'
      $a.Length | Should -Be $b.Length
    }
  }

  It 'masks overlapping secrets deterministically, longest first' {
    # HashSet iteration order is unspecified, so without the length sort the result would
    # depend on registration order: masking the short one first leaves '*****VALUE'.
    InModuleScope PrtgSensorKit {
      Add-PrtgRedaction 'SUPERSECRETVALUE'
      Add-PrtgRedaction 'SUPERSECRET'
      Protect-PrtgSecretText -Text 'saw SUPERSECRETVALUE here' | Should -Be 'saw SUPERS***** here'
    }
    InModuleScope PrtgSensorKit {
      $script:PrtgRedactions.Clear()
      Add-PrtgRedaction 'SUPERSECRET'
      Add-PrtgRedaction 'SUPERSECRETVALUE'
      Protect-PrtgSecretText -Text 'saw SUPERSECRETVALUE here' | Should -Be 'saw SUPERS***** here'
    }
  }

  It 'passes text through unchanged when nothing is registered' {
    InModuleScope PrtgSensorKit {
      Protect-PrtgSecretText -Text 'plain' | Should -BeExactly 'plain'
      Protect-PrtgSecretText -Text '' | Should -BeExactly ''
      Protect-PrtgSecretText -Text $null | Should -BeNullOrEmpty
    }
  }
}

Describe 'Redaction reaches the sensor output' {
  BeforeEach {
    Clear-PrtgOutput
    InModuleScope PrtgSensorKit { $script:PrtgRedactions.Clear() }
  }

  AfterEach {
    InModuleScope PrtgSensorKit { $script:PrtgRedactions.Clear() }
  }

  It 'masks a registered secret in the sensor message' {
    InModuleScope PrtgSensorKit { Add-PrtgRedaction 'Sup3rSecret!Pa55' }
    Set-PrtgMessage 'auth failed for Sup3rSecret!Pa55'
    Get-PrtgMessage | Should -Be 'auth failed for Sup3rS*****'
  }

  It 'masks a registered secret in the error text' {
    InModuleScope PrtgSensorKit { Add-PrtgRedaction 'Sup3rSecret!Pa55' }
    $json = Write-PrtgError -ErrorString 'https://api/?pw=Sup3rSecret!Pa55 returned 401' | ConvertFrom-Json
    $json.prtg.text | Should -Not -BeLike '*Sup3rSecret!Pa55*'
    $json.prtg.text | Should -BeLike '*Sup3rS`*`*`*`*`**'
  }

  It 'masks a secret containing # even though # is stripped from PRTG messages' {
    # Order matters: strip first and 'Pa##word123456' becomes 'Password123456', which no
    # longer matches the registered secret - a silent leak in exactly the case this exists for.
    # Registered value is 14 chars, so 5 characters are revealed ('Pa##w'), and the '#' strip
    # then runs over the already-masked text.
    InModuleScope PrtgSensorKit { Add-PrtgRedaction 'Pa##word123456' }
    Set-PrtgMessage 'bad credential Pa##word123456 rejected'
    Get-PrtgMessage | Should -Be 'bad credential Paw***** rejected'
  }

  It 'masks a secret that straddles the 2000-character truncation boundary' {
    # Truncate first and the tail of the secret is cut off, so the surviving fragment
    # ('abcdef123456789') matches nothing and is emitted in the clear. Redacting first
    # shortens the text to exactly 2000, so nothing is truncated at all.
    InModuleScope PrtgSensorKit { Add-PrtgRedaction 'abcdef1234567890' }
    Set-PrtgMessage (('x' * 1985) + 'abcdef1234567890' + 'tail')
    $message = Get-PrtgMessage
    $message.Length | Should -Be 2000
    $message | Should -Not -BeLike '*abcdef123456*'
    $message | Should -BeLike '*abcdef`*`*`*`*`*tail'
  }
}

Describe 'Redaction seeding' {
  BeforeEach {
    Clear-PrtgOutput
    foreach ($name in 'prtg_windowspassword', 'prtg_windowsuser', 'prtg_snmpcommunity', 'prtg_linuxpassword') {
      Remove-Item "Env:$name" -ErrorAction SilentlyContinue
    }
  }

  AfterEach {
    foreach ($name in 'prtg_windowspassword', 'prtg_windowsuser', 'prtg_snmpcommunity', 'prtg_linuxpassword') {
      Remove-Item "Env:$name" -ErrorAction SilentlyContinue
    }
    InModuleScope PrtgSensorKit { $script:PrtgRedactions.Clear() }
    Clear-PrtgOutput
  }

  It 'seeds credential placeholders from the environment, but not user names' {
    $env:prtg_windowspassword = 'Sup3rSecret!Pa55'
    $env:prtg_windowsuser = 'CONTOSO-serviceaccount'
    InModuleScope PrtgSensorKit {
      $script:PrtgRedactions.Clear()
      Initialize-PrtgRedaction
    }

    Set-PrtgMessage 'user CONTOSO-serviceaccount pw Sup3rSecret!Pa55'
    $message = Get-PrtgMessage
    $message | Should -BeLike '*CONTOSO-serviceaccount*'
    $message | Should -Not -BeLike '*Sup3rSecret!Pa55*'
  }

  It 'is re-seeded by Invoke-PrtgSensor for a host that imported the module earlier' {
    InModuleScope PrtgSensorKit { $script:PrtgRedactions.Clear() }
    $env:prtg_windowspassword = 'LateBoundSecret42'

    $json = Invoke-PrtgSensor {
      New-PrtgChannel -Channel 'A' -Value 1 | Add-PrtgChannel
      Set-PrtgMessage 'connected with LateBoundSecret42'
    } | ConvertFrom-Json

    $json.prtg.text | Should -Not -BeLike '*LateBoundSecret42*'
    $json.prtg.text | Should -BeLike '*LateBo`*`*`*`*`**'
  }

  It 'never registers a default SNMP community, but still masks a real one' {
    # 'public' is exactly 6 chars, so it clears the length gate. Registering it would mask
    # every occurrence of an ordinary word - including inside longer ones ('Republic').
    $env:prtg_snmpcommunity = 'public'
    InModuleScope PrtgSensorKit {
      $script:PrtgRedactions.Clear()
      Initialize-PrtgRedaction
      $script:PrtgRedactions.Count | Should -Be 0
    }
    Set-PrtgMessage 'Republic of public records'
    Get-PrtgMessage | Should -Be 'Republic of public records'

    $env:prtg_snmpcommunity = 'PRIVATE'
    InModuleScope PrtgSensorKit {
      $script:PrtgRedactions.Clear()
      Initialize-PrtgRedaction
      # Case-insensitive: 'PRIVATE' is just as much a default as 'private'.
      $script:PrtgRedactions.Count | Should -Be 0
    }

    $env:prtg_snmpcommunity = 'n0t-the-default-community'
    InModuleScope PrtgSensorKit {
      $script:PrtgRedactions.Clear()
      Initialize-PrtgRedaction
    }
    Clear-PrtgOutput
    Set-PrtgMessage 'polled with n0t-the-default-community'
    Get-PrtgMessage | Should -Be 'polled with n0t-th*****'
  }

  It 'still masks a PASSWORD that happens to be a default community word' {
    # The exclusion is about what a default community IS, not about the string: 'public'
    # arriving as a Windows password is a real credential and must still be masked.
    $env:prtg_windowspassword = 'public'
    InModuleScope PrtgSensorKit {
      $script:PrtgRedactions.Clear()
      Initialize-PrtgRedaction
      $script:PrtgRedactions.Count | Should -Be 1
    }
    Set-PrtgMessage 'auth failed for public'
    Get-PrtgMessage | Should -Be 'auth failed for *****'
  }

  It 'auto-registers a Get-PrtgSecret -AsPlainText value' {
    InModuleScope PrtgSensorKit { $script:PrtgRedactions.Clear() }
    $path = Join-Path $TestDrive "redact-secrets-$(Get-Random)"
    $secret = ConvertTo-SecureString 'Rk-9f31d7a2c840' -AsPlainText -Force
    Save-PrtgSecret -Name 'Token' -Secret $secret -Path $path -AllowUnprotected -WarningAction SilentlyContinue

    $plain = Get-PrtgSecret -Name 'Token' -Path $path -AllowUnprotected -AsPlainText
    $plain | Should -Be 'Rk-9f31d7a2c840'

    Set-PrtgMessage "call failed with token $plain"
    # 15 chars -> ceil(15/3) = 5 revealed, under the 6 cap.
    Get-PrtgMessage | Should -Be 'call failed with token Rk-9f*****'
  }
}

Describe 'Redaction reaches the log file' {
  AfterEach {
    # In AfterEach, not at the end of the It: a failing assertion above would otherwise skip
    # the reset and leave the module's log state pointed at a dead $TestDrive path for every
    # later test in the session.
    InModuleScope PrtgSensorKit {
      $script:PrtgRedactions.Clear()
      $script:PrtgLogFile = $null
      $script:PrtgLogDirectory = $null
    }
  }

  It 'masks a registered secret in a Write-PrtgLog line' {
    $dir = Join-Path $TestDrive "redact-logs-$(Get-Random)"
    [void] (New-Item -ItemType Directory -Path $dir)
    InModuleScope PrtgSensorKit -Parameters @{ Dir = $dir } {
      param($Dir)
      $script:PrtgLogFile = $null
      $script:PrtgLogDirectory = $Dir
      Add-PrtgRedaction 'Sup3rSecret!Pa55'
    }

    Write-PrtgLog 'connecting with Sup3rSecret!Pa55'
    $content = Get-Content -LiteralPath @(Get-ChildItem -LiteralPath $dir -Filter '*.log')[0].FullName -Raw
    $content | Should -Not -BeLike '*Sup3rSecret!Pa55*'
    $content | Should -BeLike '*Sup3rS`*`*`*`*`**'
  }
}
