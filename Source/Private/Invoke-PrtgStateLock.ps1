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
    [string]$LockFile,

    [Parameter(Mandatory = $true)]
    [scriptblock]$ScriptBlock,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 3600)]
    [int]$TimeoutSeconds = 10,

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$DeleteLockOnRelease
  )

  if ($Force) {
    return (& $ScriptBlock)
  }

  $options = if ($DeleteLockOnRelease) { [System.IO.FileOptions]::DeleteOnClose }
             else { [System.IO.FileOptions]::None }

  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  $handle = $null

  while ($null -eq $handle) {
    try {
      $handle = [System.IO.FileStream]::new(
        $LockFile,
        [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None,
        4096,
        $options)
    } catch [System.UnauthorizedAccessException] {
      # ACL denial is not transient; retrying until the timeout cannot succeed, so fail
      # fast with the same actionable framing as the timeout error.
      throw ("Access denied creating the state lock '$LockFile'. Check folder permissions for " +
        "the sensor account, point -Path at a writable folder, or use -Force to bypass locking.")
    } catch [System.IO.IOException] {
      if ([DateTime]::UtcNow -ge $deadline) {
        throw ("Could not acquire the state lock '$LockFile' within $TimeoutSeconds second(s). " +
          "Another sensor run may be holding it; retry, raise -TimeoutSeconds, or use -Force to bypass locking.")
      }
      Start-Sleep -Milliseconds 100
    }
  }

  try {
    & $ScriptBlock
  } finally {
    $handle.Dispose()
  }
}
