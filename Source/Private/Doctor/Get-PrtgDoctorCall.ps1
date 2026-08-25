function Get-PrtgDoctorCall {
  # Every call to one of the named commands, read from the parse context's single command scan.
  [CmdletBinding()]
  [OutputType([System.Management.Automation.Language.CommandAst[]])]
  param(
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Context,

    [Parameter(Mandatory = $true)]
    [string[]]$Name
  )

  @($Context.CommandAsts | Where-Object { $Name -contains $_.GetCommandName() })
}
