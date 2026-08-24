function Export-PrtgClixmlAtomic {
  <#
  .SYNOPSIS
    Export-Clixml that cannot leave a half-written file behind.
  .DESCRIPTION
    Shared by the state store, the shared cache, and the secret store. Export-Clixml truncates its
    target before it writes, so writing straight to the live file destroys the existing content the
    moment a write fails part-way (a full disk, a sensor killed on a PRTG timeout). The new content
    goes to a temp file in the same folder and is swapped in as a single step, so a failed write
    leaves the previous content untouched and nothing partial on disk.

    -PrtgWriteBeforeWrite runs on the temp file before the payload goes into it, and
    -PrtgWriteAfterSwap on the destination once the swap has happened. The secret store hardens its
    ACL in both places: before, so the blob never exists under inherited permissions, and after,
    because the swap keeps the ACL of the file it replaced. Each hook receives the path it acts on
    as an ARGUMENT rather than resolving it up the dynamic scope chain.

    The temp file is always pre-created, so a before-write hook only ever hardens a file that
    exists and both callers stay on one path. The extra syscall costs nothing on a plain state
    write, whose export overwrites the file regardless.

    Every parameter and local here is prefixed 'PrtgWrite' on purpose. The hooks run via '&' and
    resolve unqualified names up the DYNAMIC chain - this frame first - so any unprefixed name
    here would silently shadow the calling cmdlet's variable of the same name. A new parameter
    without the prefix reopens that hole.
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Non-interactive store write on the sensor path; a -Confirm prompt would stall a PRTG probe.')]
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [AllowNull()]
    [object]$PrtgWriteInputObject,

    [Parameter(Mandatory = $true)]
    [string]$PrtgWriteLiteralPath,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 100)]
    [int]$PrtgWriteDepth = 5,

    [Parameter(Mandatory = $false)]
    [scriptblock]$PrtgWriteBeforeWrite,

    [Parameter(Mandatory = $false)]
    [scriptblock]$PrtgWriteAfterSwap
  )

  $PrtgWriteFolder = Split-Path -Parent $PrtgWriteLiteralPath
  # Derived from the FULL leaf, extension included, so the temp of 'Key.clixml' is
  # 'Key.clixml.<guid>.tmp' and the sweep filter below matches exactly this file's own leftovers.
  $PrtgWriteLeaf = Split-Path -Leaf $PrtgWriteLiteralPath
  $PrtgWriteTemp = Join-Path $PrtgWriteFolder "$PrtgWriteLeaf.$([guid]::NewGuid().ToString('N')).tmp"

  Remove-PrtgStaleTempFile -Folder $PrtgWriteFolder -Filter "$PrtgWriteLeaf.*.tmp"

  try {
    # New-Item has no -LiteralPath, and its -Path glob-interprets '[' and ']', which a store
    # folder is allowed to contain. Escaped rather than swapped for a .NET create: [System.IO]
    # resolves a relative path against the PROCESS working directory, not PowerShell's location.
    [void] (New-Item -ItemType File -Path ([System.Management.Automation.WildcardPattern]::Escape($PrtgWriteTemp)) -Force)
    if ($PrtgWriteBeforeWrite) { & $PrtgWriteBeforeWrite $PrtgWriteTemp }

    $PrtgWriteInputObject | Export-Clixml -LiteralPath $PrtgWriteTemp -Depth $PrtgWriteDepth -Force
    Move-PrtgFileAtomic -Path $PrtgWriteTemp -Destination $PrtgWriteLiteralPath

    if ($PrtgWriteAfterSwap) { & $PrtgWriteAfterSwap $PrtgWriteLiteralPath }
  } catch {
    Remove-Item -LiteralPath $PrtgWriteTemp -Force -ErrorAction SilentlyContinue
    throw
  }
}
