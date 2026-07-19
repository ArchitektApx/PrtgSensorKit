<#
.SYNOPSIS
  Advanced: replace the whole output object with a pre-built structure.
.DESCRIPTION
  Most sensors should build output with New-PrtgChannel / Add-PrtgChannel. Set-PrtgOutput is the
  escape hatch when you already have a complete PRTG-shaped object (assembled elsewhere, cached,
  or produced by another tool). The object must have the PRTG shape: a 'prtg' property with a
  'result' list and a 'text' string. Emit it with Write-PrtgOutput.
.NOTES
  Requires the PrtgSensorKit module installed on the probe.
#>
Import-Module PrtgSensorKit

$custom = [PSCustomObject]@{
  prtg = [PSCustomObject]@{
    result = [System.Collections.ArrayList]@(
      (New-PrtgChannel -Channel 'Prebuilt A' -Value 10),
      (New-PrtgChannel -Channel 'Prebuilt B' -Value 20 -Unit Percent)
    )
    text = 'Assembled with Set-PrtgOutput'
  }
}

Set-PrtgOutput $custom
Write-PrtgOutput
