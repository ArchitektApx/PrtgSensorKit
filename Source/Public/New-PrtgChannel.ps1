function New-PrtgChannel {
  <#
  .SYNOPSIS
    Creates a new PRTG Channel object for use in custom sensor JSON output.

  .DESCRIPTION
    New-PrtgChannel creates a PSCustomObject that represents a PRTG channel definition.
    The output can be piped to Write-PrtgOutput or Add-PrtgChannel to produce
    valid PRTG custom sensor JSON. Channel objects define how values are displayed,
    graphed, and evaluated (limits) in PRTG.

    Reference: https://www.paessler.com/manuals/prtg/custom_sensors#advanced_elements

    Dynamic parameters appear based on the -Unit value. Because they are dynamic, Get-Help
    only shows their descriptions once -Unit is bound; they are summarized here:
    - CustomUnit: mandatory when Unit is 'Custom'. Text shown after the value as its unit.
    - SpeedSize: when Unit is BytesBandwidth, SpeedDisk, or SpeedNet. Size prefix - one of
      One, Kilo, Mega, Giga, Tera, Byte, KiloByte, MegaByte, GigaByte, TeraByte, Bit, KiloBit,
      MegaBit, GigaBit, TeraBit.
    - SpeedTime: when Unit is BytesBandwidth, SpeedDisk, or SpeedNet. One of Second, Minute,
      Hour, Day.
    - VolumeSize: when Unit is BytesDisk or BytesFile. Same value set as SpeedSize.

  .PARAMETER Channel
    The display name of the channel in PRTG.

  .PARAMETER Value
    The numeric value for the channel. Accepts any built-in numeric type: byte, sbyte, int16,
    uint16, int32 (int), uint32, int64, uint64, single (float), double, and decimal - so CIM and
    WMI UInt64 values can be passed without a cast. Integers keep their exact value in the JSON;
    -Float converts to double and is lossy above 2^53.

  .PARAMETER Unit
    The unit type for the channel. Determines formatting and available dynamic parameters.
    Default is 'Count'.

  .PARAMETER Mode
    Value mode: 'Absolute' (default in PRTG) or 'Difference' for delta display.

  .PARAMETER Float
    When specified, the value is sent as floating-point (recommended for decimal values).

  .PARAMETER DecimalMode
    Controls decimal places: 'Auto' or 'All'.

  .PARAMETER Warning
    When specified, marks the channel in warning state for PRTG.

  .PARAMETER ShowChart
    Whether to show the channel in the sensor graph. Default is $true.

  .PARAMETER ShowTable
    Whether to show the channel in the sensor table. Default is $true.

  .PARAMETER LimitMaxError
    Upper error limit. Value above this triggers error state.

  .PARAMETER LimitMaxWarning
    Upper warning limit. Value above this triggers warning state.

  .PARAMETER LimitMinWarning
    Lower warning limit. Value below this triggers warning state.

  .PARAMETER LimitMinError
    Lower error limit. Value below this triggers error state.

  .PARAMETER LimitErrorMsg
    Custom message shown when an error limit is exceeded.

  .PARAMETER LimitWarningMsg
    Custom message shown when a warning limit is exceeded.

  .PARAMETER LimitMode
    When $true, PRTG uses the defined limits for state evaluation. Default is $false.

  .PARAMETER ValueLookup
    Name of a PRTG value lookup to translate numeric values to text (e.g. "prtg.standardlookups.boolean").

  .PARAMETER NotifyChanged
    When specified, PRTG triggers change notification when the value changes.

  .PARAMETER CustomUnit
    Dynamic parameter, available and mandatory when -Unit is 'Custom'. The text displayed
    after the value as its unit.

  .PARAMETER SpeedSize
    Dynamic parameter, available when -Unit is 'BytesBandwidth', 'SpeedDisk', or 'SpeedNet'.
    The size prefix for the value (One, Kilo, Mega, Giga, Tera, Byte, KiloByte, MegaByte,
    GigaByte, TeraByte, Bit, KiloBit, MegaBit, GigaBit, TeraBit).

  .PARAMETER SpeedTime
    Dynamic parameter, available when -Unit is 'BytesBandwidth', 'SpeedDisk', or 'SpeedNet'.
    The time unit for the speed (Second, Minute, Hour, Day).

  .PARAMETER VolumeSize
    Dynamic parameter, available when -Unit is 'BytesDisk' or 'BytesFile'. The size prefix for
    the value (One, Kilo, Mega, Giga, Tera, Byte, KiloByte, MegaByte, GigaByte, TeraByte, Bit,
    KiloBit, MegaBit, GigaBit, TeraBit).

  .EXAMPLE
    New-PrtgChannel -Channel 'Total Items' -Value 42

    Creates a simple channel named "Total Items" with value 42 and unit Count.

  .EXAMPLE
    New-PrtgChannel -Channel 'CPU %' -Value 78.5 -Unit Percent -Float

    Creates a percentage channel with a floating-point value (e.g. CPU usage).

  .EXAMPLE
    New-PrtgChannel -Channel 'Temperature' -Value 65.2 -Unit Temperature -Float

    Creates a temperature channel (e.g. for hardware sensors).

  .EXAMPLE
    New-PrtgChannel -Channel 'Response Time' -Value 120 -Unit TimeResponse -LimitMaxWarning 100 -LimitMaxError 500 -LimitMode $true

    Creates a response time channel with warning above 100 ms and error above 500 ms.

  .EXAMPLE
    New-PrtgChannel -Channel 'Disk Free %' -Value 25.0 -Unit Percent -Float -LimitMinWarning 20 -LimitMinError 10 -LimitMode $true

    Creates a "Disk Free %" channel with lower limits (warning below 20%, error below 10%).

  .EXAMPLE
    New-PrtgChannel -Channel 'Success' -Value 950 -Unit Count | Add-PrtgChannel
    New-PrtgChannel -Channel 'Failed' -Value 50 -Unit Count -Warning | Add-PrtgChannel

    Creates two channels and writes them as PRTG JSON output (e.g. for a custom sensor script).

  .OUTPUTS
    PSCustomObject. A channel object with properties Channel, Value, Unit, ShowChart, ShowTable, and any specified optional parameters.

  .NOTES
    The returned object is designed to be consumed by Write-PrtgOutput or Add-PrtgChannel.
    Use -Float when passing decimal values to ensure correct PRTG JSON formatting.

  .LINK
    https://www.paessler.com/manuals/prtg/custom_sensors#advanced_elements
  .LINK
    Write-PrtgOutput
  .LINK
    Add-PrtgChannel
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Pure factory that returns a channel object; it changes no state, so -WhatIf/-Confirm do not apply.')]
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Channel,

    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-PrtgNumeric $_ })]
    $Value,

    [Parameter(Mandatory = $false)]
    [ValidateSet(
      'BytesBandwidth',
      'BytesDisk',
      'Temperature',
      'Percent',
      'TimeResponse',
      'TimeSeconds',
      'Count',
      'Custom',
      'CPU',
      'BytesFile',
      'SpeedDisk',
      'SpeedNet',
      'TimeHours'
    )]
    [string]
    $Unit = 'Count',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Absolute', 'Difference')]
    [string]
    $Mode,

    [Parameter(Mandatory = $false)]
    [switch]
    $Float,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Auto', 'All')]
    [string]
    $DecimalMode,

    [Parameter(Mandatory = $false)]
    [switch]
    $Warning,

    [Parameter(Mandatory = $false)]
    [bool]
    $ShowChart = $true,

    [Parameter(Mandatory = $false)]
    [bool]
    $ShowTable = $true,
      
    [Parameter(Mandatory = $false)]
    [ValidateScript({ (Test-PrtgNumeric $_) -or $_ -is [string] })]
    $LimitMaxError,
      
    [Parameter(Mandatory = $false)]
    [ValidateScript({ (Test-PrtgNumeric $_) -or $_ -is [string] })]
    $LimitMaxWarning,
      
    [Parameter(Mandatory = $false)]
    [ValidateScript({ (Test-PrtgNumeric $_) -or $_ -is [string] })]
    $LimitMinWarning,
      
    [Parameter(Mandatory = $false)]
    [ValidateScript({ (Test-PrtgNumeric $_) -or $_ -is [string] })]
    $LimitMinError,
      
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]
    $LimitErrorMsg,
      
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]
    $LimitWarningMsg,
      
    [Parameter(Mandatory = $false)]
    [bool]
    $LimitMode = $false,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]
    $ValueLookup,

    [Parameter(Mandatory = $false)]
    [switch] 
    $NotifyChanged
  )

  dynamicparam {
    $ParamDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::New()
    $ValidateSizeAttribute = [System.Management.Automation.ValidateSetAttribute]::New(
      'One',
      'Kilo',
      'Mega',
      'Giga',
      'Tera',
      'Byte',
      'KiloByte',
      'MegaByte',
      'GigaByte',
      'TeraByte',
      'Bit',
      'KiloBit',
      'MegaBit',
      'GigaBit',
      'TeraBit'
    )

    # The unit list and the companion parameter names stay literal: the generator interface
    # that would let them be derived is absent on 32-bit Windows PowerShell 5.1.
    switch ( $Unit ) {
      { $_ -eq 'Custom' } {
        New-PrtgDynamicParameter -Name 'CustomUnit' -Dictionary $ParamDictionary -Mandatory `
          -Validator ([System.Management.Automation.ValidateNotNullOrEmptyAttribute]::New())
      }
      { $_ -in @('BytesBandwidth', 'SpeedDisk', 'SpeedNet') } {
        New-PrtgDynamicParameter -Name 'SpeedSize' -Dictionary $ParamDictionary -Validator $ValidateSizeAttribute
        New-PrtgDynamicParameter -Name 'SpeedTime' -Dictionary $ParamDictionary `
          -Validator ([System.Management.Automation.ValidateSetAttribute]::New(
            'Second',
            'Minute',
            'Hour',
            'Day'
          ))
      }
      { $_ -in @('BytesDisk', 'BytesFile') } {
        New-PrtgDynamicParameter -Name 'VolumeSize' -Dictionary $ParamDictionary -Validator $ValidateSizeAttribute
      }
    }

    return $ParamDictionary
  }
      
  process {
    $PrtgChannel = [PSCustomObject]@{
      PSTypeName = 'PrtgSensorKit.Channel'
      Channel    = $Channel
      Value      = $Value
      Unit       = $Unit
      ShowChart  = [int][bool]$ShowChart
      ShowTable  = [int][bool]$ShowTable
    }

    if (
      $Float -or
      $Value -is [float] -or 
      $Value -is [double] -or 
      $Value -is [decimal]
    ) {
      $PrtgChannel.Value = [double]$Value
      $PrtgChannel | Add-Member -Name 'Float' -Type NoteProperty -Value 1
    }

    $PSBoundParameters.GetEnumerator() |
      Where-Object { $_.Key -notin $script:PrtgChannelExcludedParameters } |
      ForEach-Object { 
        $TypeConvertedValue = switch ($_.Value) {
          { $_ -is [switch] } { [int][bool]$_ }
          { $_ -is [bool] } { [int]$_ }
          { $_ -is [string] } { $_ }
          default { "$_" }
        }

        # Limit messages are shown as sensor messages, so strip '#' and truncate to 2000 chars
        if ($_.Key -in 'LimitErrorMsg', 'LimitWarningMsg') {
          $TypeConvertedValue = Format-PrtgMessage $TypeConvertedValue
        }

        $PrtgChannel | Add-Member -Name $_.Key -Type NoteProperty -Value $TypeConvertedValue
      }

    return $PrtgChannel
  }
}
