function Get-PrtgDoctorLiteralArgument {
  <#
  .SYNOPSIS
    The literal string arguments of one command call.
  .DESCRIPTION
    Returns positional values and the values of the named parameters given, with array
    literals unwrapped. Other named parameters and non-literal arguments are ignored.
  .PARAMETER NamedParameter
    Names whose values count as arguments alongside the positional ones.
  #>
  [CmdletBinding()]
  [OutputType([string[]])]
  param(
    [Parameter(Mandatory = $true)]
    [System.Management.Automation.Language.CommandAst]$Call,

    [Parameter(Mandatory = $false)]
    [string[]]$NamedParameter = @('Name')
  )

  $values = [System.Collections.Generic.List[string]]::new()
  $elements = $Call.CommandElements
  for ($i = 1; $i -lt $elements.Count; $i++) {
    $previous = $elements[$i - 1]
    $belongsToOtherParameter = $previous -is [System.Management.Automation.Language.CommandParameterAst] -and
      $NamedParameter -notcontains $previous.ParameterName
    if ($belongsToOtherParameter) { continue }

    if ($elements[$i] -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
      $values.Add($elements[$i].Value)
    } elseif ($elements[$i] -is [System.Management.Automation.Language.ArrayLiteralAst] -or
              $elements[$i] -is [System.Management.Automation.Language.ArrayExpressionAst]) {
      # A bare comma list ('A', 'B') parses as ArrayLiteralAst, the @('A', 'B') syntax
      # as ArrayExpressionAst.
      foreach ($item in @($elements[$i].FindAll({
        $args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst]
      }, $true))) {
        $values.Add($item.Value)
      }
    }
  }
  $values.ToArray()
}
