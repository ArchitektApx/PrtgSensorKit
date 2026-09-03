function Test-PrtgDoctorPSK0011 {
  <#
  .SYNOPSIS
    PSK0011: source encoding (raw bytes, no AST needed)
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Parsed
  )

  # Windows PowerShell 5.1 parses BOM-less .ps1 as ANSI, pwsh as UTF-8, so mojibake appears
  # only under PRTG. This runs even on a script that fails to parse: encoding can be the cause.
  $bytes = [System.IO.File]::ReadAllBytes($Parsed.ScriptPath)
  # UTF-8, UTF-16 LE/BE, and UTF-32 BE BOMs; the FF FE prefix also covers UTF-32 LE.
  $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) -or
            ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or
            ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) -or
            ($bytes.Length -ge 4 -and $bytes[0] -eq 0x00 -and $bytes[1] -eq 0x00 -and $bytes[2] -eq 0xFE -and $bytes[3] -eq 0xFF)
  $hasNonAscii = $false
  if (-not $hasBom) {
    foreach ($byte in $bytes) {
      if ($byte -gt 0x7F) { $hasNonAscii = $true; break }
    }
  }
  if ($hasNonAscii) {
    New-PrtgDoctorFinding -CheckId 'PSK0011' -Severity 'Warning' `
      -Message 'The script contains non-ASCII characters but has no BOM. Windows PowerShell 5.1 reads BOM-less files as ANSI, so string literals with umlauts, accents, or symbols are silently misread under PRTG even though the script looks correct in pwsh.' `
      -Recommendation 'Save the file as UTF-8 with BOM.'
  } else {
    New-PrtgDoctorFinding -CheckId 'PSK0011' -Severity 'Pass' -Message 'Script encoding is safe for Windows PowerShell 5.1 (all-ASCII or BOM present).'
  }
}
