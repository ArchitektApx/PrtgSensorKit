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
