function Invoke-PrtgDoctorModuleProbe {
  <#
  .SYNOPSIS
    Whether another PowerShell host can resolve a module.
  .DESCRIPTION
    The probe runs out of process: each host has its own PSModulePath.
  #>
  [CmdletBinding()]
  [OutputType([bool])]
  param(
    [Parameter(Mandatory = $true)][string]$Executable,
    [Parameter(Mandatory = $true)][string]$ModuleName
  )

  # $ModuleName comes from the analyzed script and is spliced into a child command line, so
  # only a plain module name is probed; anything else is reported as not resolvable.
  if ($ModuleName -notmatch '^[A-Za-z0-9._-]+$') {
    Write-Verbose "Invoke-PrtgDoctorModuleProbe: refusing to probe suspicious module name '$ModuleName'."
    return $false
  }

  try {
    # A membership test against the marker: stray stdout from the child host (banners,
    # console hooks) must not turn a resolvable module into a false 'not resolvable'.
    $output = & $Executable -NoProfile -NonInteractive -Command "if ([bool](Get-Module -ListAvailable -Name '$ModuleName')) { 'PSK_MODULE_FOUND' }" 2>$null
    return [bool](@($output) | Where-Object { "$_".Trim() -eq 'PSK_MODULE_FOUND' })
  } catch {
    return $false
  }
}
