# Characterizes the module's ENTIRE public surface against the built artifact in Dist/.
#
# The module has promised since 1.1.0 that sensor scripts written for 1.0.0 and 1.1.0 run
# unchanged. This file is what measures that promise: the exported function names, each one's
# parameters and their types, the channel unit set, and the companion parameters each unit makes
# available. Anything removed or reshaped fails here rather than in a sensor on a probe.
#
# The expected surface below is the contract, so it is written out in full rather than derived
# from the module. A test that reads the surface and compares it with itself passes forever.
#
# Companion parameters are DYNAMIC, so a static listing of the command's parameters never sees
# them. Get-Command -ArgumentList runs the dynamicparam block with those arguments bound, which is
# the only way to observe them without invoking the command; the arguments are positional because
# a hashtable is not bound for dynamic parameter discovery.

BeforeDiscovery {
  # The parameter types are FullNames on purpose: 'int' and 'System.Object' both print as
  # something short and a shortened form hides a real change from [int] to [long].
  $script:ExpectedSurface = [ordered]@{
    'Add-PrtgChannel'           = [ordered]@{
      PrtgChannel = 'System.Management.Automation.PSObject'
    }
    'Clear-PrtgOutput'          = [ordered]@{}
    'Clear-PrtgSensorState'     = [ordered]@{
      ClearLock      = 'System.Management.Automation.SwitchParameter'
      Depth          = 'System.Int32'
      Force          = 'System.Management.Automation.SwitchParameter'
      Key            = 'System.String'
      MaxAge         = 'System.TimeSpan'
      Path           = 'System.String'
      TimeoutSeconds = 'System.Int32'
    }
    'Get-PrtgMessage'           = [ordered]@{}
    'Get-PrtgSecret'            = [ordered]@{
      AllowUnprotected = 'System.Management.Automation.SwitchParameter'
      AsPlainText      = 'System.Management.Automation.SwitchParameter'
      Name             = 'System.String'
      Path             = 'System.String'
    }
    'Get-PrtgSensorState'       = [ordered]@{
      Default        = 'System.Object'
      Force          = 'System.Management.Automation.SwitchParameter'
      Key            = 'System.String'
      Latest         = 'System.Management.Automation.SwitchParameter'
      MaxAge         = 'System.TimeSpan'
      Path           = 'System.String'
      TimeoutSeconds = 'System.Int32'
    }
    'Invoke-PrtgSensor'         = [ordered]@{
      DryRun            = 'System.Management.Automation.SwitchParameter'
      EnableLogging     = 'System.Management.Automation.SwitchParameter'
      ForceModernTls    = 'System.Management.Automation.SwitchParameter'
      LogPath           = 'System.String'
      MaxLogs           = 'System.Int32'
      RetryCount        = 'System.Int32'
      RetryDelaySeconds = 'System.Int32'
      ScriptBlock       = 'System.Management.Automation.ScriptBlock'
    }
    'Invoke-PrtgSensorDoctor'   = [ordered]@{
      ScriptPath            = 'System.String'
      SkipEnvironmentChecks = 'System.Management.Automation.SwitchParameter'
    }
    'New-PrtgChannel'           = [ordered]@{
      Channel         = 'System.String'
      DecimalMode     = 'System.String'
      Float           = 'System.Management.Automation.SwitchParameter'
      LimitErrorMsg   = 'System.String'
      LimitMaxError   = 'System.Object'
      LimitMaxWarning = 'System.Object'
      LimitMinError   = 'System.Object'
      LimitMinWarning = 'System.Object'
      LimitMode       = 'System.Boolean'
      LimitWarningMsg = 'System.String'
      Mode            = 'System.String'
      NotifyChanged   = 'System.Management.Automation.SwitchParameter'
      ShowChart       = 'System.Boolean'
      ShowTable       = 'System.Boolean'
      Unit            = 'System.String'
      Value           = 'System.Object'
      ValueLookup     = 'System.String'
      Warning         = 'System.Management.Automation.SwitchParameter'
    }
    'Restart-As64BitPowershell' = [ordered]@{}
    'Restart-InPwsh'            = [ordered]@{}
    'Save-PrtgSecret'           = [ordered]@{
      AllowUnprotected = 'System.Management.Automation.SwitchParameter'
      Credential       = 'System.Management.Automation.PSCredential'
      Name             = 'System.String'
      Path             = 'System.String'
      Secret           = 'System.Security.SecureString'
    }
    'Save-PrtgSensorState'      = [ordered]@{
      Depth          = 'System.Int32'
      Force          = 'System.Management.Automation.SwitchParameter'
      Key            = 'System.String'
      MaxEntries     = 'System.Int32'
      Path           = 'System.String'
      TimeoutSeconds = 'System.Int32'
      Value          = 'System.Object'
    }
    'Set-PrtgMessage'           = [ordered]@{
      Text = 'System.String'
    }
    'Set-PrtgOutput'            = [ordered]@{
      Object = 'System.Object'
    }
    'Use-PrtgCachedResult'      = [ordered]@{
      Depth          = 'System.Int32'
      Force          = 'System.Management.Automation.SwitchParameter'
      Key            = 'System.String'
      MaxAge         = 'System.TimeSpan'
      Path           = 'System.String'
      ScriptBlock    = 'System.Management.Automation.ScriptBlock'
      SkipNullCache  = 'System.Management.Automation.SwitchParameter'
      TimeoutSeconds = 'System.Int32'
    }
    'Write-PrtgError'           = [ordered]@{
      ErrorObject = 'System.Management.Automation.ErrorRecord'
      ErrorString = 'System.String'
    }
    'Write-PrtgLog'             = [ordered]@{
      Level   = 'System.String'
      Message = 'System.String'
    }
    'Write-PrtgOutput'          = [ordered]@{}
  }

  # How each function binds: which parameters are mandatory, which accept pipeline input, the
  # positional order, and the parameter set names.
  $script:ExpectedBinding = [ordered]@{
    'Add-PrtgChannel'           = @{ Mandatory = @('PrtgChannel'); Pipeline = @('PrtgChannel'); Positional = @('PrtgChannel'); Sets = @('__AllParameterSets') }
    'Clear-PrtgOutput'          = @{ Mandatory = @(); Pipeline = @(); Positional = @(); Sets = @('__AllParameterSets') }
    'Clear-PrtgSensorState'     = @{ Mandatory = @('Key'); Pipeline = @(); Positional = @('Key', 'MaxAge', 'Path', 'Depth', 'TimeoutSeconds'); Sets = @('__AllParameterSets') }
    'Get-PrtgMessage'           = @{ Mandatory = @(); Pipeline = @(); Positional = @(); Sets = @('__AllParameterSets') }
    'Get-PrtgSecret'            = @{ Mandatory = @('Name'); Pipeline = @(); Positional = @('Name', 'Path'); Sets = @('__AllParameterSets') }
    'Get-PrtgSensorState'       = @{ Mandatory = @('Key'); Pipeline = @(); Positional = @('Key', 'MaxAge', 'Default', 'Path', 'TimeoutSeconds'); Sets = @('__AllParameterSets') }
    'Invoke-PrtgSensor'         = @{ Mandatory = @('ScriptBlock'); Pipeline = @(); Positional = @('ScriptBlock'); Sets = @('Default', 'Logging') }
    'Invoke-PrtgSensorDoctor'   = @{ Mandatory = @('ScriptPath'); Pipeline = @(); Positional = @('ScriptPath'); Sets = @('__AllParameterSets') }
    'New-PrtgChannel'           = @{ Mandatory = @('Channel', 'Value'); Pipeline = @(); Positional = @('Channel', 'Value', 'Unit', 'Mode', 'DecimalMode', 'ShowChart', 'ShowTable', 'LimitMaxError', 'LimitMaxWarning', 'LimitMinWarning', 'LimitMinError', 'LimitErrorMsg', 'LimitWarningMsg', 'LimitMode', 'ValueLookup'); Sets = @('__AllParameterSets') }
    'Restart-As64BitPowershell' = @{ Mandatory = @(); Pipeline = @(); Positional = @(); Sets = @('__AllParameterSets') }
    'Restart-InPwsh'            = @{ Mandatory = @(); Pipeline = @(); Positional = @(); Sets = @('__AllParameterSets') }
    'Save-PrtgSecret'           = @{ Mandatory = @('Name', 'Secret', 'Credential'); Pipeline = @(); Positional = @(); Sets = @('SecureString', 'Credential') }
    'Save-PrtgSensorState'      = @{ Mandatory = @('Key', 'Value'); Pipeline = @(); Positional = @('Key', 'Value', 'Path', 'Depth', 'MaxEntries', 'TimeoutSeconds'); Sets = @('__AllParameterSets') }
    'Set-PrtgMessage'           = @{ Mandatory = @(); Pipeline = @('Text'); Positional = @('Text'); Sets = @('__AllParameterSets') }
    'Set-PrtgOutput'            = @{ Mandatory = @(); Pipeline = @(); Positional = @('Object'); Sets = @('__AllParameterSets') }
    'Use-PrtgCachedResult'      = @{ Mandatory = @('Key', 'MaxAge', 'ScriptBlock'); Pipeline = @(); Positional = @('ScriptBlock'); Sets = @('__AllParameterSets') }
    'Write-PrtgError'           = @{ Mandatory = @('ErrorObject', 'ErrorString'); Pipeline = @('ErrorObject', 'ErrorString'); Positional = @(); Sets = @('ErrorObject', 'ErrorString') }
    'Write-PrtgLog'             = @{ Mandatory = @('Message'); Pipeline = @(); Positional = @('Message'); Sets = @('__AllParameterSets') }
    'Write-PrtgOutput'          = @{ Mandatory = @(); Pipeline = @(); Positional = @(); Sets = @('__AllParameterSets') }
  }

  # Every unit the channel cmdlet accepts, mapped to the companion parameters that unit makes
  # available and whether each one is mandatory. An empty set is as much a part of the contract as
  # a populated one: a companion appearing on a unit that had none is a surface change too.
  $script:ExpectedUnits = [ordered]@{
    BytesBandwidth = [ordered]@{ SpeedSize = $false; SpeedTime = $false }
    BytesDisk      = [ordered]@{ VolumeSize = $false }
    Temperature    = [ordered]@{}
    Percent        = [ordered]@{}
    TimeResponse   = [ordered]@{}
    TimeSeconds    = [ordered]@{}
    Count          = [ordered]@{}
    Custom         = [ordered]@{ CustomUnit = $true }
    CPU            = [ordered]@{}
    BytesFile      = [ordered]@{ VolumeSize = $false }
    SpeedDisk      = [ordered]@{ SpeedSize = $false; SpeedTime = $false }
    SpeedNet       = [ordered]@{ SpeedSize = $false; SpeedTime = $false }
    TimeHours      = [ordered]@{}
  }

  # Everything the run phase needs travels through -ForEach. Discovery and run are separate
  # scopes in Pester 5+, so a variable set here is not in scope inside an It block.
  $FunctionCases = @($script:ExpectedSurface.Keys | ForEach-Object {
      @{ Name = $_; Expected = $script:ExpectedSurface[$_] }
    })
  $BindingCases = @($script:ExpectedBinding.Keys | ForEach-Object {
      @{ Name = $_; Expected = $script:ExpectedBinding[$_] }
    })
  $UnitCases = @($script:ExpectedUnits.Keys | ForEach-Object {
      # Not wrapped in @(): the value is the name-to-mandatory map, and array-wrapping it would
      # hide .Keys behind member enumeration.
      @{ Unit = $_; Expected = $script:ExpectedUnits[$_] }
    })
  $FunctionSetCase = @(@{ Expected = @($script:ExpectedSurface.Keys) })
  $UnitSetCase = @(@{ Expected = @($script:ExpectedUnits.Keys) })
}

