# Mutation fuzzer for the surfaces that must survive arbitrary/adversarial input:
#   A) the Doctor's script parser (Invoke-PrtgSensorDoctor) - must never throw, no matter
#      how broken the sensor script on disk is; it only parses, never executes.
#   B) the JSON output pipeline (New-PrtgChannel/Add-PrtgChannel/Write-PrtgOutput) - the
#      module's core promise is "always emit valid JSON, never breaks PRTG".
#   C) the sensor state store (Get/Save-PrtgSensorState) - fed bit-flipped clixml files to
#      catch both crashes and SILENT data loss (a corrupted property that nothing throws on).
#   D) error output (Write-PrtgError) - fed hand-built ErrorRecords, the one input shape a
#      plain catch-and-report never produces (see the Section D comment below).
#   E) the Invoke-PrtgSensor wrapper - fed script blocks that throw wild payloads, to check
#      the retry/-DryRun/-EnableLogging orchestration never lets an error through unhandled.
#   F) Write-PrtgLog - verifies its documented "never throws" contract under adversarial input.
param(
  [int]$Iterations = 3000,
  [int]$Seed = (Get-Random)
)

$ErrorActionPreference = 'Stop'
Write-Host "Fuzz seed: $Seed (rerun with -Seed $Seed to repeat the same value/number sequence)"

. (Join-Path (Join-Path $PSScriptRoot '..') (Join-Path 'Tests' '_TestHelpers.ps1'))
Import-BuiltPrtgModule

$failureDir = Join-Path $PSScriptRoot 'fuzz-failures'
# Stale repro files from a previous run would otherwise mix with this run's (same iteration
# indices get reused each time), making counts and saved artifacts ambiguous.
if (Test-Path -LiteralPath $failureDir) { Remove-Item -Path $failureDir -Recurse -Force }
New-Item -ItemType Directory -Path $failureDir -Force | Out-Null

$rand = [System.Random]::new($Seed)
$failures = 0

# --- Section A: Doctor parser, fed byte-mutated seed scripts --------------------------
Write-Host "--------------------------------"
Write-Host "Fuzzing Invoke-PrtgSensorDoctor ($Iterations mutated scripts)..."
Write-Host "--------------------------------"

$malformedDir = Join-Path (Join-Path $PSScriptRoot '..') (Join-Path 'Tests' (Join-Path 'Integration' 'malformed'))
$examplesDir = Join-Path $PSScriptRoot (Join-Path '..' 'Examples')
$seedFiles = @(Get-ChildItem -Path $malformedDir -Filter '*.ps1') + @(Get-ChildItem -Path $examplesDir -Filter '*.ps1')

function Get-MutatedBytes([byte[]]$Bytes, [System.Random]$Rand) {
  $out = [System.Collections.Generic.List[byte]]::new($Bytes)
  $mutations = $Rand.Next(1, 20)
  for ($m = 0; $m -lt $mutations; $m++) {
    if ($out.Count -eq 0) { $out.Add([byte]$Rand.Next(0, 256)); continue }
    $pos = $Rand.Next(0, $out.Count)
    switch ($Rand.Next(0, 4)) {
      0 { $out[$pos] = $out[$pos] -bxor (1 -shl $Rand.Next(0, 8)) }        # bit flip
      1 { $out.Insert($pos, [byte]$Rand.Next(0, 256)) }                    # insert
      2 { $out.RemoveAt($pos) }                                           # delete
      3 {                                                                  # duplicate a slice
        $len = [Math]::Min($Rand.Next(1, 16), $out.Count - $pos)
        if ($len -gt 0) { $out.InsertRange($pos, $out.GetRange($pos, $len)) }
      }
    }
  }
  $out.ToArray()
}

$doctorCrashes = 0
for ($i = 0; $i -lt $Iterations; $i++) {
  $seedFile = $seedFiles[$rand.Next(0, $seedFiles.Count)]
  $seedBytes = [IO.File]::ReadAllBytes($seedFile.FullName)
  $bytes = Get-MutatedBytes -Bytes $seedBytes -Rand $rand
  $tmp = Join-Path ([IO.Path]::GetTempPath()) "prtgfuzz_$i.ps1"
  [IO.File]::WriteAllBytes($tmp, $bytes)

  try {
    Invoke-PrtgSensorDoctor -ScriptPath $tmp -SkipEnvironmentChecks 6>$null | Out-Null
  } catch {
    $doctorCrashes++
    $failures++
    $keep = Join-Path $failureDir "doctor-crash-$i.ps1"
    Copy-Item -Path $tmp -Destination $keep -Force
    Write-Verbose "CRASH  seed=$($seedFile.Name) saved=$keep`n  $_"
  } finally {
    Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
  }
}
Write-Host "Doctor: $doctorCrashes crash(es) out of $Iterations."

