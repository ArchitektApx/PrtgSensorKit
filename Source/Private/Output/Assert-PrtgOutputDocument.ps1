function Assert-PrtgOutputDocument {
  # Called at the point a cmdlet would otherwise fail on a null document, never on entry.
  # Get-PrtgMessage and Write-PrtgOutput do not fail on one today and must not start to.
  #
  # Thrown through the calling cmdlet so the error record carries the sensor script's line, with
  # the same exception type as the null dereference it replaces. -Action is the caller's verb
  # phrase ending in its preposition ('add a channel to').
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [System.Management.Automation.PSCmdlet]$Caller,

    [Parameter(Mandatory = $true)]
    [string]$Action,

    # Mandatory with AllowNull: an omitted argument would otherwise be indistinguishable from a
    # genuinely null document, and report a null output document for a missing parameter.
    [Parameter(Mandatory = $true)]
    [AllowNull()]
    $Document
  )

  if ($null -ne $Document) { return }

  $name = $Caller.MyInvocation.MyCommand.Name
  $message = "${name}: there is no sensor output to $Action. The output document is null, which " +
    "happens when Set-PrtgOutput is passed `$null. Call Clear-PrtgOutput to start a fresh one, " +
    "or pass Set-PrtgOutput an object with a 'prtg' property holding 'result' and 'text'."
  $record = [System.Management.Automation.ErrorRecord]::new(
    [System.Management.Automation.RuntimeException]::new($message),
    'PrtgOutputDocumentNull',
    [System.Management.Automation.ErrorCategory]::InvalidOperation,
    $Document)
  $Caller.ThrowTerminatingError($record)
}
