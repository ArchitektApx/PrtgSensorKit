<#
.SYNOPSIS
  Low-level API without the Invoke-PrtgSensor wrapper.
.DESCRIPTION
  When you need full control, build the output by hand: Clear-PrtgOutput to start clean, add
  channels, set the message, then Write-PrtgOutput exactly once on the happy path - or
  Write-PrtgError once on the error path. There's no output guard here, so every command's
  result must be piped into a channel, assigned to a variable, or sent to Out-Null, and each
  path must short-circuit the script with exit so nothing runs after the response is emitted.
  Most sensors should prefer Invoke-PrtgSensor (see the other examples); this shows what it does
  under the hood.
.NOTES
  Requires the PrtgSensorKit module installed on the probe.
#>
Import-Module PrtgSensorKit

# Always call Clear-PrtgOutput before defining any channels or setting a messages
# to generate an empty output object in this scope.
Clear-PrtgOutput

try {
  $items = Get-ChildItem -Path 'C:\Temp'

  New-PrtgChannel -Channel 'Items' -Value $items.Count | Add-PrtgChannel
} catch {
  # Use -ErrorString to have full control over the error message.
  Write-PrtgError -ErrorString 'My custom error message'
  exit 1 # short-circuit the error path
}

# some other code on your happy path 
# ...

# Put Write-PrtgOutput at the end of your script to emit the final sensor JSON on the happy path.
Write-PrtgOutput
