function Test-PrtgDoctorInSensorBlock {
  # Whether a node sits inside one of the script blocks handed to Invoke-PrtgSensor, by source
  # offset against the extents collected on the parse context.
  [CmdletBinding()]
  [OutputType([bool])]
  param(
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Context,

    [Parameter(Mandatory = $true)]
    [System.Management.Automation.Language.Ast]$Node
  )

  foreach ($extent in $Context.SensorBlockExtents) {
    if ($Node.Extent.StartOffset -gt $extent.StartOffset -and $Node.Extent.EndOffset -le $extent.EndOffset) { return $true }
  }
  $false
}
