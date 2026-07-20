<#
.SYNOPSIS
  Reading the current sensor message back and appending to it.
.DESCRIPTION
  To build the Sensors Message across multiple steps, read the
  current text with Get-PrtgMessage, modify it as you want,
  and then Set-PrtgMessage the modified string.
.NOTES
  Requires the PrtgSensorKit module installed on the probe.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  $services = 'Spooler', 'BITS', 'W32Time'
  $down = 0

  foreach ($name in $services) {
    $service = Get-Service -Name $name -ErrorAction Stop
    $isRunning = $service.Status -eq 'Running'

    if ($isRunning -eq $false) {
      $down++
      Set-PrtgMessage "$(Get-PrtgMessage)$name is $($service.Status). ".Trim()
    }

    New-PrtgChannel -Channel $name -Value ([int]$isRunning) | Add-PrtgChannel
  }

  if ($down -eq 0) {
    Set-PrtgMessage 'All services running'
  }
}
