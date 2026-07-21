function New-PrtgDoctorFinding {
  # Shared finding constructor for all Doctor checks (script and environment).
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Creates an in-memory result object only; no system state is changed.')]
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$CheckId,
    [Parameter(Mandatory = $true)][ValidateSet('Pass', 'Info', 'Warning', 'Error')][string]$Severity,
    [Parameter(Mandatory = $true)][string]$Message,
    [Parameter(Mandatory = $false)][object]$Line = $null,
    [Parameter(Mandatory = $false)][string]$Recommendation = ''
  )

  [PSCustomObject]@{
    CheckId        = $CheckId
    Severity       = $Severity
    Message        = $Message
    Line           = $Line
    Recommendation = $Recommendation
  }
}

function Test-PrtgDoctorScript {
  <#
  .SYNOPSIS
    Runs the AST-based Doctor checks (PSK0001-PSK0010) against a parsed sensor script.
  .DESCRIPTION
    Pure static analysis: works everywhere, never executes the target script. Each check
    emits exactly one finding (Pass or its issue severity); position-sensitive checks may
    emit one finding per offending call site instead. The checks are assembled as a
    registry of script blocks sharing one context, so future checks are additive.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Parsed
  )

  $findings = [System.Collections.Generic.List[object]]::new()

  # --- PSK0001: the script must parse ---------------------------------------------------
  if ($Parsed.ParseErrors.Count -gt 0) {
    foreach ($parseError in $Parsed.ParseErrors) {
      $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0001' -Severity 'Error' `
        -Message "Syntax error: $($parseError.Message)" `
        -Line $parseError.Extent.StartLineNumber `
        -Recommendation 'Fix the syntax error; PRTG would report this sensor as failed on every scan.'))
    }
  } else {
    $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0001' -Severity 'Pass' -Message 'Script parses without syntax errors.'))
  }

  if ($null -eq $Parsed.Ast) { return $findings.ToArray() }

  # --- Shared context for all remaining checks ------------------------------------------
  $ast = $Parsed.Ast
  $commandAsts = @($Parsed.CommandAsts)

  $getCallsByName = {
    param([string[]]$Names)
    @($commandAsts | Where-Object { $Names -contains $_.GetCommandName() })
  }

  # Every assignment in the script; used to statically resolve splatted hashtables and
  # variable-based values in the checks below.
  $assignments = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true))
  $getAssignmentsTo = {
    param([string]$variableName)
    @($assignments | Where-Object {
      $_.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
      $_.Left.VariablePath.UserPath -eq $variableName
    })
  }

  # A switch counts as ENABLED ('on') only when present without an argument (-X) or with
  # an argument other than a literal $false (-X:$true, -X:$flag). '-X:$false' is 'off'.
  # Splatted literal hashtables are resolved too; a splat the Doctor cannot resolve
  # statically yields 'unknown' so checks never report a false Pass.
  $getSwitchState = {
    param($call, [string]$name)
    $parameter = @($call.CommandElements | Where-Object {
      $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq $name
    }) | Select-Object -First 1
    if ($parameter) {
      if ($null -eq $parameter.Argument -or $parameter.Argument.Extent.Text -ne '$false') { return 'on' }
      return 'off'
    }
    $state = 'off'
    foreach ($splat in @($call.CommandElements | Where-Object {
      $_ -is [System.Management.Automation.Language.VariableExpressionAst] -and $_.Splatted
    })) {
      $resolved = $false
      foreach ($assignment in @(& $getAssignmentsTo $splat.VariablePath.UserPath)) {
        $hashtable = $assignment.Right.Find({ $args[0] -is [System.Management.Automation.Language.HashtableAst] }, $true)
        if ($null -eq $hashtable) { continue }
        $resolved = $true
        foreach ($pair in $hashtable.KeyValuePairs) {
          $keyName = if ($pair.Item1 -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $pair.Item1.Value }
                     else { $pair.Item1.Extent.Text }
          if ($keyName -eq $name -and $pair.Item2.Extent.Text -ne '$false') { return 'on' }
        }
      }
      if (-not $resolved) { $state = 'unknown' }
    }
    $state
  }

  $invokeCalls = & $getCallsByName @('Invoke-PrtgSensor')
  $restartCalls = & $getCallsByName @('Restart-As64BitPowershell', 'Restart-InPwsh')
  $importCalls = & $getCallsByName @('Import-Module')
  $webCalls = & $getCallsByName @('Invoke-RestMethod', 'Invoke-WebRequest')

  # Script block arguments handed to Invoke-PrtgSensor (the sensor blocks).
  $sensorBlockExtents = @(foreach ($call in $invokeCalls) {
    foreach ($element in $call.CommandElements) {
      if ($element -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) { $element.Extent }
    }
  })

  $isInsideSensorBlock = {
    param($node)
    foreach ($extent in $sensorBlockExtents) {
      if ($node.Extent.StartOffset -gt $extent.StartOffset -and $node.Extent.EndOffset -le $extent.EndOffset) { return $true }
    }
    $false
  }

  # Import-Module calls that import PrtgSensorKit itself (by name or by manifest path).
  # Literal arguments (scalar or array) are resolved by the shared helper so this check
  # and the environment's import scan can never disagree on what counts as an import.
  $isKitImport = {
    param($call)
    [bool]@(Get-PrtgDoctorLiteralArgument -Call $call | Where-Object {
      $_ -match '(^|[\\/])PrtgSensorKit(\.psd1|\.psm1)?$'
    })
  }
  $kitImports = @($importCalls | Where-Object { & $isKitImport $_ })
  $otherImports = @($importCalls | Where-Object { -not (& $isKitImport $_) })

  # --- PSK0002: Import-Module PrtgSensorKit before first kit command --------------------
  $kitCommandPattern = '^(?:\w+-Prtg\w+|Restart-As64BitPowershell|Restart-InPwsh)$'
  $kitUsages = @($commandAsts | Where-Object { $_.GetCommandName() -match $kitCommandPattern })
  if ($kitUsages.Count -eq 0) {
    $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0002' -Severity 'Info' `
      -Message 'No PrtgSensorKit commands found in the script.' `
      -Recommendation 'Nothing to check; is this really a PrtgSensorKit sensor script?'))
  } elseif ($kitImports.Count -eq 0) {
    $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0002' -Severity 'Warning' `
      -Message "No 'Import-Module PrtgSensorKit' found. Module autoloading may cover this, but an explicit import is more predictable under PRTG." `
      -Line $kitUsages[0].Extent.StartLineNumber `
      -Recommendation "Add 'Import-Module PrtgSensorKit' at the top of the script."))
  } else {
    $firstImport = ($kitImports | ForEach-Object { $_.Extent.StartOffset } | Measure-Object -Minimum).Minimum
    $firstUsage = @($kitUsages | Where-Object { $_.Extent.StartOffset -lt $firstImport })
    if ($firstUsage.Count -gt 0) {
      $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0002' -Severity 'Warning' `
        -Message "'$($firstUsage[0].GetCommandName())' is used before 'Import-Module PrtgSensorKit'." `
        -Line $firstUsage[0].Extent.StartLineNumber `
        -Recommendation 'Move the import above the first PrtgSensorKit command.'))
    } else {
      $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0002' -Severity 'Pass' -Message 'PrtgSensorKit is imported before it is used.'))
    }
  }

  # --- PSK0003: Restart-* must not run inside the sensor block --------------------------
  $restartsInside = @($restartCalls | Where-Object { & $isInsideSensorBlock $_ })
  if ($restartsInside.Count -gt 0) {
    foreach ($call in $restartsInside) {
      $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0003' -Severity 'Error' `
        -Message "'$($call.GetCommandName())' is called inside the Invoke-PrtgSensor block. The relaunched child process output would be discarded by the output guard." `
        -Line $call.Extent.StartLineNumber `
        -Recommendation 'Move the Restart-* call to the top of the script, before Invoke-PrtgSensor.'))
    }
  } else {
    $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0003' -Severity 'Pass' -Message 'No Restart-* call inside the sensor block.'))
  }

  # --- PSK0004: Restart-* before Invoke-PrtgSensor and before other imports -------------
  $restartsOutside = @($restartCalls | Where-Object { -not (& $isInsideSensorBlock $_) })
  if ($restartCalls.Count -eq 0) {
    $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0004' -Severity 'Pass' -Message 'No Restart-* helpers used.'))
  } else {
    $violations = [System.Collections.Generic.List[object]]::new()
    $firstInvoke = if ($invokeCalls.Count -gt 0) { ($invokeCalls | ForEach-Object { $_.Extent.StartOffset } | Measure-Object -Minimum).Minimum } else { $null }
    foreach ($call in $restartsOutside) {
      if ($null -ne $firstInvoke -and $call.Extent.StartOffset -gt $firstInvoke) {
        $violations.Add((New-PrtgDoctorFinding -CheckId 'PSK0004' -Severity 'Error' `
          -Message "'$($call.GetCommandName())' is called after Invoke-PrtgSensor; the sensor has already emitted its response by then." `
          -Line $call.Extent.StartLineNumber `
          -Recommendation 'Call Restart-* before Invoke-PrtgSensor.'))
      }
      $importsBefore = @($otherImports | Where-Object { $_.Extent.StartOffset -lt $call.Extent.StartOffset })
      if ($importsBefore.Count -gt 0) {
        $violations.Add((New-PrtgDoctorFinding -CheckId 'PSK0004' -Severity 'Error' `
          -Message "'Import-Module' (other than PrtgSensorKit) runs before '$($call.GetCommandName())' on line $($call.Extent.StartLineNumber). The import happens in the wrong host and can fail before the relaunch." `
          -Line $importsBefore[0].Extent.StartLineNumber `
          -Recommendation 'Import dependency modules after the Restart-* call (only Import-Module PrtgSensorKit may come first).'))
      }
    }
    if ($violations.Count -gt 0) { $findings.AddRange($violations) }
    else {
      $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0004' -Severity 'Pass' -Message 'Restart-* calls are positioned correctly.'))
    }
  }

  # --- PSK0005: no manual output commands inside the sensor block -----------------------
  $manualOutputCalls = & $getCallsByName @('Write-PrtgOutput', 'Write-PrtgError', 'Clear-PrtgOutput')
  $manualInside = @($manualOutputCalls | Where-Object { & $isInsideSensorBlock $_ })
  if ($manualInside.Count -gt 0) {
    foreach ($call in $manualInside) {
      $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0005' -Severity 'Error' `
        -Message "'$($call.GetCommandName())' inside the Invoke-PrtgSensor block is not supported; the wrapper owns the single response." `
        -Line $call.Extent.StartLineNumber `
        -Recommendation 'Remove the call. Use New-PrtgChannel | Add-PrtgChannel and Set-PrtgMessage inside the block, or drop Invoke-PrtgSensor and go fully low-level.'))
    }
  } else {
    $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0005' -Severity 'Pass' -Message 'No manual output commands inside the sensor block.'))
  }

  # --- PSK0006: no Invoke-PrtgSensor call at all -----------------------------------------
  if ($invokeCalls.Count -eq 0) {
    $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0006' -Severity 'Info' `
      -Message 'No Invoke-PrtgSensor call found; assuming low-level mode (manual Write-PrtgOutput / Write-PrtgError).' `
      -Recommendation 'If this is not intentional, wrap your sensor logic in Invoke-PrtgSensor { ... }.'))
  } else {
    $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0006' -Severity 'Pass' -Message 'Invoke-PrtgSensor is used.'))
  }

  # --- PSK0007: at most one Invoke-PrtgSensor call ---------------------------------------
  if ($invokeCalls.Count -gt 1) {
    $lines = ($invokeCalls | ForEach-Object { $_.Extent.StartLineNumber }) -join ', '
    $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0007' -Severity 'Error' `
      -Message "Invoke-PrtgSensor is called $($invokeCalls.Count) times (lines $lines); a sensor must emit exactly one response." `
      -Line $invokeCalls[1].Extent.StartLineNumber `
      -Recommendation 'Merge the logic into a single Invoke-PrtgSensor block.'))
  } else {
    $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0007' -Severity 'Pass' -Message 'At most one Invoke-PrtgSensor call.'))
  }

  # --- PSK0008: statements after Invoke-PrtgSensor that could write to stdout -----------
  $trailing = @()
  if ($invokeCalls.Count -gt 0 -and $null -ne $ast.EndBlock) {
    $lastInvokeEnd = ($invokeCalls | ForEach-Object { $_.Extent.EndOffset } | Measure-Object -Maximum).Maximum
    $trailing = @($ast.EndBlock.Statements | Where-Object {
      $_.Extent.StartOffset -ge $lastInvokeEnd
    } | Where-Object {
      $statement = $_
      if ($statement -is [System.Management.Automation.Language.AssignmentStatementAst]) { return $false }
      if ($statement -is [System.Management.Automation.Language.PipelineAst]) { return $true }
      # Control flow after the sensor call: any pipeline in OUTPUT position inside it
      # (direct child of a statement block, not a condition or an assignment RHS) can
      # write to stdout at runtime, so the whole statement is flagged.
      [bool]$statement.Find({
        $args[0] -is [System.Management.Automation.Language.PipelineAst] -and
        ($args[0].Parent -is [System.Management.Automation.Language.StatementBlockAst] -or
         $args[0].Parent -is [System.Management.Automation.Language.NamedBlockAst])
      }, $true)
    })
  }
  if ($trailing.Count -gt 0) {
    foreach ($statement in $trailing) {
      $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0008' -Severity 'Warning' `
        -Message "Statement after Invoke-PrtgSensor could write to the output stream and corrupt the emitted JSON: $($statement.Extent.Text.Trim())" `
        -Line $statement.Extent.StartLineNumber `
        -Recommendation 'Remove it, assign its result to a variable, or pipe it to Out-Null. PRTG reads everything on stdout.'))
    }
  } else {
    $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0008' -Severity 'Pass' -Message 'No output-producing statements after Invoke-PrtgSensor.'))
  }

  # --- PSK0009: web cmdlets without modern TLS -------------------------------------------
  if ($webCalls.Count -eq 0) {
    $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0009' -Severity 'Pass' -Message 'No web cmdlets used; TLS setup not needed.'))
  } else {
    $forceTlsStates = @($invokeCalls | ForEach-Object { & $getSwitchState $_ 'ForceModernTls' })
    # Manual TLS setup = an assignment whose TARGET is the ServicePointManager
    # SecurityProtocol member (not any variable containing that substring) and whose
    # value mentions a modern protocol, either literally or via a variable whose own
    # literal assignment mentions one. '$SecurityProtocolBackup = ...' or an Ssl3-only
    # assignment must not count; a value the Doctor cannot resolve is 'unknown', never
    # a silent Pass or a false 'not set up'.
    $tlsAssignments = @($assignments | Where-Object {
      $_.Left.Extent.Text -match '(?i)ServicePointManager\]\s*::\s*SecurityProtocol\s*$'
    })
    $tlsVerdicts = @(foreach ($assignment in $tlsAssignments) {
      if ($assignment.Right.Extent.Text -match '(?i)Tls1[23]') { 'modern'; continue }
      $variable = $assignment.Right.Find({ $args[0] -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)
      if ($null -eq $variable) { 'none'; continue }
      if (@(& $getAssignmentsTo $variable.VariablePath.UserPath |
          Where-Object { $_.Right.Extent.Text -match '(?i)Tls1[23]' }).Count -gt 0) { 'modern' } else { 'unknown' }
    })
    if ($forceTlsStates -contains 'on' -or $tlsVerdicts -contains 'modern') {
      $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0009' -Severity 'Pass' -Message 'Web cmdlets are used and TLS is set up.'))
    } elseif ($forceTlsStates -contains 'unknown' -or $tlsVerdicts -contains 'unknown') {
      $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0009' -Severity 'Info' `
        -Message 'Web cmdlets are used and a TLS setup was found, but its value could not be verified statically (splatted or variable-based).' `
        -Line $webCalls[0].Extent.StartLineNumber `
        -Recommendation 'Prefer -ForceModernTls on the Invoke-PrtgSensor call, or assign SecurityProtocol from a literal Tls12/Tls13 value.'))
    } else {
      $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0009' -Severity 'Info' `
        -Message 'Web cmdlets are used without -ForceModernTls or a manual SecurityProtocol assignment. Windows PowerShell 5.1 defaults can lack TLS 1.2.' `
        -Line $webCalls[0].Extent.StartLineNumber `
        -Recommendation 'Add -ForceModernTls to the Invoke-PrtgSensor call.'))
    }
  }

  # --- PSK0010: -DryRun left in the script -----------------------------------------------
  $dryRunCalls = @($invokeCalls | Where-Object { (& $getSwitchState $_ 'DryRun') -eq 'on' })
  $unresolvedDryRunCalls = @($invokeCalls | Where-Object { (& $getSwitchState $_ 'DryRun') -eq 'unknown' })
  if ($dryRunCalls.Count -gt 0) {
    $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0010' -Severity 'Warning' `
      -Message 'Invoke-PrtgSensor is called with -DryRun. Deployed to PRTG, this emits an object dump instead of the PRTG JSON.' `
      -Line $dryRunCalls[0].Extent.StartLineNumber `
      -Recommendation 'Remove -DryRun before deploying the sensor.'))
  } elseif ($unresolvedDryRunCalls.Count -gt 0) {
    $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0010' -Severity 'Info' `
      -Message 'Invoke-PrtgSensor parameters are splatted from a value that could not be resolved statically; unable to verify -DryRun is not left in.' `
      -Line $unresolvedDryRunCalls[0].Extent.StartLineNumber `
      -Recommendation 'Build the splat hashtable as a literal in the script, or pass -DryRun directly, so the Doctor can check it.'))
  } else {
    $findings.Add((New-PrtgDoctorFinding -CheckId 'PSK0010' -Severity 'Pass' -Message 'No -DryRun left in the script.'))
  }

  $findings.ToArray()
}
