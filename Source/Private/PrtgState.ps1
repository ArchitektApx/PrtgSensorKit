# Module-scope sensor output state. In the built single-file module every source file shares
# one script scope, so $script:OutputObject is visible to all functions without touching the
# caller's session. Clear-PrtgOutput re-initializes it (needed between runs and in tests).
$script:OutputObject = [PSCustomObject]@{
  prtg = [PSCustomObject]@{
    result = [System.Collections.ArrayList]@()
    text   = ''
  }
}
