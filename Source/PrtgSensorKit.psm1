# Dev-only loader, never part of the built module. The directory list must match
# SourceDirectories in build.psd1; an artifact test checks it.
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
