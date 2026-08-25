# Module-scope sensor output state. In the built single-file module every source file shares
# one script scope, so $script:OutputObject is visible to all functions without touching the
# caller's session. Clear-PrtgOutput re-initializes it (needed between runs and in tests).
#
# This is a top-level statement, so New-PrtgOutputDocument must already be defined when the
# built module reaches this line: the holder calls a function defined in another file at
# import, and a function only enters scope when execution reaches its definition. The builder
# orders source files by full relative path, so a subfolder interleaves among top-level files
# as if the folder name were a file name; both files therefore sit in Private/Output, where
# New-PrtgOutputDocument.ps1 sorts ahead of PrtgOutputDocument.ps1. Renaming either file, or
# moving one out of the folder, can break the import.
$script:OutputObject = New-PrtgOutputDocument
