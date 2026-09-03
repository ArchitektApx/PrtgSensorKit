function Invoke-PrtgStateOperation {
  <#
  .SYNOPSIS
    Resolves a state store key and runs a script block while holding its lock.
  .DESCRIPTION
    Resolves the key to its entry file and '.lock' sidecar, takes the lock, and runs the block
    with that resolved state object as its argument. The block's output is returned unchanged.
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'PrtgOpBlock is invoked inside the script block passed to Invoke-PrtgStateLock; the analyzer cannot see into it.')]
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$PrtgOpKey,

    [Parameter(Mandatory = $false)]
    [string]$PrtgOpPath,

    [Parameter(Mandatory = $true)]
    [scriptblock]$PrtgOpBlock,

    [Parameter(Mandatory = $true)]
    [int]$PrtgOpTimeout,

    [Parameter(Mandatory = $false)]
    [switch]$PrtgOpForce,

    [Parameter(Mandatory = $false)]
    [switch]$PrtgOpDeleteOnRelease
  )

  # Names are prefixed 'PrtgOp' so they cannot shadow the caller's block (ADR 0001).

  $PrtgOpState = Get-PrtgStateFile -Key $PrtgOpKey -Path $PrtgOpPath

  Invoke-PrtgStateLock -PrtgLockFile $PrtgOpState.LockFile -PrtgLockTimeout $PrtgOpTimeout `
    -PrtgLockForce:$PrtgOpForce -PrtgLockDeleteOnRelease:$PrtgOpDeleteOnRelease -PrtgLockBlock {
    & $PrtgOpBlock $PrtgOpState
  }
}
