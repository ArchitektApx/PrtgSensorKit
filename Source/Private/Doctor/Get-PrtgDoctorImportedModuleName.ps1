function Get-PrtgDoctorImportedModuleName {
  <#
  .SYNOPSIS
    The statically imported module names of the analyzed script.
  .DESCRIPTION
    Reads literal Import-Module arguments (positional or -Name, array literals unwrapped) and
    #Requires -Modules. Variable-based imports are out of scope.
  #>
  [CmdletBinding()]
  [OutputType([string[]])]
  param(
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Parsed
  )

  $names = [System.Collections.Generic.List[string]]::new()

  foreach ($requirement in @($Parsed.Ast.ScriptRequirements.RequiredModules)) {
    if ($requirement.Name) { $names.Add($requirement.Name) }
  }

  foreach ($call in @(Get-PrtgDoctorCall -Context $Parsed -Name 'Import-Module')) {
    foreach ($value in @(Get-PrtgDoctorLiteralArgument -Call $call)) { $names.Add($value) }
  }

  # A module path reduces to its last segment; both separators are split by hand because the
  # Doctor may analyze a Windows script on any platform. Only file extensions are stripped.
  @($names | ForEach-Object {
    ($_ -split '[\\/]')[-1] -replace '\.(psd1|psm1|dll)$', ''
  } | Select-Object -Unique)
}
