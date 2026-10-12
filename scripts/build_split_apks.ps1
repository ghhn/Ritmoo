# PowerShell Script to build optimized per-ABI APKs for Ritmoo
Write-Host "Building optimized per-ABI APKs for Ritmoo..." -ForegroundColor Green

$env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-17.0.20.8-hotspot"
$env:PATH = "C:\Program Files\Eclipse Adoptium\jdk-17.0.20.8-hotspot\bin;" + $env:PATH

flutter build apk --flavor github --split-per-abi --debug

Write-Host "Build complete! Check build/app/outputs/flutter-apk/ for generated APKs." -ForegroundColor Cyan
