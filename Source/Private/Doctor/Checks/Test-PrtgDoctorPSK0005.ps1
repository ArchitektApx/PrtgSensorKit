function Test-PrtgDoctorPSK0005 {
  <#
  .SYNOPSIS
    PSK0005: no manual output commands inside the sensor block
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Parsed
  )

  $manualOutputCalls = Get-PrtgDoctorCall -Context $Parsed -Name @('Write-PrtgOutput', 'Write-PrtgError', 'Clear-PrtgOutput')
  $manualInside = @($manualOutputCalls | Where-Object { Test-PrtgDoctorInSensorBlock -Context $Parsed -Node $_ })
  if ($manualInside.Count -gt 0) {
    foreach ($call in $manualInside) {
      New-PrtgDoctorFinding -CheckId 'PSK0005' -Severity 'Error' `
        -Message "'$($call.GetCommandName())' inside the Invoke-PrtgSensor block is not supported; the wrapper owns the single response." `
        -Line $call.Extent.StartLineNumber `
        -Recommendation 'Remove the call. Use New-PrtgChannel | Add-PrtgChannel and Set-PrtgMessage inside the block, or drop Invoke-PrtgSensor and go fully low-level.'
    }
  } else {
    New-PrtgDoctorFinding -CheckId 'PSK0005' -Severity 'Pass' -Message 'No manual output commands inside the sensor block.'
  }
}
