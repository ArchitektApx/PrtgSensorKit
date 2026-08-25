function Test-PrtgDoctorPSK0002 {
  <#
  .SYNOPSIS
    PSK0002: Import-Module PrtgSensorKit before first kit command
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Parsed
  )

  $commandAsts = @($Parsed.CommandAsts)
  $importCalls = Get-PrtgDoctorCall -Context $Parsed -Name 'Import-Module'
  $kitImports = @($importCalls | Where-Object { Test-PrtgDoctorKitImport -Call $_ })

  $kitCommandPattern = '^(?:\w+-Prtg\w+|Restart-As64BitPowershell|Restart-InPwsh)$'
  $kitUsages = @($commandAsts | Where-Object { $_.GetCommandName() -match $kitCommandPattern })
  if ($kitUsages.Count -eq 0) {
    New-PrtgDoctorFinding -CheckId 'PSK0002' -Severity 'Info' `
      -Message 'No PrtgSensorKit commands found in the script.' `
      -Recommendation 'Nothing to check; is this really a PrtgSensorKit sensor script?'
  } elseif ($kitImports.Count -eq 0) {
    New-PrtgDoctorFinding -CheckId 'PSK0002' -Severity 'Warning' `
      -Message "No 'Import-Module PrtgSensorKit' found. Module autoloading may cover this, but an explicit import is more predictable under PRTG." `
      -Line $kitUsages[0].Extent.StartLineNumber `
      -Recommendation "Add 'Import-Module PrtgSensorKit' at the top of the script."
  } else {
    $firstImport = ($kitImports | ForEach-Object { $_.Extent.StartOffset } | Measure-Object -Minimum).Minimum
    $firstUsage = @($kitUsages | Where-Object { $_.Extent.StartOffset -lt $firstImport })
    if ($firstUsage.Count -gt 0) {
      New-PrtgDoctorFinding -CheckId 'PSK0002' -Severity 'Warning' `
        -Message "'$($firstUsage[0].GetCommandName())' is used before 'Import-Module PrtgSensorKit'." `
        -Line $firstUsage[0].Extent.StartLineNumber `
        -Recommendation 'Move the import above the first PrtgSensorKit command.'
    } else {
      New-PrtgDoctorFinding -CheckId 'PSK0002' -Severity 'Pass' -Message 'PrtgSensorKit is imported before it is used.'
    }
  }
}
