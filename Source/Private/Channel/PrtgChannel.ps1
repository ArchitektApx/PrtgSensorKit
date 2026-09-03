# Parameter names that must never become channel properties. Invariant, so it is built once at
# import. The common parameters come from the runtime, not a hand-maintained list.
$script:PrtgChannelExcludedParameters = @('Channel', 'Value', 'Unit', 'Float', 'ShowChart', 'ShowTable') +
  [System.Management.Automation.PSCmdlet]::CommonParameters +
  [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
