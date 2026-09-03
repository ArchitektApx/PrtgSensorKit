function Test-PrtgDoctorScript {
  <#
  .SYNOPSIS
    Runs the AST-based Doctor checks (PSK0001-PSK0013) against a parsed sensor script.
  .DESCRIPTION
    Pure static analysis: works everywhere, never executes the target script. Each check
    emits exactly one finding (Pass or its issue severity); position-sensitive checks may
    emit one finding per offending call site instead. Every check reads the whole-script
    walks from the parse context it is handed.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Parsed
  )

  $findings = [System.Collections.Generic.List[object]]::new()

  $findings.AddRange(@(Test-PrtgDoctorPSK0001 -Parsed $Parsed))
  $findings.AddRange(@(Test-PrtgDoctorPSK0011 -Parsed $Parsed))
  $findings.AddRange(@(Test-PrtgDoctorPSK0002 -Parsed $Parsed))
  $findings.AddRange(@(Test-PrtgDoctorPSK0003 -Parsed $Parsed))
  $findings.AddRange(@(Test-PrtgDoctorPSK0004 -Parsed $Parsed))
  $findings.AddRange(@(Test-PrtgDoctorPSK0005 -Parsed $Parsed))
  $findings.AddRange(@(Test-PrtgDoctorPSK0006 -Parsed $Parsed))
  $findings.AddRange(@(Test-PrtgDoctorPSK0007 -Parsed $Parsed))
  $findings.AddRange(@(Test-PrtgDoctorPSK0008 -Parsed $Parsed))
  $findings.AddRange(@(Test-PrtgDoctorPSK0009 -Parsed $Parsed))
  $findings.AddRange(@(Test-PrtgDoctorPSK0010 -Parsed $Parsed))
  $findings.AddRange(@(Test-PrtgDoctorPSK0012 -Parsed $Parsed))
  $findings.AddRange(@(Test-PrtgDoctorPSK0013 -Parsed $Parsed))

  $findings.ToArray()
}
