# Module-scope sensor output state, built at import and so dependent on file order:
# New-PrtgOutputDocument.ps1 sorts ahead of this file. Renaming either one breaks the import.
$script:OutputObject = New-PrtgOutputDocument
