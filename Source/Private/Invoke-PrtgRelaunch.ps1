function Invoke-PrtgRelaunch {
  # Re-launches the CALLING sensor script in another PowerShell host, then exits with its code.
  # Uses the caller's InvocationInfo (captured by the Restart-* function from the call stack)
  # rather than [Environment]::GetCommandLineArgs(): PRTG does not start sensors with
  # '-File script.ps1', so the process command line does not contain the script, but the caller's
  # InvocationInfo always exposes the script path and the parameters it was called with.
  #
  # Always relaunches via -File (not -Command): a script invoked as `powershell -Command "& 'x.ps1'"`
  # that calls `exit N` reports exit code 1, while -File reports N. -File preserves the exit code.
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
