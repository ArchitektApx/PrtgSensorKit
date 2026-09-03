function Remove-PrtgStaleTempFile {
  <#
  .SYNOPSIS
    Best-effort cleanup of temp files left behind by an interrupted atomic write.
  .DESCRIPTION
    A process killed between creating the temp file and renaming it over the target strands a
    '<name>.<guid>.tmp' file that nothing else prunes. Only files older than -OlderThan are
    removed, so a concurrent save of the same sensor keeps its own temp file. Never throws.
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
  # -Filter does the fast pass and -like re-checks it: on Windows the provider filter also
  # matches 8.3 short names, so '*.tmp' can hit a '.tmpsomething' file.
  Get-ChildItem -LiteralPath $Folder -Filter $Filter -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like $Filter -and $_.LastWriteTimeUtc -lt $cutoff } |
    ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
}
