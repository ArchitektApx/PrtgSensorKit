function Test-PrtgDoctorPSK0001 {
  <#
  .SYNOPSIS
    PSK0001: the script must parse
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Parsed
  )

  if ($Parsed.ParseErrors.Count -gt 0) {
    foreach ($parseError in $Parsed.ParseErrors) {
      New-PrtgDoctorFinding -CheckId 'PSK0001' -Severity 'Error' `
        -Message "Syntax error: $($parseError.Message)" `
        -Line $parseError.Extent.StartLineNumber `
        -Recommendation 'Fix the syntax error; PRTG would report this sensor as failed on every scan.'
    }
  } else {
    New-PrtgDoctorFinding -CheckId 'PSK0001' -Severity 'Pass' -Message 'Script parses without syntax errors.'
  }
}
