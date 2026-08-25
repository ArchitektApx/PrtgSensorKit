function Get-PrtgDoctorSwitchState {
  # Whether a switch parameter is on, off, or unknowable at one call site.
  #
  # A switch counts as ENABLED ('on') only when present without an argument (-X) or with
  # an argument other than a literal $false (-X:$true, -X:$flag). '-X:$false' is 'off'.
  # Splatted literal hashtables are resolved too; a splat the Doctor cannot resolve
  # statically yields 'unknown' so checks never report a false Pass.
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Context,

    [Parameter(Mandatory = $true)]
    [System.Management.Automation.Language.CommandAst]$Call,

    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  $parameter = @($Call.CommandElements | Where-Object {
      $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq $Name
    }) | Select-Object -First 1
  if ($parameter) {
    if ($null -eq $parameter.Argument -or $parameter.Argument.Extent.Text -ne '$false') { return 'on' }
    return 'off'
  }

  $state = 'off'
  foreach ($splat in @($Call.CommandElements | Where-Object {
        $_ -is [System.Management.Automation.Language.VariableExpressionAst] -and $_.Splatted
      })) {
    $resolved = $false
    foreach ($assignment in @(Get-PrtgDoctorAssignment -Context $Context -VariableName $splat.VariablePath.UserPath)) {
      $hashtable = $assignment.Right.Find({ $args[0] -is [System.Management.Automation.Language.HashtableAst] }, $true)
      if ($null -eq $hashtable) { continue }
      $resolved = $true
      foreach ($pair in $hashtable.KeyValuePairs) {
        # Only a literal key can name a parameter; a variable or expression key is skipped.
        if ($pair.Item1 -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { continue }
        if ($pair.Item1.Value -eq $Name -and $pair.Item2.Extent.Text -ne '$false') { return 'on' }
      }
    }
    if (-not $resolved) { $state = 'unknown' }
  }
  $state
}
