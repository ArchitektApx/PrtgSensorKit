function Invoke-PrtgDoctorModuleProbe {
  # Asks another PowerShell host whether it can resolve a module. Out-of-process on
  # purpose: each host has its own PSModulePath and the Doctor must never guess it.
  # Isolated in its own function so tests can mock it.
  [CmdletBinding()]
  [OutputType([bool])]
  param(
    [Parameter(Mandatory = $true)][string]$Executable,
    [Parameter(Mandatory = $true)][string]$ModuleName
  )

  # SECURITY GATE: $ModuleName comes from string literals parsed out of the ANALYZED
  # sensor script and is spliced into a child-process command line below. Without this
  # allowlist, a crafted literal (embedded quote) would execute arbitrary code in the
  # child - breaking the Doctor's guarantee that it never executes the analyzed script.
  # Real module names match this pattern; anything else is reported as not resolvable.
  if ($ModuleName -notmatch '^[A-Za-z0-9._-]+$') {
    Write-Verbose "Invoke-PrtgDoctorModuleProbe: refusing to probe suspicious module name '$ModuleName'."
    return $false
  }

  try {
    # Membership test against a marker string, not a scalar comparison: stray extra
    # stdout lines from the child host (banners, console hooks) must not turn a
    # resolvable module into a false 'not resolvable'.
    $output = & $Executable -NoProfile -NonInteractive -Command "if ([bool](Get-Module -ListAvailable -Name '$ModuleName')) { 'PSK_MODULE_FOUND' }" 2>$null
    return [bool](@($output) | Where-Object { "$_".Trim() -eq 'PSK_MODULE_FOUND' })
  } catch {
    return $false
  }
}
