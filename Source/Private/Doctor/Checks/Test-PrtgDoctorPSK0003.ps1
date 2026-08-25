function Test-PrtgDoctorPSK0003 {
  <#
  .SYNOPSIS
    PSK0003: Restart-* must not run inside the sensor block
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Parsed
  )

  $restartCalls = Get-PrtgDoctorCall -Context $Parsed -Name @('Restart-As64BitPowershell', 'Restart-InPwsh')

  $restartsInside = @($restartCalls | Where-Object { Test-PrtgDoctorInSensorBlock -Context $Parsed -Node $_ })
  if ($restartsInside.Count -gt 0) {
    foreach ($call in $restartsInside) {
      New-PrtgDoctorFinding -CheckId 'PSK0003' -Severity 'Error' `
        -Message "'$($call.GetCommandName())' is called inside the Invoke-PrtgSensor block. The relaunched child process output would be discarded by the output guard." `
        -Line $call.Extent.StartLineNumber `
        -Recommendation 'Move the Restart-* call to the top of the script, before Invoke-PrtgSensor.'
    }
  } else {
    New-PrtgDoctorFinding -CheckId 'PSK0003' -Severity 'Pass' -Message 'No Restart-* call inside the sensor block.'
  }
}
