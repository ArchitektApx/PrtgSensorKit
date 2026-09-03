function Invoke-PrtgRelaunch {
  <#
  .SYNOPSIS
    Re-launches the calling sensor script in another PowerShell host and exits with its code.
  .PARAMETER Invocation
    The calling sensor script's InvocationInfo, captured by the Restart-* function.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Executable,

    [Parameter(Mandatory = $true)]
    [System.Management.Automation.InvocationInfo]$Invocation
  )

  $scriptPath = if ($Invocation.MyCommand -and $Invocation.MyCommand.Path) {
    $Invocation.MyCommand.Path
  } else {
    [string]$Invocation.InvocationName
  }
  if (-not $scriptPath) {
    throw "cannot determine the sensor script path to relaunch. Call Restart-* from a .ps1 file at the top level."
  }

  $newArgs = [System.Collections.Generic.List[string]]::new()
  '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass' | ForEach-Object { $newArgs.Add($_) }
  # -File preserves the exit code; -Command does not.
  $newArgs.Add('-File')
  $newArgs.Add($scriptPath)

  # Forward the sensor's parameters so they survive the relaunch (PRTG "Parameters" field).
  foreach ($kv in $Invocation.BoundParameters.GetEnumerator()) {
    $val = $kv.Value
    if ($val -is [switch]) {
      if ($val.IsPresent) { $newArgs.Add("-$($kv.Key)") }
    } elseif ($val -is [System.Collections.IEnumerable] -and $val -isnot [string]) {
      $newArgs.Add("-$($kv.Key)")
      foreach ($item in $val) { $newArgs.Add([string]$item) }
    } else {
      $newArgs.Add("-$($kv.Key)")
      $newArgs.Add([string]$val)
    }
  }
  foreach ($u in $Invocation.UnboundArguments) { $newArgs.Add([string]$u) }

  & $Executable @newArgs
  exit $LASTEXITCODE
}
