<#
.SYNOPSIS
  Validates the malformed integration sensors against Invoke-PrtgSensorDoctor.

.DESCRIPTION
  Runs the Doctor (script checks only) on each malformed sensor and asserts the expected
  primary finding (check id + severity) is present. This is the automatable counterpart to
  the manual PRTG validation matrix in README.md: it confirms the Doctor predicts the
  breakage each malformed_* sensor demonstrates.

  Works against either layout, matching files by their 'NN-name' fragment under -Path:
    - the repo:            Tests/Integration/malformed/NN-name.ps1
    - the PRTG deployment: <EXEXML>/malformed_NN-name.ps1  (flattened, prefixed)

  Exits non-zero if any check does not match, so it can gate a release.

.PARAMETER Path
  Folder searched recursively for the malformed sensor scripts. Defaults to the folder this
  helper lives in, so on the probe just run it from the EXEXML directory.

.EXAMPLE
  ./Test-MalformedDoctor.ps1

.EXAMPLE
  ./Test-MalformedDoctor.ps1 -Path 'C:\Program Files (x86)\PRTG Network Monitor\Custom Sensors\EXEXML'
#>
[CmdletBinding()]
param(
  [string]$Path = $PSScriptRoot
)

Import-Module PrtgSensorKit -ErrorAction Stop

# Expected primary Doctor finding per malformed sensor (mirrors README.md's matrix).
$expected = [ordered]@{
  '09-dryrun-left-in'           = @{ CheckId = 'PSK0010'; Severity = 'Warning' }
  '10-manual-output-in-block'   = @{ CheckId = 'PSK0005'; Severity = 'Error' }
  '11-multiple-invoke'          = @{ CheckId = 'PSK0007'; Severity = 'Error' }
  '12-trailing-output'          = @{ CheckId = 'PSK0008'; Severity = 'Warning' }
  '13-restart-inside-block'     = @{ CheckId = 'PSK0003'; Severity = 'Error' }
  '14-restart-misplaced-import' = @{ CheckId = 'PSK0004'; Severity = 'Error' }
  '15-web-without-tls'          = @{ CheckId = 'PSK0009'; Severity = 'Info' }
  '16-syntax-error'             = @{ CheckId = 'PSK0001'; Severity = 'Error' }
}

$pass = 0
$fail = 0

foreach ($key in $expected.Keys) {
  $exp = $expected[$key]
  $file = Get-ChildItem -Path $Path -Recurse -Filter "*$key*.ps1" -ErrorAction SilentlyContinue |
    Select-Object -First 1

  if (-not $file) {
    Write-Host ("MISS  {0,-30} expected {1} {2} - no file found under {3}" -f $key, $exp.CheckId, $exp.Severity, $Path)
    $fail++
    continue
  }

  $findings = Invoke-PrtgSensorDoctor -ScriptPath $file.FullName -SkipEnvironmentChecks 6>$null
  $hit = @($findings | Where-Object { $_.CheckId -eq $exp.CheckId -and $_.Severity -eq $exp.Severity })

  if ($hit.Count -gt 0) {
    Write-Host ("PASS  {0,-34} {1} {2}" -f $file.Name, $exp.CheckId, $exp.Severity)
    $pass++
  } else {
    $got = (@($findings | Where-Object { $_.Severity -in 'Error', 'Warning', 'Info' } |
      ForEach-Object { "$($_.CheckId):$($_.Severity)" }) -join ', ')
    Write-Host ("FAIL  {0,-34} expected {1} {2}; got [{3}]" -f $file.Name, $exp.CheckId, $exp.Severity, $got)
    $fail++
  }
}

Write-Host ''
Write-Host ("Doctor validation: {0} passed, {1} failed." -f $pass, $fail)
if ($fail -gt 0) { exit 1 }
