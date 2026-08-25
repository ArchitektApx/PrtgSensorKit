function Test-PrtgDoctorKitImport {
  # Whether an Import-Module call imports PrtgSensorKit itself, by name or by manifest path.
  # Literal arguments (scalar or array) are resolved by the shared argument helper so this check
  # and the environment's import scan can never disagree on what counts as an import.
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
