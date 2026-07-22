# ❌ Custom errors and low-level output control

`Invoke-PrtgSensor` sets **all errors** to **terminating**, catches the error/exception
object, and returns it as a parsed error response to PRTG.

```plaintext
line:22 char:13
--- message: The remote server returned an error: (500) Internal Server Error.
--- line: $Response = Invoke-RestMethod -Method Get -Uri $URL -Headers $Header
```

If you just want **some** errors to be non-terminating, you can override this by using the
`-ErrorAction` parameter on the cmdlet or by setting the `$ErrorActionPreference` to
`'SilentlyContinue'` and then back to `'Stop'` when you want `Invoke-PrtgSensor` to handle
errors again.

See [16-making-errors-nonterminating.ps1](../Examples/16-making-errors-nonterminating.ps1)
for a more detailed example on how to make some errors non-terminating.

## Going fully low-level

If you want even more fine-grained control over errors and output, you can use the
lower-level cmdlets yourself.

```powershell
Import-Module PrtgSensorKit

# Always call Clear-PrtgOutput before defining any channels or setting a message/error to
# generate an empty output object in the scope
Clear-PrtgOutput

$API_URL = 'https://api.example.com/data'
$Header = @{
  'Authorization' = 'Bearer 1234567890'
}

try {
  $Response = Invoke-RestMethod -Method Get -Uri $API_URL -Headers $Header -ErrorAction Stop
  New-PrtgChannel -Channel 'Response' -Value $Response.Status | Add-PrtgChannel
  Write-PrtgOutput
} catch {
  Write-PrtgError -ErrorString 'My custom error message'
}
```

When manually using the lower-level cmdlets, make sure to follow some **important limitations**:

- **Every** command's output has to be piped into a channel, assigned to a variable, or sent
  to `Out-Null` - there's no output guard here.
- **On your happy path**, call `Write-PrtgOutput` to emit the sensor JSON.
- **On your error path**, call `Write-PrtgError` to emit an error response.
- **`Write-PrtgOutput` and `Write-PrtgError` should always short-circuit the execution of
  your script**, otherwise the output will be corrupted.

`Write-PrtgLog` works in low-level scripts too (it never touches the output stream); see
[File logging](logging.md).

See [04-manual-output-and-errors.ps1](../Examples/04-manual-output-and-errors.ps1) for a
more detailed example on how to use the lower-level cmdlets.
