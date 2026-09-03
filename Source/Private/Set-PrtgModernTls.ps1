function Set-PrtgModernTls {
  <#
  .SYNOPSIS
    Forces modern TLS (1.2, plus 1.3 when available) for all web requests in this process.
  .DESCRIPTION
    Sets [Net.ServicePointManager]::SecurityProtocol to TLS 1.2, adding TLS 1.3 when the
    runtime knows it. The assignment replaces the previous protocol set rather than adding
    to it, and falls back to TLS 1.2 alone when TLS 1.3 is unavailable.
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Non-interactive sensor bootstrap that flips a process-wide TLS setting; a -Confirm prompt would stall a PRTG probe.')]
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
    Justification = 'TLS is an acronym, not a plural; the noun ModernTls is singular.')]
  [CmdletBinding()]
  param()

  $tls12 = [System.Net.SecurityProtocolType]::Tls12

  # Probe for the Tls13 enum value without referencing it statically, so this parses and
  # runs on runtimes that predate it.
  $tls13 = $tls12
  if ([System.Enum]::TryParse('Tls13', [ref]$tls13) -and $tls13 -ne $tls12) {
    try {
      [System.Net.ServicePointManager]::SecurityProtocol = $tls12 -bor $tls13
      return
    } catch {
      Write-Verbose "Set-PrtgModernTls: TLS 1.3 not supported by this OS/runtime, falling back to TLS 1.2 only. ($($_.Exception.Message))"
    }
  }

  [System.Net.ServicePointManager]::SecurityProtocol = $tls12
}
