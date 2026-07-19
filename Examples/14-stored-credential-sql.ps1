<#
.SYNOPSIS
  Use a stored PSCredential (not just a token) to authenticate.
.DESCRIPTION
  Save-PrtgSecret can store a full credential (user + password), and Get-PrtgSecret returns it as
  a PSCredential you can pass straight to cmdlets that take -Credential (SQL, remoting, CIM, ...).
  No password in the script or PRTG config.

  One-time setup on the probe, as the sensor's account:
    Save-PrtgSecret -Name 'SqlLogin' -Credential (Get-Credential)
.NOTES
  Requires PrtgSensorKit and the SqlServer module on the probe. Windows only (DPAPI).
  Import SqlServer AFTER any Restart-* call (see example 06).
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  $cred = Get-PrtgSecret -Name 'SqlLogin'   # returns a PSCredential

  $failed = Invoke-Sqlcmd -ServerInstance 'db01' -Database 'AppDb' -Credential $cred `
    -Query "SELECT COUNT(*) AS n FROM dbo.Jobs WHERE Status = 'Failed'" |
    Select-Object -ExpandProperty n

  New-PrtgChannel -Channel 'Failed Jobs' -Value ([int]$failed) `
    -LimitMode $true -LimitMaxWarning 1 -LimitMaxError 10 |
    Add-PrtgChannel

  Set-PrtgMessage 'Failed job count from AppDb'
}