# --- Section B: JSON output, fed adversarial channel values ---------------------------
Write-Host "--------------------------------"
Write-Host "Fuzzing New-PrtgChannel/Write-PrtgOutput JSON ($Iterations values)..."
Write-Host "--------------------------------"

$nastyChars = @(
  [char]0x0000, [char]0x001F, [char]0x0007, "`t", "`n", "`r",   # control chars
  '#', '"', '\', "'", '</script>', "`u{202E}",                  # PRTG/JSON/RTL-override specials
  [char]0xD800, "`u{1F4A9}"                                     # lone surrogate, astral emoji
)
$nastyNumbers = @(
  [double]::NaN, [double]::PositiveInfinity, [double]::NegativeInfinity,
  [double]::MaxValue, [double]::MinValue, [double]0, [double](-0.0)
)

function Get-FuzzString([System.Random]$Rand) {
  # 1-in-5 near/over the Format-PrtgMessage 2000-char truncation boundary; otherwise short.
  $len = if ($Rand.Next(0, 5) -eq 0) { $Rand.Next(1900, 2600) } else { $Rand.Next(0, 500) }
  $sb = [System.Text.StringBuilder]::new()
  for ($j = 0; $j -lt $len; $j++) {
    if ($Rand.Next(0, 3) -eq 0) {
      [void]$sb.Append($nastyChars[$Rand.Next(0, $nastyChars.Count)])
    } else {
      [void]$sb.Append([char]$Rand.Next(32, 0xFFFF))
    }
  }
  $sb.ToString()
}

$jsonBreaks = 0
for ($i = 0; $i -lt $Iterations; $i++) {
  $channelName = Get-FuzzString $rand
  if ($channelName.Length -eq 0) { $channelName = 'x' } # Channel can't be empty
  $value = if ($rand.Next(0, 2) -eq 0) { $nastyNumbers[$rand.Next(0, $nastyNumbers.Count)] } else { $rand.NextDouble() * [double]::MaxValue }
  $msg = Get-FuzzString $rand

  try {
    Clear-PrtgOutput
    New-PrtgChannel -Channel $channelName -Value $value -Float -LimitErrorMsg $(if ($msg) { $msg } else { 'x' }) |
      Add-PrtgChannel
    $json = Write-PrtgOutput
    $parsed = ConvertFrom-Json -InputObject $json -ErrorAction Stop

    # Format-PrtgMessage's contract: strip '#', truncate to 2000. Assert it, not just "no crash" -
    # a truncation off-by-one wouldn't throw, it would just silently violate the contract.
    $limitMsg = $parsed.prtg.result[0].LimitErrorMsg
    if ($null -ne $limitMsg -and ($limitMsg.Length -gt 2000 -or $limitMsg.Contains('#'))) {
      throw "LimitErrorMsg not truncated/stripped correctly (length=$($limitMsg.Length))"
    }
  } catch {
    if ($_.Exception.GetType().Name -eq 'ParameterBindingValidationException') {
      continue # expected rejection of empty/invalid-typed input, not a bug
    }
    $jsonBreaks++
    $failures++
    $repro = Join-Path $failureDir "json-break-$i.json"
    [PSCustomObject]@{ Channel = $channelName; Value = $value; LimitErrorMsg = $msg; Error = "$_" } |
      ConvertTo-Json -Depth 5 | Set-Content -Path $repro -Encoding UTF8
    Write-Verbose "BREAK  saved=$repro`n  $_"
  }
}
Write-Host "JSON output: $jsonBreaks break(s) out of $Iterations."

# --- Section C: sensor state, fed byte-mutated clixml files ---------------------------
Write-Host "--------------------------------"
Write-Host "Fuzzing Get-PrtgSensorState/Save-PrtgSensorState ($Iterations corrupt state files)..."
Write-Host "--------------------------------"

$stateDir = Join-Path ([IO.Path]::GetTempPath()) 'prtgfuzz_state'
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null

$seedStatePath = Join-Path $stateDir '_seed.clixml'
@([PSCustomObject]@{ Value = 1; Timestamp = [DateTime]::UtcNow }) | Export-Clixml -LiteralPath $seedStatePath -Depth 5
$goodStateBytes = [IO.File]::ReadAllBytes($seedStatePath)

