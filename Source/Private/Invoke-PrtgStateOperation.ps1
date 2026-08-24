function Invoke-PrtgStateOperation {
  <#
  .SYNOPSIS
    Resolves a state store key and runs a script block while holding its lock.
  .DESCRIPTION
    The opening sequence Save/Get/Clear-PrtgSensorState and Use-PrtgCachedResult all need
    before they can do anything: resolve the key to its entry file and '.lock' sidecar, then
    take the lock. One owner, so the next concurrency fix is written once instead of four
    times. The block's output is returned unchanged.

    Two steps, resolve and lock, and nothing else. Reading entries, deciding freshness, and
    writing back look shared and are not: the four pass four different narration sets to the
    entry loader, the three freshness comparisons answer three different questions, and the
    three write-backs have three different shapes.

    This sits above Invoke-PrtgStateLock rather than absorbing it. Resolving a store folder
    creates it, so the case where the lock is reached with a folder that does not exist is
    unreachable from here; the test for it calls the lock directly, and it guards an
    exception-dispatch difference that only appears under Windows PowerShell 5.1.
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

  # Every parameter and local here is prefixed 'PrtgOp' on purpose. This is the second frame in
  # the DYNAMIC chain a caller's block resolves through, above Invoke-PrtgStateLock's own
  # 'PrtgLock' frame, and the names it naturally wants - Key, Path, File, Force, TimeoutSeconds -
  # are exactly the ones the four blocks already read from their own cmdlets. An unprefixed name
  # here shadows them silently. A closure is not the way out: it defeats the shadowing but also
  # severs the block from the module's private functions, and all four blocks call at least one.
  #
  # The lock wait is mandatory and has no default. All four cmdlets publish their own default
  # and always pass a value, so a default here would be unreachable and a second place for the
  # published values to drift from.

  $PrtgOpState = Get-PrtgStateFile -Key $PrtgOpKey -Path $PrtgOpPath

  # No verbose line of its own: every existing one lives in a caller's block and names what
  # that cmdlet did, and the lock's errors already name the file they could not take.
  Invoke-PrtgStateLock -PrtgLockFile $PrtgOpState.LockFile -PrtgLockTimeout $PrtgOpTimeout `
    -PrtgLockForce:$PrtgOpForce -PrtgLockDeleteOnRelease:$PrtgOpDeleteOnRelease -PrtgLockBlock {
    # Passed as an explicit argument the block declares as param($PrtgOpState), rather than left
    # to dynamic lookup: passing what a block needs removes the shadowing hazard for that value
    # instead of managing it.
    & $PrtgOpBlock $PrtgOpState
  }
}
