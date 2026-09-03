function Get-PrtgDoctorCall {
  <#
  .SYNOPSIS
    Every call in the analyzed script to one of the named commands.
  #>
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