$stateCrashes = 0
$stateSilent = 0
for ($i = 0; $i -lt $Iterations; $i++) {
  $key = "FuzzState$i"
  $file = Join-Path $stateDir "$key.clixml"

  $bytes = Get-MutatedBytes -Bytes $goodStateBytes -Rand $rand
  [IO.File]::WriteAllBytes($file, $bytes)

  try {
    Get-PrtgSensorState -Key $key -Path $stateDir -MaxAge (New-TimeSpan -Hours $rand.Next(0, 48)) `
      -Latest:($rand.Next(0, 2) -eq 0) -Default 0 -TimeoutSeconds 1 | Out-Null
  } catch {
    $stateCrashes++
    $failures++
    $keep = Join-Path $failureDir "state-crash-get-$i.clixml"
    Copy-Item -Path $file -Destination $keep -Force -ErrorAction SilentlyContinue
    Write-Verbose "CRASH  Get-PrtgSensorState saved=$keep`n  $_"
  }

  # No -MaxAge here, so the Timestamp filter (and its crash check above) never runs;
  # this only catches a corrupted Value, which nothing throws on. The seed always saves
  # Value = 1 (an [int]), so any surviving entry whose Value isn't an [int] - null,
  # wrong type, whatever the mutated bytes decoded to - is corruption Get-PrtgStateEntry's
  # {Value, Timestamp}-shape check let through silently. Same-type corruption (1 -> 5)
  # is undetectable here: Value has no schema, so it's indistinguishable from real data.
  try {
    $raw = Get-PrtgSensorState -Key $key -Path $stateDir -TimeoutSeconds 1
    if ($null -ne $raw) {
      $corrupt = @($raw | Where-Object { $_.Value -isnot [int] })
      if ($corrupt.Count -gt 0) {
        $stateSilent++
        $failures++
        $keep = Join-Path $failureDir "state-silent-$i.clixml"
        Copy-Item -Path $file -Destination $keep -Force -ErrorAction SilentlyContinue
        Write-Verbose "SILENT  Get-PrtgSensorState returned $($corrupt.Count) entry(ies) with a corrupted Value, no exception. saved=$keep"
      }
    }
  } catch {
    # Same corrupted file already counted by the crash check above; do not double-count.
  }

  try {
    Save-PrtgSensorState -Key $key -Value 'x' -Path $stateDir -TimeoutSeconds 1 | Out-Null
  } catch {
    $stateCrashes++
    $failures++
    $keep = Join-Path $failureDir "state-crash-save-$i.clixml"
    Copy-Item -Path $file -Destination $keep -Force -ErrorAction SilentlyContinue
    Write-Verbose "CRASH  Save-PrtgSensorState saved=$keep`n  $_"
  }

  Remove-Item -Path $file, "$file.lock" -Force -ErrorAction SilentlyContinue
}
Write-Host "State: $stateCrashes crash(es), $stateSilent silent corruption(s) out of $Iterations."

# --- Section D: error output, fed hand-built ErrorRecords -----------------------------
# A throw always has non-null InvocationInfo; a hand-built ErrorRecord never does.
Write-Host "--------------------------------"
Write-Host "Fuzzing Write-PrtgError JSON ($Iterations error records)..."
Write-Host "--------------------------------"

$errorBreaks = 0
for ($i = 0; $i -lt $Iterations; $i++) {
  $msg1 = Get-FuzzString $rand
  $msg2 = Get-FuzzString $rand
  $inner = [Exception]::new($(if ($msg1) { $msg1 } else { 'x' }))
  $outer = [Exception]::new($(if ($msg2) { $msg2 } else { 'x' }), $inner)
  $errRecord = [System.Management.Automation.ErrorRecord]::new(
    $outer, 'FuzzError', [System.Management.Automation.ErrorCategory]::NotSpecified, $null)

  try {
    $json = if ($rand.Next(0, 2) -eq 0) {
      Write-PrtgError -ErrorObject $errRecord
    } else {
      Write-PrtgError -ErrorString $(if ($msg2) { $msg2 } else { 'x' })
    }
    $parsed = ConvertFrom-Json -InputObject $json -ErrorAction Stop

    $text = $parsed.prtg.text
    if ($null -ne $text -and ($text.Length -gt 2000 -or $text.Contains('#'))) {
      throw "error text not truncated/stripped correctly (length=$($text.Length))"
    }
  } catch {
    $errorBreaks++
    $failures++
    $repro = Join-Path $failureDir "error-break-$i.json"
    [PSCustomObject]@{ Message1 = $msg1; Message2 = $msg2; Error = "$_" } |
      ConvertTo-Json -Depth 5 | Set-Content -Path $repro -Encoding UTF8
    Write-Verbose "BREAK  saved=$repro`n  $_"
  }
}
Write-Host "Write-PrtgError: $errorBreaks break(s) out of $Iterations."

# --- Section E: Invoke-PrtgSensor's wrapper, fed script blocks that throw wild payloads --
# Targets the retry/-DryRun/-EnableLogging orchestration, not payload parsing.
Write-Host "--------------------------------"
Write-Host "Fuzzing Invoke-PrtgSensor wrapper ($Iterations throwing script blocks)..."
Write-Host "--------------------------------"

