function Test-PrtgDoctorPSK0009 {
  <#
  .SYNOPSIS
    PSK0009: web cmdlets without modern TLS
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Parsed
  )

  $invokeCalls = Get-PrtgDoctorCall -Context $Parsed -Name 'Invoke-PrtgSensor'
  $webCalls = Get-PrtgDoctorCall -Context $Parsed -Name @('Invoke-RestMethod', 'Invoke-WebRequest')

  if ($webCalls.Count -eq 0) {
    New-PrtgDoctorFinding -CheckId 'PSK0009' -Severity 'Pass' -Message 'No web cmdlets used; TLS setup not needed.'
  } else {
    $forceTlsStates = @($invokeCalls | ForEach-Object { Get-PrtgDoctorSwitchState -Context $Parsed -Call $_ -Name 'ForceModernTls' })
    # Manual TLS setup = an assignment whose TARGET is the ServicePointManager
    # SecurityProtocol member (not any variable containing that substring) and whose
    # value mentions a modern protocol, either literally or via a variable whose own
    # literal assignment mentions one. '$SecurityProtocolBackup = ...' or an Ssl3-only
    # assignment must not count; a value the Doctor cannot resolve is 'unknown', never
    # a silent Pass or a false 'not set up'.
    $tlsAssignments = @($Parsed.Assignments | Where-Object {
      $_.Left.Extent.Text -match '(?i)ServicePointManager\]\s*::\s*SecurityProtocol\s*$'
    })
    $tlsVerdicts = @(foreach ($assignment in $tlsAssignments) {
      if ($assignment.Right.Extent.Text -match '(?i)Tls1[23]') { 'modern'; continue }
      $variable = $assignment.Right.Find({ $args[0] -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)
      if ($null -eq $variable) { 'none'; continue }
      if (@(Get-PrtgDoctorAssignment -Context $Parsed -VariableName $variable.VariablePath.UserPath |
          Where-Object { $_.Right.Extent.Text -match '(?i)Tls1[23]' }).Count -gt 0) { 'modern' } else { 'unknown' }
    })
    if ($forceTlsStates -contains 'on' -or $tlsVerdicts -contains 'modern') {
      New-PrtgDoctorFinding -CheckId 'PSK0009' -Severity 'Pass' -Message 'Web cmdlets are used and TLS is set up.'
    } elseif ($forceTlsStates -contains 'unknown' -or $tlsVerdicts -contains 'unknown') {
      New-PrtgDoctorFinding -CheckId 'PSK0009' -Severity 'Info' `
        -Message 'Web cmdlets are used and a TLS setup was found, but its value could not be verified statically (splatted or variable-based).' `
        -Line $webCalls[0].Extent.StartLineNumber `
        -Recommendation 'Prefer -ForceModernTls on the Invoke-PrtgSensor call, or assign SecurityProtocol from a literal Tls12/Tls13 value.'
    } else {
      New-PrtgDoctorFinding -CheckId 'PSK0009' -Severity 'Info' `
        -Message 'Web cmdlets are used without -ForceModernTls or a manual SecurityProtocol assignment. Windows PowerShell 5.1 defaults can lack TLS 1.2.' `
        -Line $webCalls[0].Extent.StartLineNumber `
        -Recommendation 'Add -ForceModernTls to the Invoke-PrtgSensor call.'
    }
  }
}
