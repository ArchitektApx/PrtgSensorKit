# Artifact tests: the checks about the BUILD rather than about what the module does. They read
# the built module whatever -Target says; the behaviour tests one folder up import -Target's tree.

# Top level too, not just BeforeAll: -Skip: and -ForEach expressions run at discovery time.
. $PSScriptRoot/../_TestHelpers.ps1

BeforeAll {
  . $PSScriptRoot/../_TestHelpers.ps1
  Import-BuiltModule
}

Describe 'Built module' {
  It 'was built from the source tree as it stands now' {
    $stale = Get-StaleBuildReason
    $stale | Should -BeNullOrEmpty -Because "$stale"
  }

  It 'produced a manifest under the build output root' {
    Get-BuiltManifestPath | Should -Exist
  }

  It 'has a valid manifest' {
    { Test-ModuleManifest -Path (Get-BuiltManifestPath) } | Should -Not -Throw
  }

  It 'imports' {
    Get-Module -Name (Get-ModuleInfo).ModuleName | Should -Not -BeNullOrEmpty
  }
}

# A function the build misses is only visible on a real install; catch it here instead.
Describe 'Every function in the source tree reaches the built module' {
  BeforeAll {
    $script:Info = Get-ModuleInfo

    function script:Get-DefinedFunction {
      [OutputType([string[]])]
      param([string[]]$Path)

      $names = [System.Collections.Generic.HashSet[string]]::new()
      foreach ($file in $Path) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$null)
        foreach ($function in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
          [void]$names.Add($function.Name)
        }
      }
      [string[]]$names
    }

    # '*.ps1' leaves the source loader out, which is wanted: it is not copied into the built
    # root module, so a function defined there would read as missing by design.
    $script:SourceFiles = @(Get-ChildItem -Path $script:Info.SourceRoot -Recurse -Filter '*.ps1' -File |
        ForEach-Object { $_.FullName })
    $script:InSource = @(Get-DefinedFunction -Path $script:SourceFiles)
    $script:InBuild = @(Get-DefinedFunction -Path @(Join-Path (Split-Path -Parent (Get-BuiltManifestPath)) "$($script:Info.ModuleName).psm1"))
  }

  It 'finds functions on both sides at all' {
    $script:InSource.Count | Should -BeGreaterThan 0
    $script:InBuild.Count | Should -BeGreaterThan 0
  }

  It 'defines every function the source tree defines' {
    $missing = @($script:InSource | Where-Object { $_ -notin $script:InBuild } | Sort-Object)
    $missing | Should -BeNullOrEmpty -Because "the source tree defines these and the built module does not: $($missing -join ', ')"
  }
}

# The source manifest is the only export list that can drift; ModuleBuilder rewrites the built one.
Describe 'The source manifest and the built manifest export the same functions' {
  BeforeAll {
    $script:Info = Get-ModuleInfo
    $script:SourceExports = @((Import-PowerShellDataFile -LiteralPath $script:Info.SourceManifest).FunctionsToExport | Sort-Object)
    $script:BuiltExports = @((Import-PowerShellDataFile -LiteralPath (Get-BuiltManifestPath)).FunctionsToExport | Sort-Object)
  }

  It 'exports the same set on both sides' {
    $script:BuiltExports.Count | Should -BeGreaterThan 0
    $onlySource = @($script:SourceExports | Where-Object { $_ -notin $script:BuiltExports })
    $onlyBuilt = @($script:BuiltExports | Where-Object { $_ -notin $script:SourceExports })
    $because = "the source manifest exports '$($script:SourceExports -join ', ')' and the built manifest exports '$($script:BuiltExports -join ', ')'"
    ($onlySource + $onlyBuilt) | Should -BeNullOrEmpty -Because $because
  }
}

# Nothing else keeps build.psd1's directory list and the source loader's loop in step. A
# directory in one and not the other means the source import and the build load different files.
Describe 'The build configuration and the source loader' {
  BeforeAll {
    $script:Info = Get-ModuleInfo
    $script:Configured = @($script:Info.SourceDirectories)

    $loader = Join-Path $script:Info.SourceRoot "$($script:Info.ModuleName).psm1"
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($loader, [ref]$null, [ref]$null)
    $loop = $ast.Find({
        param($n)
        $n -is [System.Management.Automation.Language.ForEachStatementAst] -and $n.Variable.VariablePath.UserPath -eq 'dir'
      }, $true)
    $script:Loaded = @($loop.Condition.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) |
        ForEach-Object { $_.Value })
  }

  It 'walks the same source directories on both sides' {
    $script:Configured.Count | Should -BeGreaterThan 0
    $both = "build.psd1 builds from '$($script:Configured -join ', ')' and the source loader dot-sources '$($script:Loaded -join ', ')'"
    @($script:Loaded | Sort-Object) | Should -Be @($script:Configured | Sort-Object) -Because $both
  }
}
