function Invoke-PrtgSensor {
  <#
  .SYNOPSIS
    Runs a sensor script block and emits exactly one valid PRTG response.

  .DESCRIPTION
    The batteries-included way to write a sensor. Wrap your channel-building logic in a script
    block and Invoke-PrtgSensor handles all the boilerplate for you:

    - starts from a clean output state (calls Clear-PrtgOutput),
    - sets $ErrorActionPreference to 'Stop' so any failure is caught,
    - runs your block with its success and information output discarded, so a stray
      Write-Host or an un-captured command result cannot corrupt the sensor output,
    - emits the PRTG JSON once on success, or a PRTG error response if your block throws.

    Inside the block, build channels with New-PrtgChannel | Add-PrtgChannel and set the message
    with Set-PrtgMessage. Do NOT call Write-PrtgOutput / Write-PrtgError yourself and do NOT
    write to the output stream (see the note below) - the wrapper produces the single response.

  .PARAMETER ScriptBlock
    The sensor logic. Add one or more channels and set the message here; the block may contain
    any logic (loops, function calls, etc.). The wrapper emits the single result.

  .EXAMPLE
    Invoke-PrtgSensor {
      New-PrtgChannel -Channel 'CPU' -Value (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue -Unit Percent -Float | Add-PrtgChannel
      Set-PrtgMessage 'ok'
    }

    Builds a single channel and emits the PRTG JSON. If the block throws, a PRTG error is emitted instead.

  .EXAMPLE
    Invoke-PrtgSensor {
      # The block can contain any logic and add as many channels as you need (up to PRTG's 50).
      foreach ($disk in Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 3') {
        $freePct = [math]::Round($disk.FreeSpace / $disk.Size * 100, 1)
        New-PrtgChannel -Channel "Free % $($disk.DeviceID)" -Value $freePct -Unit Percent -Float `
          -LimitMinWarning 15 -LimitMinError 5 -LimitMode $true | Add-PrtgChannel
      }
      Set-PrtgMessage 'Disk free space per volume'
    }

    Builds one channel per fixed disk in a loop. Multiple channels and arbitrarily complex block
    logic (loops, function calls, remote queries) are fully supported - the wrapper only handles
    the surrounding error handling and single-response output.

  .NOTES
    A PRTG EXE/Script Advanced sensor reads its result from the process standard output, which
    must contain only the JSON. Anything your block writes to the output stream (a bare
    Write-Host, Write-Output, or an un-captured command that returns objects) would corrupt it,
    so the wrapper discards that output for you. For debugging, log to a file instead - never to
    the output stream.

    Import-Module works normally inside the block. Restart-As64BitPowershell / Restart-InPwsh do
    NOT: they relaunch the sensor as a child process, whose output would be discarded by this
    wrapper's output guard. Call them at the top of your script, BEFORE Invoke-PrtgSensor.

  .LINK
    New-PrtgChannel
  .LINK
    Write-PrtgError
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true, Position = 0)]
    [scriptblock]$ScriptBlock
  )

  $ErrorActionPreference = 'Stop'
  Clear-PrtgOutput

  try {
    # Merge the information stream into success, then discard both so stray output from the
    # user's code never reaches stdout. Terminating errors still propagate to the catch below.
    & $ScriptBlock 6>&1 | Out-Null
    Write-PrtgOutput
  } catch {
    $_ | Write-PrtgError
  }
}
