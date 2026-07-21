function Get-PrtgDoctorAst {
  <#
  .SYNOPSIS
    Parses a sensor script into AST, tokens, and parse errors for the Doctor checks.
  .DESCRIPTION
    Thin wrapper around the PowerShell language parser. The script is only PARSED, never
    executed - the Doctor must be safe to run against untrusted or broken sensor scripts.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptPath
  )

  $tokens = $null
  $parseErrors = $null
  $ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$parseErrors)

  # Walked once here; every consumer (script checks, environment context) reuses this
  # list so there is exactly one definition of 'the commands in the script'.
  $commandAsts = @()
  if ($null -ne $ast) {
    $commandAsts = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true))
  }

  [PSCustomObject]@{
    ScriptPath  = $ScriptPath
    Ast         = $ast
    Tokens      = $tokens
    ParseErrors = @($parseErrors)
    CommandAsts = $commandAsts
  }
}

function Get-PrtgDoctorImportedModuleName {
  # Collects STATICALLY imported module names: literal Import-Module arguments (positional
  # or -Name, including array literals) and #Requires -Modules. Dynamic/variable-based
  # imports are intentionally out of scope (documented in the Doctor's PSK0104 check).
  [CmdletBinding()]
  [OutputType([string[]])]
  param(
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Parsed
  )

  $names = [System.Collections.Generic.List[string]]::new()
  if ($null -eq $Parsed.Ast) { return @() }

  foreach ($requirement in @($Parsed.Ast.ScriptRequirements.RequiredModules)) {
    if ($requirement.Name) { $names.Add($requirement.Name) }
  }

  $importCalls = @($Parsed.CommandAsts | Where-Object { $_.GetCommandName() -eq 'Import-Module' })

  foreach ($call in $importCalls) {
    foreach ($value in @(Get-PrtgDoctorLiteralArgument -Call $call)) { $names.Add($value) }
  }

  # Module paths count as static too; reduce them to the module name. Split on both
  # separators by hand: the Doctor may analyze a Windows sensor script on any platform,
  # where .NET would not treat '\' as a separator. Only module FILE extensions are
  # stripped - a dotted module NAME like 'Az.Accounts' must keep its dot.
  @($names | ForEach-Object {
    ($_ -split '[\\/]')[-1] -replace '\.(psd1|psm1|dll)$', ''
  } | Select-Object -Unique)
}

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
