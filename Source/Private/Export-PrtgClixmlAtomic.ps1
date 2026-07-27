function Export-PrtgClixmlAtomic {
  <#
  .SYNOPSIS
    Export-Clixml that cannot leave a half-written file behind.
  .DESCRIPTION
    Shared by the state store and the shared cache. Export-Clixml truncates its target before it
    writes, so writing straight to the live file destroys the existing content the moment a write
    fails part-way (a full disk, a sensor killed on a PRTG timeout). The new content goes to a
    temp file in the same folder and is swapped in as a single step, so a failed write leaves the
    previous content untouched and nothing partial on disk.
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Non-interactive store write on the sensor path; a -Confirm prompt would stall a PRTG probe.')]
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [AllowNull()]
    [object]$InputObject,

    [Parameter(Mandatory = $true)]
    [string]$LiteralPath,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 100)]
    [int]$Depth = 5
  )

  $folder = Split-Path -Parent $LiteralPath
  $name = Split-Path -Leaf $LiteralPath
  $temp = Join-Path $folder "$name.$([guid]::NewGuid().ToString('N')).tmp"

  Remove-PrtgStaleTempFile -Folder $folder -Filter "$name.*.tmp"

  try {
    $InputObject | Export-Clixml -LiteralPath $temp -Depth $Depth -Force
    Move-PrtgFileAtomic -Path $temp -Destination $LiteralPath
  } catch {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    throw
  }
}
