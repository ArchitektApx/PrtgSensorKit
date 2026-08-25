function Remove-PrtgStaleTempFile {
  <#
  .SYNOPSIS
    Best-effort cleanup of temp files left behind by an interrupted atomic write.
  .DESCRIPTION
    A process killed between creating the temp file and renaming it over the target (a PRTG
    sensor timeout, a reboot) strands a '<name>.<guid>.tmp' file that nothing else prunes.

    Only files older than -OlderThan are removed: a second instance of the same sensor may be
    part-way through its own save right now, and deleting its temp file would either break that
    save or - worse for the secret store - make Export-Clixml recreate the file without the ACL
    the save had already applied to it. Never throws; cleanup is not worth failing a sensor over.
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Non-interactive store housekeeping on the sensor path; a -Confirm prompt would stall a PRTG probe.')]
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Folder,

    [Parameter(Mandatory = $true)]
    [string]$Filter,

    [Parameter(Mandatory = $false)]
    [timespan]$OlderThan = ([timespan]::FromHours(1))
  )

  $cutoff = [DateTime]::UtcNow - $OlderThan
  # -Filter does the fast pass, -like re-checks it: on Windows the provider filter also matches
  # 8.3 short names, so '*.tmp' can hit a '.tmpsomething' file. The store folder may hold
  # unrelated content (Save-PrtgSecret -Path documents that as safe), so only exact matches go.
  Get-ChildItem -LiteralPath $Folder -Filter $Filter -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like $Filter -and $_.LastWriteTimeUtc -lt $cutoff } |
    ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
}
