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
  # ParseFile never returns null: syntax errors, a missing path, a directory and an empty file
  # all yield a ScriptBlockAst and report through $parseErrors, so no consumer guards the tree.
  $ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$parseErrors)

  # The whole-script walks every check reads from, done once so no check walks the tree to a
  # different answer.
  $commandAsts = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true))
  $assignments = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true))

  $context = [PSCustomObject]@{
    ScriptPath         = $ScriptPath
    Ast                = $ast
    Tokens             = $tokens
    ParseErrors        = @($parseErrors)
    CommandAsts        = $commandAsts
    Assignments        = $assignments
    SensorBlockExtents = @()
  }

  # Derived from CommandAsts through the same helper the checks use, so the object must exist first.
  $context.SensorBlockExtents = @(
    foreach ($call in @(Get-PrtgDoctorCall -Context $context -Name 'Invoke-PrtgSensor')) {
      foreach ($element in $call.CommandElements) {
        if ($element -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) { $element.Extent }
      }
    }
  )

  $context
}