BeforeAll {
  . $PSScriptRoot/../_TestHelpers.ps1
  Import-BuiltModule

  # PowerShell adds these to every advanced function; they are not part of this module's surface.
  $script:CommonParameters =
  [System.Management.Automation.PSCmdlet]::CommonParameters +
  [System.Management.Automation.PSCmdlet]::OptionalCommonParameters

  function Get-SurfaceParameter {
    param([string]$FunctionName)
    $cmd = Get-Command -Name $FunctionName -Module 'PrtgSensorKit' -ErrorAction Stop
    $table = @{}
    foreach ($p in $cmd.Parameters.GetEnumerator()) {
      if ($script:CommonParameters -contains $p.Key) { continue }
      $table[$p.Key] = $p.Value.ParameterType.FullName
    }
    $table
  }

  # Mandatory, pipeline and positional parameters across all of a function's parameter sets, as
  # sorted name lists (positional in position order), plus the set names.
  function Get-SurfaceBinding {
    param([string]$FunctionName)
    $cmd = Get-Command -Name $FunctionName -Module 'PrtgSensorKit' -ErrorAction Stop
    $mandatory = @(); $pipeline = @(); $positional = @()
    foreach ($p in $cmd.Parameters.GetEnumerator()) {
      if ($script:CommonParameters -contains $p.Key) { continue }
      $attributes = @($p.Value.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })
      if (@($attributes | Where-Object { $_.Mandatory }).Count) { $mandatory += $p.Key }
      if (@($attributes | Where-Object { $_.ValueFromPipeline -or $_.ValueFromPipelineByPropertyName }).Count) { $pipeline += $p.Key }
      $position = @($attributes | Where-Object { $_.Position -ge 0 } | Select-Object -First 1)
      if ($position.Count) { $positional += [PSCustomObject]@{ Name = $p.Key; Position = $position[0].Position } }
    }
    @{
      Mandatory  = @($mandatory | Sort-Object)
      Pipeline   = @($pipeline | Sort-Object)
      Positional = @($positional | Sort-Object Position | ForEach-Object { $_.Name })
      Sets       = @($cmd.ParameterSets.Name | Sort-Object)
    }
  }

  # Runs the dynamicparam block with -Unit bound and returns the companion parameters it added,
  # each mapped to its Mandatory flag. The arguments are positional: Get-Command binds a hashtable
  # as a single value and the dynamicparam block then sees no unit at all.
  function Get-CompanionParameter {
    param([string]$Unit)
    $companions = @('CustomUnit', 'SpeedSize', 'SpeedTime', 'VolumeSize')
    $cmd = Get-Command -Name 'New-PrtgChannel' -ArgumentList @('SurfaceProbe', 1, $Unit) -ErrorAction Stop
    $found = @{}
    foreach ($name in @($cmd.Parameters.Keys | Where-Object { $companions -contains $_ })) {
      $attribute = @($cmd.Parameters[$name].Attributes |
          Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })[0]
      $found[$name] = [bool]$attribute.Mandatory
    }
    $found
  }
}