$logDir = Join-Path ([IO.Path]::GetTempPath()) 'prtgfuzz_logs'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

$sensorBreaks = 0
for ($i = 0; $i -lt $Iterations; $i++) {
  $s1 = Get-FuzzString $rand
  $s2 = Get-FuzzString $rand
  $payload = switch ($rand.Next(0, 8)) {
    0 { if ($s1) { $s1 } else { 'x' } }
    1 { [Exception]::new($(if ($s1) { $s1 } else { 'x' })) }
    2 { [Exception]::new($(if ($s2) { $s2 } else { 'x' }), [Exception]::new($(if ($s1) { $s1 } else { 'x' }))) }
    3 { $rand.Next([int]::MinValue, [int]::MaxValue) }
    4 { $null }
    5 { @{ code = $rand.Next(); message = $s1 } }
    6 { @(1, $s1, $null) }
    7 { [PSCustomObject]@{ Weird = $s1 } }
  }
  $block = { throw $payload }

  $dryRun = $rand.Next(0, 2) -eq 0
  $enableLogging = $rand.Next(0, 2) -eq 0
  $params = @{ ScriptBlock = $block; RetryCount = $rand.Next(0, 3); RetryDelaySeconds = 0 }
  if ($dryRun) { $params.DryRun = $true }
  if ($enableLogging) { $params.EnableLogging = $true; $params.LogPath = $logDir; $params.MaxLogs = 5 }

  try {
    $result = Invoke-PrtgSensor @params
    if ($dryRun) {
      # -DryRun's documented contract is "rethrow the original error" - returning
      # normally instead means the wrapper silently swallowed a failing block.
      $sensorBreaks++
      $failures++
      $repro = Join-Path $failureDir "sensor-swallowed-$i.json"
      [PSCustomObject]@{ Payload = "$payload"; Params = ($params.Keys -join ',') } |
        ConvertTo-Json -Depth 5 | Set-Content -Path $repro -Encoding UTF8
      Write-Verbose "BREAK  DryRun did not rethrow, saved=$repro"
    } else {
      $parsed = ConvertFrom-Json -InputObject $result -ErrorAction Stop
      if ($parsed.prtg.error -ne 1) {
        $sensorBreaks++
        $failures++
        $repro = Join-Path $failureDir "sensor-wrong-shape-$i.json"
        $result | Set-Content -Path $repro -Encoding UTF8
        Write-Verbose "BREAK  non-error JSON for a throwing block, saved=$repro"
      }
    }
  } catch {
    if (-not $dryRun) {
      $sensorBreaks++
      $failures++
      $repro = Join-Path $failureDir "sensor-crash-$i.txt"
      "Payload: $payload`nParams: $($params.Keys -join ',')`nError: $_" | Set-Content -Path $repro -Encoding UTF8
      Write-Verbose "CRASH  Invoke-PrtgSensor let an exception escape (non-DryRun), saved=$repro`n  $_"
    }
    # DryRun IS expected to throw here - that's the documented behavior, not a finding.
  }
}
Write-Host "Invoke-PrtgSensor: $sensorBreaks break(s) out of $Iterations."

# --- Section F: Write-PrtgLog, fed adversarial message content ------------------------
# Docs state it never throws; this verifies that. Writes to the real default log location -
# no public way to redirect a standalone call, but it's one file per run, self-bounding.
Write-Host "--------------------------------"
Write-Host "Fuzzing Write-PrtgLog ($Iterations messages)..."
Write-Host "--------------------------------"

$logBreaks = 0
$levels = @('Info', 'Warning', 'Error', 'Debug')
for ($i = 0; $i -lt $Iterations; $i++) {
  $msg = Get-FuzzString $rand
  $level = $levels[$rand.Next(0, $levels.Count)]
  try {
    Write-PrtgLog -Message $msg -Level $level
  } catch {
    $logBreaks++
    $failures++
    $repro = Join-Path $failureDir "log-break-$i.txt"
    "Message: $msg`nLevel: $level`nError: $_" | Set-Content -Path $repro -Encoding UTF8
    Write-Verbose "CRASH  Write-PrtgLog threw despite its never-throw contract, saved=$repro`n  $_"
  }
}
Write-Host "Write-PrtgLog: $logBreaks break(s) out of $Iterations."

Write-Host ''
if ($failures -gt 0) {
  throw "Fuzzing found $failures issue(s) across sections A-F. Repro artifacts saved under $failureDir (seed was $Seed)."
}
Write-Host "Fuzzing clean: all six sections held their contracts (seed was $Seed)."
