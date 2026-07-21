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

    Optional extras:

    - -RetryCount re-runs a throwing block up to N additional times (with an optional
      -RetryDelaySeconds pause) before giving up; the sensor message or error text notes
      the retries that were used.
    - -ForceModernTls switches the process to TLS 1.2/1.3 before your block runs, which
      Windows PowerShell 5.1 often needs for web requests.
    - -DryRun returns the sensor result as an inspectable object instead of JSON, for
      debugging in a normal console.

  .PARAMETER ScriptBlock
    The sensor logic. Add one or more channels and set the message here; the block may contain
    any logic (loops, function calls, etc.). The wrapper emits the single result.

  .PARAMETER DryRun
    Debugging aid. Instead of emitting the PRTG JSON string, returns the sensor result as a
    PSCustomObject (the same 'prtg' tree PRTG would receive), so you can capture it in a
    variable and inspect channels and message as objects. If the block throws, the original
    error is rethrown with full details instead of being flattened into a PRTG error
    response. Execution is otherwise identical to a real run (clean state, output guard,
    retries). Remove -DryRun before deploying - a deployed dry run would not emit valid
    PRTG JSON.

  .PARAMETER RetryCount
    Number of ADDITIONAL attempts when the script block throws (total attempts =
    RetryCount + 1). Default 0 (no retries). The output state is cleared before every
    attempt, so a failed partial attempt never leaks channels into the next one. When the
    block eventually succeeds after retries, '(n/RetryCount retries attempted)' is appended
    to the sensor message; when all attempts fail, the error text is prefixed with
    'unsuccessful after RetryCount retries:'. Keep (RetryCount + 1) * (block runtime +
    RetryDelaySeconds) below the PRTG sensor timeout, or PRTG kills the sensor first.

  .PARAMETER RetryDelaySeconds
    Seconds to wait between attempts (not before the first, not after the last). Default 0.
    Only meaningful together with -RetryCount.

  .PARAMETER ForceModernTls
    Sets [Net.ServicePointManager]::SecurityProtocol to TLS 1.2 (plus TLS 1.3 when the
    runtime supports it) before running your block, replacing the previous protocol set.
    Windows PowerShell 5.1 defaults can lack TLS 1.2, which makes HTTPS requests fail
    against modern endpoints. The setting is process-wide and is not restored afterwards;
    sensor processes are short-lived. Harmless on PowerShell 7+, where the defaults are
    already modern.

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

  .EXAMPLE
    Invoke-PrtgSensor -ForceModernTls -RetryCount 2 -RetryDelaySeconds 5 {
      $data = Invoke-RestMethod -Uri 'https://api.example.com/health' -TimeoutSec 10
      New-PrtgChannel -Channel 'Latency' -Value $data.latencyMs -Unit TimeResponse | Add-PrtgChannel
      Set-PrtgMessage $data.status
    }

    Enables TLS 1.2/1.3 and retries a flaky endpoint up to two extra times, five seconds
    apart, before reporting an error to PRTG.

  .EXAMPLE
    $result = Invoke-PrtgSensor -DryRun {
      New-PrtgChannel -Channel 'A' -Value 1 | Add-PrtgChannel
      Set-PrtgMessage 'ok'
    }
    $result.prtg.result | Format-Table

    Debugging in a normal console: returns the sensor result as an object instead of JSON,
    so channels and message can be inspected directly.

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
    [scriptblock]$ScriptBlock,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 100)]
    [int]$RetryCount = 0,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 3600)]
    [int]$RetryDelaySeconds = 0,

    [Parameter(Mandatory = $false)]
    [switch]$ForceModernTls
  )

  $ErrorActionPreference = 'Stop'

  if ($ForceModernTls) { Set-PrtgModernTls }

  # Attempt loop: $retriesUsed counts FAILED attempts so far. The block runs at most
  # RetryCount + 1 times; output state is cleared before every attempt so a failed partial
  # attempt cannot leak channels or a message into the next one.
  $retriesUsed = 0
  $lastError = $null

  while ($true) {
    Clear-PrtgOutput
    try {
      # Merge the information stream into success, then discard both so stray output from the
      # user's code never reaches stdout. Terminating errors still propagate to the catch below.
      & $ScriptBlock 6>&1 | Out-Null
      $lastError = $null
      break
    } catch {
      $lastError = $_
      if ($retriesUsed -ge $RetryCount) { break }
      $retriesUsed++
      if ($RetryDelaySeconds -gt 0) { Start-Sleep -Seconds $RetryDelaySeconds }
    }
  }

  if ($null -ne $lastError) {
    # All attempts failed. A dry run surfaces the real error for debugging; a real run
    # emits the PRTG error response, prefixed with the retry summary when retries were used.
    if ($DryRun) { throw $lastError }
    if ($RetryCount -gt 0) {
      Write-PrtgError -ErrorString "unsuccessful after $RetryCount retries: $(Format-PrtgErrorText -ErrorObject $lastError)"
    } else {
      $lastError | Write-PrtgError
    }
    return
  }

  if ($retriesUsed -gt 0) {
    $suffix = "($retriesUsed/$RetryCount retries attempted)"
    $message = Get-PrtgMessage
    if ([string]::IsNullOrEmpty($message)) {
      Set-PrtgMessage $suffix
    } else {
      Set-PrtgMessage "$message $suffix"
    }
  }

  if ($DryRun) {
    # Round-trip through JSON so the caller inspects exactly what PRTG would receive and
    # mutating the returned object cannot touch the module-scope output state.
    return ($script:OutputObject | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
  }

  Write-PrtgOutput
}