Describe 'Public surface of the built module' {
  It 'exports exactly the documented set of functions' -ForEach $FunctionSetCase {
    $actual = @((Get-Module PrtgSensorKit).ExportedFunctions.Keys)
    $expected = @($Expected)

    (@($expected | Where-Object { $actual -notcontains $_ }) -join ', ') |
      Should -BeNullOrEmpty -Because 'these exported functions are gone or renamed'
    (@($actual | Where-Object { $expected -notcontains $_ }) -join ', ') |
      Should -BeNullOrEmpty -Because 'these functions are newly exported and are not in the recorded surface'
  }

  It 'exports no cmdlets, aliases or variables beyond the functions' {
    $m = Get-Module PrtgSensorKit
    (@($m.ExportedCmdlets.Keys) -join ', ') | Should -BeNullOrEmpty
    (@($m.ExportedAliases.Keys) -join ', ') | Should -BeNullOrEmpty
    (@($m.ExportedVariables.Keys) -join ', ') | Should -BeNullOrEmpty
  }

  It '<Name> takes exactly its recorded parameters' -ForEach $FunctionCases {
    $actual = Get-SurfaceParameter -FunctionName $Name

    (@($Expected.Keys | Where-Object { -not $actual.ContainsKey($_) }) -join ', ') |
      Should -BeNullOrEmpty -Because "$Name lost these parameters"
    (@($actual.Keys | Where-Object { -not $Expected.Contains($_) }) -join ', ') |
      Should -BeNullOrEmpty -Because "$Name gained these parameters, which are not in the recorded surface"
  }

  It '<Name> keeps the recorded type on every parameter' -ForEach $FunctionCases {
    $actual = Get-SurfaceParameter -FunctionName $Name

    $changed = @(
      foreach ($p in $Expected.Keys) {
        if (-not $actual.ContainsKey($p)) { continue }
        if ($actual[$p] -ne $Expected[$p]) { "$p is $($actual[$p]), recorded as $($Expected[$p])" }
      }
    )
    ($changed -join '; ') | Should -BeNullOrEmpty -Because "$Name changed a parameter type"
  }

  It '<Name> keeps its recorded mandatory, pipeline, positional and set binding' -ForEach $BindingCases {
    $actual = Get-SurfaceBinding -FunctionName $Name

    ($actual.Mandatory -join ',') | Should -Be (@($Expected.Mandatory | Sort-Object) -join ',') -Because "$Name changed which parameters are mandatory"
    ($actual.Pipeline -join ',') | Should -Be (@($Expected.Pipeline | Sort-Object) -join ',') -Because "$Name changed which parameters accept pipeline input"
    ($actual.Positional -join ',') | Should -Be (@($Expected.Positional) -join ',') -Because "$Name changed its positional parameter order"
    ($actual.Sets -join ',') | Should -Be (@($Expected.Sets | Sort-Object) -join ',') -Because "$Name changed its parameter sets"
  }
}

