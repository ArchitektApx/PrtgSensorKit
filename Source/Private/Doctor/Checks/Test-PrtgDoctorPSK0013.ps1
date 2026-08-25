function Test-PrtgDoctorPSK0013 {
  <#
  .SYNOPSIS
    PSK0013: DPAPI secrets are bound to the sensor account
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Parsed
  )

  $secretCalls = Get-PrtgDoctorCall -Context $Parsed -Name 'Get-PrtgSecret'
  if ($secretCalls.Count -gt 0) {
    New-PrtgDoctorFinding -CheckId 'PSK0013' -Severity 'Info' `
      -Message 'Get-PrtgSecret is used. DPAPI secrets only decrypt under the Windows account that saved them, and PRTG runs the sensor as the probe service account (usually Local System), not your console user.' `
      -Line $secretCalls[0].Extent.StartLineNumber `
      -Recommendation "Run Save-PrtgSecret under the same account the sensor runs as, and test the script under that account before deploying. See Docs/secrets.md ('Credentials and secrets') in the PrtgSensorKit repository."
  } else {
    New-PrtgDoctorFinding -CheckId 'PSK0013' -Severity 'Pass' -Message 'No Get-PrtgSecret usage; secret account binding not applicable.'
  }
}
