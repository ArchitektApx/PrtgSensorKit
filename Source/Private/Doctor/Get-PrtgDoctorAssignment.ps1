function Get-PrtgDoctorAssignment {
  <#
  .SYNOPSIS
    Every assignment in the analyzed script whose target is the named variable.
  #>
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
