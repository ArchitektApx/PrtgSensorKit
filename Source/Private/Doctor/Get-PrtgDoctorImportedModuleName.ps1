function Get-PrtgDoctorImportedModuleName {
  # Collects STATICALLY imported module names: literal Import-Module arguments (positional
  # or -Name, including array literals) and #Requires -Modules. Dynamic/variable-based
  # imports are intentionally out of scope (documented in the Doctor's PSK0104 check).
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

  # Module paths count as static too; reduce them to the module name. Split on both
  # separators by hand: the Doctor may analyze a Windows sensor script on any platform,
  # where .NET would not treat '\' as a separator. Only module FILE extensions are
  # stripped - a dotted module NAME like 'Az.Accounts' must keep its dot.
  @($names | ForEach-Object {
    ($_ -split '[\\/]')[-1] -replace '\.(psd1|psm1|dll)$', ''
  } | Select-Object -Unique)
}
