# Parameter names that must never become channel properties. Invariant, so it is built once at
# import instead of per New-PrtgChannel call: a sensor emits dozens of channels per interval.
# Channel/Value/Unit/Float/ShowChart/ShowTable are set on the object directly; the common
# parameters come from the runtime rather than a hand-maintained list, so -Verbose and friends
# cannot leak into the emitted JSON as hosts add new ones.
$script:PrtgChannelExcludedParameters = @('Channel', 'Value', 'Unit', 'Float', 'ShowChart', 'ShowTable') +
  [System.Management.Automation.PSCmdlet]::CommonParameters +
  [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
