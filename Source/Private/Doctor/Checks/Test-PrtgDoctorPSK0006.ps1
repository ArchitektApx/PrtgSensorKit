function Test-PrtgDoctorPSK0006 {
  <#
  .SYNOPSIS
    PSK0006: no Invoke-PrtgSensor call at all
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Parsed
  )

  $invokeCalls = Get-PrtgDoctorCall -Context $Parsed -Name 'Invoke-PrtgSensor'

  if ($invokeCalls.Count -eq 0) {
    New-PrtgDoctorFinding -CheckId 'PSK0006' -Severity 'Info' `
      -Message 'No Invoke-PrtgSensor call found; assuming low-level mode (manual Write-PrtgOutput / Write-PrtgError).' `
      -Recommendation 'If this is not intentional, wrap your sensor logic in Invoke-PrtgSensor { ... }.'
  } else {
    New-PrtgDoctorFinding -CheckId 'PSK0006' -Severity 'Pass' -Message 'Invoke-PrtgSensor is used.'
  }
}