Describe 'Channel unit surface' {
  It 'accepts exactly the documented set of units' -ForEach $UnitSetCase {
    $set = (Get-Command New-PrtgChannel -Module 'PrtgSensorKit').Parameters['Unit'].Attributes |
      Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
    $actual = @($set.ValidValues)
    $expected = @($Expected)

    (@($expected | Where-Object { $actual -notcontains $_ }) -join ', ') |
      Should -BeNullOrEmpty -Because 'these channel units no longer bind'
    (@($actual | Where-Object { $expected -notcontains $_ }) -join ', ') |
      Should -BeNullOrEmpty -Because 'these channel units are new and are not in the recorded surface'
  }

  It 'unit <Unit> offers exactly its recorded companion parameters' -ForEach $UnitCases {
    $actual = Get-CompanionParameter -Unit $Unit
    $want = @($Expected.Keys | Sort-Object)
    $have = @($actual.Keys | Sort-Object)

    (@($want | Where-Object { $have -notcontains $_ }) -join ', ') |
      Should -BeNullOrEmpty -Because "unit $Unit no longer offers these companion parameters"
    (@($have | Where-Object { $want -notcontains $_ }) -join ', ') |
      Should -BeNullOrEmpty -Because "unit $Unit offers these companion parameters, which are not in the recorded surface"
  }

  It 'unit <Unit> keeps the recorded mandatory flag on every companion parameter' -ForEach $UnitCases {
    # A companion that becomes mandatory breaks a call that used to bind: a non-interactive host
    # throws ParameterBindingException for it.
    $actual = Get-CompanionParameter -Unit $Unit

    $changed = @(
      foreach ($name in $Expected.Keys) {
        if (-not $actual.ContainsKey($name)) { continue }
        if ($actual[$name] -ne $Expected[$name]) {
          "$name is Mandatory=$($actual[$name]), recorded as Mandatory=$($Expected[$name])"
        }
      }
    )
    ($changed -join '; ') | Should -BeNullOrEmpty -Because "unit $Unit changed a companion parameter's mandatory flag"
  }
}
