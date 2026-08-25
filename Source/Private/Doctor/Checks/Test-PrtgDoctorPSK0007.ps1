function Test-PrtgDoctorPSK0007 {
  <#
  .SYNOPSIS
    PSK0007: at most one Invoke-PrtgSensor call
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Parsed
  )

  $invokeCalls = Get-PrtgDoctorCall -Context $Parsed -Name 'Invoke-PrtgSensor'

  if ($invokeCalls.Count -gt 1) {
    $lines = ($invokeCalls | ForEach-Object { $_.Extent.StartLineNumber }) -join ', '
    New-PrtgDoctorFinding -CheckId 'PSK0007' -Severity 'Error' `
      -Message "Invoke-PrtgSensor is called $($invokeCalls.Count) times (lines $lines); a sensor must emit exactly one response." `
      -Line $invokeCalls[1].Extent.StartLineNumber `
      -Recommendation 'Merge the logic into a single Invoke-PrtgSensor block.'
  } else {
    New-PrtgDoctorFinding -CheckId 'PSK0007' -Severity 'Pass' -Message 'At most one Invoke-PrtgSensor call.'
  }
}
