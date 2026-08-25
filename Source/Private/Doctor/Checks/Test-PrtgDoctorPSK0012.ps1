function Test-PrtgDoctorPSK0012 {
  <#
  .SYNOPSIS
    PSK0012: channel limits are a creation-time snapshot
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Parsed
  )

  $channelCalls = Get-PrtgDoctorCall -Context $Parsed -Name 'New-PrtgChannel'
  $limitCalls = @($channelCalls | Where-Object {
    @($_.CommandElements | Where-Object {
      $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -like 'Limit*'
    }).Count -gt 0
  })
  if ($limitCalls.Count -gt 0) {
    New-PrtgDoctorFinding -CheckId 'PSK0012' -Severity 'Info' `
      -Message 'New-PrtgChannel is called with Limit* parameters. PRTG copies limit values into the channel settings ONLY when the sensor is first created; editing them in the script later has no effect on an existing sensor.' `
      -Line $limitCalls[0].Extent.StartLineNumber `
      -Recommendation 'To change limits on a deployed sensor, edit the channel settings in the PRTG UI or delete and recreate the sensor.'
  } else {
    New-PrtgDoctorFinding -CheckId 'PSK0012' -Severity 'Pass' -Message 'No channel limit parameters used.'
  }
}
