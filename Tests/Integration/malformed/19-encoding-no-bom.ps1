<#
.SYNOPSIS
  MALFORMED (PSK0011): non-ASCII content saved without a BOM.
.DESCRIPTION
  Channel name and message contain umlauts and this file is DELIBERATELY saved as UTF-8
  without a BOM. pwsh reads it correctly, but PRTG's Windows PowerShell 5.1 host parses
  BOM-less files as ANSI. Expected PRTG result: the sensor shows Up - but the channel
  name and message are mojibake (Gruene Kanaele with umlauts turns into 'GrÃ¼ne
  KanÃ¤le'). No parse error, which is exactly what makes this trap sneaky: the script
  works everywhere except in what PRTG displays. Doctor: PSK0011 Warning ('save the
  file as UTF-8 with BOM'). Do NOT re-save this file with an editor that adds a BOM;
  the BOM-less encoding IS the fixture. No network.
#>
Import-Module PrtgSensorKit

Invoke-PrtgSensor {
  New-PrtgChannel -Channel 'Grüne Kanäle' -Value 1 | Add-PrtgChannel
  Set-PrtgMessage 'Prüfung läuft'
}
