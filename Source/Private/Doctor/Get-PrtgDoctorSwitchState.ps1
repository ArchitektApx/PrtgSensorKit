function Get-PrtgDoctorSwitchState {
  <#
  .SYNOPSIS
    Whether a switch is 'on', 'off' or 'unknown' at one call site.
  .DESCRIPTION
    '-X' and '-X:<anything but literal $false>' are on, '-X:$false' is off. Literal splat
    hashtables are resolved; a splat that cannot be resolved statically is unknown.
  #>
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
