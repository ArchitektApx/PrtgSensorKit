foreach ($dir in 'Private', 'Public') {
  $path = Join-Path $PSScriptRoot $dir
  if (Test-Path -LiteralPath $path) {
    foreach ($file in Get-ChildItem -Path $path -Filter '*.ps1') {
      . $file.FullName
    }
  }
}
