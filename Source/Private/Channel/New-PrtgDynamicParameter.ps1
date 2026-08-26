function New-PrtgDynamicParameter {
  <#
    .SYNOPSIS
      Builds one companion parameter for New-PrtgChannel and adds it to the dictionary.
    .DESCRIPTION
      The ParameterAttribute is constructed here, once per call. Reusing one instance across
      two companion parameters makes them share mandatory state.

      The validator arrives already constructed and typed as a plain attribute, so the caller
      decides whether it is shared across families or fresh per call. ValidateSet instances are
      immutable in use, so the size set is shared; the caller's other validators are not.
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Builds a parameter definition during binding; -WhatIf/-Confirm cannot apply inside dynamicparam.')]
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Name,

    [Parameter(Mandatory = $true)]
    [System.Attribute]
    $Validator,

    [Parameter(Mandatory = $true)]
    [System.Management.Automation.RuntimeDefinedParameterDictionary]
    $Dictionary,

    [Parameter(Mandatory = $false)]
    [switch]
    $Mandatory
  )

  $parameterAttribute = [System.Management.Automation.ParameterAttribute]::New()
  $parameterAttribute.Mandatory = [bool]$Mandatory

  $attributes = [System.Collections.ObjectModel.Collection[System.Attribute]]::New()
  $attributes.Add($parameterAttribute)
  $attributes.Add($Validator)

  $Dictionary.Add($Name, [System.Management.Automation.RuntimeDefinedParameter]::New(
      $Name, [string], $attributes
    ))
}
