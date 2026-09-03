function Invoke-PrtgStateLock {
  <#
  .SYNOPSIS
    Runs a script block while holding the exclusive lock for a state file.
  .DESCRIPTION
    Serializes access to a sensor state file across overlapping sensor runs. The lock is an
    exclusive handle on the '.lock' sidecar, released by the OS when the owning process exits,
    so a killed run leaves no stale lock. Acquisition polls every 100 ms until the timeout
    expires (0 = one try); -PrtgLockForce skips locking, and -PrtgLockDeleteOnRelease lets the
    OS remove the sidecar when the handle closes.
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

  # Names are prefixed 'PrtgLock' so they cannot shadow the caller's block (ADR 0001).

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
      # DirectoryNotFoundException is handled inside this arm on purpose: given its own catch
      # clause, Windows PowerShell 5.1 sends a sharing violation to the access-denied arm.
      if ($_.Exception.GetBaseException() -is [System.IO.DirectoryNotFoundException]) {
        # Not transient: retrying until the timeout cannot make a directory appear.
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
