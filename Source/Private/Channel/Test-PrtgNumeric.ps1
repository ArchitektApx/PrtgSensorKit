function Test-PrtgNumeric {
  # True for any numeric value PRTG can carry in a channel or a limit. Explicit list rather than
  # '[ValueType] and not bool', which would also admit enums, TimeSpan, Guid, and DateTime.
  [CmdletBinding()]
  [OutputType([bool])]
  param(
    [Parameter(Mandatory = $false)]
    [AllowNull()]
    $Value
  )

  return (
    $Value -is [byte]   -or $Value -is [sbyte]  -or
    $Value -is [int16]  -or $Value -is [uint16] -or
    $Value -is [int32]  -or $Value -is [uint32] -or
    $Value -is [int64]  -or $Value -is [uint64] -or
    $Value -is [single] -or $Value -is [double] -or $Value -is [decimal]
  )
}
