function New-PrtgDynamicParameter {
  <#
    .SYNOPSIS
      Builds one companion parameter for New-PrtgChannel and adds it to the dictionary.
    .DESCRIPTION
      A fresh ParameterAttribute is built per call, so companion parameters never share
      mandatory state. The validator arrives constructed; the caller decides whether to share it.
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
