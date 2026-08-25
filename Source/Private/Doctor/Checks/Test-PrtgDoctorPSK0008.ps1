function Test-PrtgDoctorPSK0008 {
  <#
  .SYNOPSIS
    PSK0008: statements after Invoke-PrtgSensor that could write to stdout
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Parsed
  )

  $ast = $Parsed.Ast
  $invokeCalls = Get-PrtgDoctorCall -Context $Parsed -Name 'Invoke-PrtgSensor'

  $trailing = @()
  if ($invokeCalls.Count -gt 0 -and $null -ne $ast.EndBlock) {
    $lastInvokeEnd = ($invokeCalls | ForEach-Object { $_.Extent.EndOffset } | Measure-Object -Maximum).Maximum
    $trailing = @($ast.EndBlock.Statements | Where-Object {
      $_.Extent.StartOffset -ge $lastInvokeEnd
    } | Where-Object {
      $statement = $_
      if ($statement -is [System.Management.Automation.Language.AssignmentStatementAst]) { return $false }
      if ($statement -is [System.Management.Automation.Language.PipelineAst]) { return $true }
      # Control flow after the sensor call: any pipeline in OUTPUT position inside it
      # (direct child of a statement block, not a condition or an assignment RHS) can
      # write to stdout at runtime, so the whole statement is flagged.
      [bool]$statement.Find({
        $args[0] -is [System.Management.Automation.Language.PipelineAst] -and
        ($args[0].Parent -is [System.Management.Automation.Language.StatementBlockAst] -or
         $args[0].Parent -is [System.Management.Automation.Language.NamedBlockAst])
      }, $true)
    })
  }
  if ($trailing.Count -gt 0) {
    foreach ($statement in $trailing) {
      New-PrtgDoctorFinding -CheckId 'PSK0008' -Severity 'Warning' `
        -Message "Statement after Invoke-PrtgSensor could write to the output stream and corrupt the emitted JSON: $($statement.Extent.Text.Trim())" `
        -Line $statement.Extent.StartLineNumber `
        -Recommendation 'Remove it, assign its result to a variable, or pipe it to Out-Null. PRTG reads everything on stdout.'
    }
  } else {
    New-PrtgDoctorFinding -CheckId 'PSK0008' -Severity 'Pass' -Message 'No output-producing statements after Invoke-PrtgSensor.'
  }
}
