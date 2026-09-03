function Test-PrtgDoctorKitImport {
  <#
  .SYNOPSIS
    Whether an Import-Module call imports PrtgSensorKit itself, by name or by manifest path.
  #>
  [CmdletBinding()]
  [OutputType([bool])]
  param(
    [Parameter(Mandatory = $true)]
    [System.Management.Automation.Language.CommandAst]$Call
  )

  [bool]@(Get-PrtgDoctorLiteralArgument -Call $Call | Where-Object {
      $_ -match '(^|[\\/])PrtgSensorKit(\.psd1|\.psm1)?$'
    })
}
