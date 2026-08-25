function Invoke-PrtgStateLock {
  <#
  .SYNOPSIS
    Runs a script block while holding the exclusive lock for a state file.
  .DESCRIPTION
    Serializes access to a sensor state file across overlapping sensor runs. The lock is an
    open FileShare.None handle on the '.lock' sidecar file - handle-based on purpose: the
    OS releases the handle when the owning process exits or crashes, so a killed sensor run
    can never leave a permanently stale lock. Acquisition polls every 100 ms until it
    succeeds or the timeout expires (TimeoutSeconds 0 = exactly one try). The handle is
    released in a finally block, so a throwing script block still releases the lock.

    The sidecar file itself is never deleted here (deleting it while another process polls
    it is a race); a leftover zero-byte '.lock' file is harmless. -DeleteLockOnRelease opts
    into FileOptions.DeleteOnClose for Clear-PrtgSensorState -ClearLock, where the OS
    removes the file atomically when the held handle closes.

    -Force skips locking entirely and runs the block best-effort.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$PrtgLockFile,

    [Parameter(Mandatory = $true)]
    [scriptblock]$PrtgLockBlock,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 3600)]
    [int]$PrtgLockTimeout = 10,

    [Parameter(Mandatory = $false)]
    [switch]$PrtgLockForce,

    [Parameter(Mandatory = $false)]
    [switch]$PrtgLockDeleteOnRelease
  )

  # Every parameter and local here is prefixed 'PrtgLock' on purpose. The script block runs via
  # '& $PrtgLockBlock' and resolves unqualified names up the DYNAMIC chain - this frame first -
  # so any ordinary name here would silently shadow the caller's variable of the same name.
  # A new parameter without the prefix reopens that hole.

  if ($PrtgLockForce) {
    return (& $PrtgLockBlock)
  }

  $PrtgLockOptions = if ($PrtgLockDeleteOnRelease) { [System.IO.FileOptions]::DeleteOnClose }
                     else { [System.IO.FileOptions]::None }

  $PrtgLockDeadline = [DateTime]::UtcNow.AddSeconds($PrtgLockTimeout)
  $PrtgLockHandle = $null

  while ($null -eq $PrtgLockHandle) {
    try {
      $PrtgLockHandle = [System.IO.FileStream]::new(
        $PrtgLockFile,
        [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None,
        4096,
        $PrtgLockOptions)
    } catch [System.UnauthorizedAccessException] {
      # ACL denial is not transient; retrying until the timeout cannot succeed, so fail
      # fast with the same actionable framing as the timeout error.
      throw ("Access denied creating the state lock '$PrtgLockFile'. Check folder permissions for " +
        "the sensor account, point -Path at a writable folder, or use -Force to bypass locking.")
    } catch [System.IO.IOException] {
      # DirectoryNotFoundException derives from IOException and is handled INSIDE this arm on
      # purpose. Giving it its own 'catch [System.IO.DirectoryNotFoundException]' clause ahead
      # of the other two - the obvious way to write this - makes Windows PowerShell 5.1
      # dispatch an ordinary sharing violation to the UnauthorizedAccessException arm instead,
      # so every wait-for-a-concurrent-holder case dies with a bogus "Access denied". pwsh 7 is
      # unaffected, so a macOS/pwsh-only test run will not catch a reintroduction.
      # GetBaseException() is defensive - every observed throw here arrives unwrapped - but it
      # costs nothing and covers a MethodInvocationException wrapper if one ever shows up.
      if ($_.Exception.GetBaseException() -is [System.IO.DirectoryNotFoundException]) {
        # Not transient: retrying until the timeout cannot make a directory appear. Fail fast
        # with an accurate message instead of blaming a concurrent run that does not exist.
        throw ("The folder for the state lock '$PrtgLockFile' does not exist. Point -Path at an " +
          "existing folder, or let the module use its default store.")
      }
      if ([DateTime]::UtcNow -ge $PrtgLockDeadline) {
        throw ("Could not acquire the state lock '$PrtgLockFile' within $PrtgLockTimeout second(s). " +
          "Another sensor run may be holding it; retry, raise -TimeoutSeconds, or use -Force to bypass locking.")
      }
      Start-Sleep -Milliseconds 100
    }
  }

  try {
    & $PrtgLockBlock
  } finally {
    $PrtgLockHandle.Dispose()
  }
}
