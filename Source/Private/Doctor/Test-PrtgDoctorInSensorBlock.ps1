function Test-PrtgDoctorInSensorBlock {
  <#
  .SYNOPSIS
    Whether a node sits inside one of the script blocks handed to Invoke-PrtgSensor.
  #>
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
