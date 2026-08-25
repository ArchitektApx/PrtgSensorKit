function Get-PrtgDoctorLiteralArgument {
  # Literal string arguments of a command: positional values and values of the given
  # named parameters, with array literals unwrapped. Values of other named parameters
  # are skipped; non-literal (variable/expression) arguments are ignored. Shared by
  # every check that inspects command arguments so scalar and array forms are always
  # handled the same way.
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
    # Take values that are positional or belong to an allowed parameter; skip the rest.
    $belongsToOtherParameter = $previous -is [System.Management.Automation.Language.CommandParameterAst] -and
      $NamedParameter -notcontains $previous.ParameterName
    if ($belongsToOtherParameter) { continue }

    if ($elements[$i] -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
      $values.Add($elements[$i].Value)
    } elseif ($elements[$i] -is [System.Management.Automation.Language.ArrayLiteralAst] -or
              $elements[$i] -is [System.Management.Automation.Language.ArrayExpressionAst]) {
      # Both array forms: bare comma lists ('A', 'B') parse as ArrayLiteralAst, the
      # @('A', 'B') syntax as ArrayExpressionAst. Collect every string literal inside.
      foreach ($item in @($elements[$i].FindAll({
        $args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst]
      }, $true))) {
        $values.Add($item.Value)
      }
    }
  }
  $values.ToArray()
}
