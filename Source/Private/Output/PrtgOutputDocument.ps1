# Module-scope sensor output state. In the built single-file module every source file shares
# one script scope, so $script:OutputObject is visible to all functions without touching the
# caller's session. Clear-PrtgOutput re-initializes it (needed between runs and in tests).
#
# This is a top-level statement, so New-PrtgOutputDocument must already be defined when the
# built module reaches this line. The builder concatenates Private/ alphabetically, which puts
# New-PrtgOutputDocument.ps1 ahead of PrtgState.ps1; renaming either file can break the import.
$script:OutputObject = New-PrtgOutputDocument
