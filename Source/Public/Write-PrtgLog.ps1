function Write-PrtgLog {
  <#
  .SYNOPSIS
    Appends a timestamped line to this sensor run's log file.

  .DESCRIPTION
    The safe way to debug a deployed sensor: PRTG reads the sensor result from stdout, so
    debugging output must go to a file - and Write-PrtgLog is that file writer, batteries
    included. Each sensor invocation (process) gets its own log file, so a failing run is
    one self-contained file and concurrent sensor runs never write into each other.

    Where the file goes:

    - inside 'Invoke-PrtgSensor -EnableLogging', the directory configured there
      (its -LogPath, or the default below);
    - anywhere else, the default '$env:ProgramData\PrtgSensorKit\Logs\<scriptname>\'
      on Windows (a temp folder on other platforms).

    An explicit Write-PrtgLog call always writes - there is no silent no-op - so it also
    works in manual low-level sensor scripts that do not use Invoke-PrtgSensor at all.

    The first call in a process creates '<scriptname>_<yyyyMMdd-HHmmss>_<PID>.log' and
    prunes old run files in the same folder (newest 30 kept by default; configure with
    Invoke-PrtgSensor -MaxLogs). Later calls append to the same file.

    Logging can never affect the sensor result: every failure (full disk, locked file,
    bad path) is swallowed and only surfaced via Write-Verbose. Write-PrtgLog never
    throws and writes nothing to any PowerShell output stream.

  .PARAMETER Message
    The text to log. One '<timestamp> [<LEVEL>] <message>' line per call; embedded
    newlines are preserved, so multi-line content like exception dumps is fine. The
    timestamp is local time with UTC offset (ISO 8601 round-trip format). Do not log
    secret values; nothing is redacted.

  .PARAMETER Level
    Tag for the line: Info (default), Warning, Error, or Debug. A label only - no level
    is ever filtered out.

  .EXAMPLE
    Invoke-PrtgSensor -EnableLogging {
      Write-PrtgLog "querying $ApiUrl"
      $data = Invoke-RestMethod -Uri $ApiUrl
      New-PrtgChannel -Channel 'Items' -Value $data.count | Add-PrtgChannel
    }

    Logs to the default log folder alongside the automatic sensor lifecycle entries
    (start, retries, success summary, full error details).

  .EXAMPLE
    Write-PrtgLog -Level Warning "cache miss, falling back to full query"

    Standalone use in a manual low-level sensor script; writes to the default log folder.

  .NOTES
    Log files are plain text, UTF-8 (with BOM under Windows PowerShell 5.1). To find the
    latest run:  Get-ChildItem $env:ProgramData\PrtgSensorKit\Logs\<scriptname> |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

  .LINK
    Invoke-PrtgSensor
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true, Position = 0)]
    [AllowEmptyString()]
    [string]$Message,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Info', 'Warning', 'Error', 'Debug')]
    [string]$Level = 'Info'
  )

  try {
    $line = '{0} [{1}] {2}{3}' -f [DateTime]::Now.ToString('o'), $Level.ToUpperInvariant(), $Message, [Environment]::NewLine
    if ([string]::IsNullOrEmpty($script:PrtgLogFile) -or -not (Test-Path -LiteralPath $script:PrtgLogFile)) {
      $script:PrtgLogFile = New-PrtgLogFile -FirstLine $line
    } else {
      [System.IO.File]::AppendAllText($script:PrtgLogFile, $line, $script:PrtgLogEncoding)
    }
  } catch {
    # Never-throw policy: a log line is never worth a red sensor.
    Write-Verbose "Write-PrtgLog: log entry dropped. ($($_.Exception.Message))"
  }
}
