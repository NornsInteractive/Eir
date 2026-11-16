$ErrorActionPreference = 'Stop'
$env:Path = 'C:\valhalla-build\.cargo\bin;C:\valhalla-build\eir-flutter\bin;C:\Program Files\Git\cmd;C:\Program Files\Git\bin;' + $env:Path

Set-Location 'C:\valhalla-build\eir-build'

Write-Host "=== 1. Checking Flutter Environment ==="
& flutter.bat --version

Write-Host "=== 2. Getting Flutter Dependencies ==="
& flutter.bat pub get

Write-Host "=== 3. Building Flutter Windows Release ==="
& flutter.bat build windows --release

Write-Host "=== 4. Packaging Windows Store MSIX ==="
& powershell -ExecutionPolicy Bypass -File tool\package_windows_msix.ps1 -Project .

Write-Host "=== 5. Packaging Portable Windows ZIP ==="
$bundle = 'build\windows\x64\runner\Release'
$output = 'build\windows-artifacts'
New-Item -ItemType Directory -Path $output -Force | Out-Null
$zip = Join-Path $output "eir-v1.0.40-windows-x64.zip"
Compress-Archive -Path "$bundle\*" -DestinationPath $zip -CompressionLevel Optimal -Force
$zipHash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
"$zipHash  $([IO.Path]::GetFileName($zip))" | Set-Content "$zip.sha256" -Encoding ascii
Write-Host "Portable ZIP created: $zip ($zipHash)"

Write-Host "=== Artifacts in build\windows-artifacts ==="
Get-ChildItem -Path $output | Select-Object Name, Length
