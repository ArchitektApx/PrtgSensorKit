# Dot-sources the source tree when the module is imported straight from Source/ during
# development. ModuleBuilder concatenates these same files into the built .psm1 in Dist/, so
# this loop is not part of the built root module and never runs for an installed module.
# The directory list must stay equal to SourceDirectories in build.psd1; an artifact test
# compares the two.
foreach ($dir in 'Private', 'Public') {
  $path = Join-Path $PSScriptRoot $dir
  if (Test-Path -LiteralPath $path) {
    # -Recurse and Sort-Object FullName are ModuleBuilder's concatenation order, so the
    # source import defines the same functions in the same order as the built module.
    foreach ($file in Get-ChildItem -Path $path -Filter '*.ps1' -Recurse | Sort-Object FullName) {
      . $file.FullName
    }
  }
}
