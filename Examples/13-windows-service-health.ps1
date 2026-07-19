<#
.SYNOPSIS
  One up/down channel per Windows service.
.DESCRIPTION
  Monitors a list of Windows services (from a sensor parameter) and emits a boolean channel per
  service, plus a message summarizing how many are down. Shows the "loop over inputs, one channel
  each, roll up a summary" pattern combined with value lookups.
.NOTES
  Requires the PrtgSensorKit module installed on the probe. Windows (uses Get-Service).
#>
[CmdletBinding()]
param(
  [string[]]$Service = @('Spooler', 'W32Time')
)

Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  $down = 0
  foreach ($name in $Service) {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    $running = [int]($svc -and $svc.Status -eq 'Running')
    if (-not $running) { $down++ }

    New-PrtgChannel -Channel $name -Value $running `
      -ValueLookup 'prtg.standardlookups.boolean' -NotifyChanged |
      Add-PrtgChannel
  }

  if ($down) { Set-PrtgMessage "$down monitored service(s) not running" }
  else { Set-PrtgMessage 'All monitored services running' }
}
