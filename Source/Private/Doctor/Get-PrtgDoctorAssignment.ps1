function Get-PrtgDoctorAssignment {
  # Every assignment in the analyzed script whose target is the named variable. Used to resolve
  # splatted hashtables and variable-based values back to the literal they came from.
  [CmdletBinding()]
  [OutputType([System.Management.Automation.Language.AssignmentStatementAst[]])]
  param(
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Context,

    [Parameter(Mandatory = $true)]
    [string]$VariableName
  )

  @($Context.Assignments | Where-Object {
      $_.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
      $_.Left.VariablePath.UserPath -eq $VariableName
    })
}
