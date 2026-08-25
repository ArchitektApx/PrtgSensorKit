function Test-PrtgDoctorPSK0010 {
  <#
  .SYNOPSIS
    PSK0010: -DryRun left in the script
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Parsed
  )

  $invokeCalls = Get-PrtgDoctorCall -Context $Parsed -Name 'Invoke-PrtgSensor'

  $dryRunCalls = @($invokeCalls | Where-Object { (Get-PrtgDoctorSwitchState -Context $Parsed -Call $_ -Name 'DryRun') -eq 'on' })
  $unresolvedDryRunCalls = @($invokeCalls | Where-Object { (Get-PrtgDoctorSwitchState -Context $Parsed -Call $_ -Name 'DryRun') -eq 'unknown' })
  if ($dryRunCalls.Count -gt 0) {
    New-PrtgDoctorFinding -CheckId 'PSK0010' -Severity 'Warning' `
      -Message 'Invoke-PrtgSensor is called with -DryRun. Deployed to PRTG, this emits an object dump instead of the PRTG JSON.' `
      -Line $dryRunCalls[0].Extent.StartLineNumber `
      -Recommendation 'Remove -DryRun before deploying the sensor.'
  } elseif ($unresolvedDryRunCalls.Count -gt 0) {
    New-PrtgDoctorFinding -CheckId 'PSK0010' -Severity 'Info' `
      -Message 'Invoke-PrtgSensor parameters are splatted from a value that could not be resolved statically; unable to verify -DryRun is not left in.' `
      -Line $unresolvedDryRunCalls[0].Extent.StartLineNumber `
      -Recommendation 'Build the splat hashtable as a literal in the script, or pass -DryRun directly, so the Doctor can check it.'
  } else {
    New-PrtgDoctorFinding -CheckId 'PSK0010' -Severity 'Pass' -Message 'No -DryRun left in the script.'
  }
}
