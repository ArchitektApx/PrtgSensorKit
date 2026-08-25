function Test-PrtgDoctorPSK0004 {
  <#
  .SYNOPSIS
    PSK0004: Restart-* before Invoke-PrtgSensor and before other imports
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Parsed
  )

  $invokeCalls = Get-PrtgDoctorCall -Context $Parsed -Name 'Invoke-PrtgSensor'
  $restartCalls = Get-PrtgDoctorCall -Context $Parsed -Name @('Restart-As64BitPowershell', 'Restart-InPwsh')
  $importCalls = Get-PrtgDoctorCall -Context $Parsed -Name 'Import-Module'
  $otherImports = @($importCalls | Where-Object { -not (Test-PrtgDoctorKitImport -Call $_) })

  $restartsOutside = @($restartCalls | Where-Object { -not (Test-PrtgDoctorInSensorBlock -Context $Parsed -Node $_) })
  if ($restartCalls.Count -eq 0) {
    New-PrtgDoctorFinding -CheckId 'PSK0004' -Severity 'Pass' -Message 'No Restart-* helpers used.'
  } else {
    $violations = [System.Collections.Generic.List[object]]::new()
    $firstInvoke = if ($invokeCalls.Count -gt 0) { ($invokeCalls | ForEach-Object { $_.Extent.StartOffset } | Measure-Object -Minimum).Minimum } else { $null }
    foreach ($call in $restartsOutside) {
      if ($null -ne $firstInvoke -and $call.Extent.StartOffset -gt $firstInvoke) {
        $violations.Add((New-PrtgDoctorFinding -CheckId 'PSK0004' -Severity 'Error' `
          -Message "'$($call.GetCommandName())' is called after Invoke-PrtgSensor; the sensor has already emitted its response by then." `
          -Line $call.Extent.StartLineNumber `
          -Recommendation 'Call Restart-* before Invoke-PrtgSensor.'))
      }
      $importsBefore = @($otherImports | Where-Object { $_.Extent.StartOffset -lt $call.Extent.StartOffset })
      if ($importsBefore.Count -gt 0) {
        $violations.Add((New-PrtgDoctorFinding -CheckId 'PSK0004' -Severity 'Error' `
          -Message "'Import-Module' (other than PrtgSensorKit) runs before '$($call.GetCommandName())' on line $($call.Extent.StartLineNumber). The import happens in the wrong host and can fail before the relaunch." `
          -Line $importsBefore[0].Extent.StartLineNumber `
          -Recommendation 'Import dependency modules after the Restart-* call (only Import-Module PrtgSensorKit may come first).'))
      }
    }
    if ($violations.Count -gt 0) { $violations }
    else {
      New-PrtgDoctorFinding -CheckId 'PSK0004' -Severity 'Pass' -Message 'Restart-* calls are positioned correctly.'
    }
  }
}
