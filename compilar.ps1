# =====================================================================
# Script PowerShell para Compilación de Ritmoo (Ritmoo)
# =====================================================================

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Configurar JAVA_HOME si es necesario
if (-not $env:JAVA_HOME) {
    $jdkPath = "C:\Program Files\Eclipse Adoptium\jdk-17.0.20.8-hotspot"
    if (Test-Path $jdkPath) {
        $env:JAVA_HOME = $jdkPath
        $env:PATH = "$jdkPath\bin;$env:PATH"
    }
}

function Show-Menu {
    Clear-Host
    Write-Host "=====================================================================" -ForegroundColor Cyan
    Write-Host "                 COMPILADOR RITMOO (PowerShell)                       " -ForegroundColor Green
    Write-Host "=====================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [1] Compilar AAB para Google Play (.aab) [RECOMENDADO PLAY STORE]" -ForegroundColor Yellow
    Write-Host "  [2] Compilar APK Release Universal (.apk) [Para instalar en celular]" -ForegroundColor White
    Write-Host "  [3] Compilar APKs Split por Arquitectura (arm64, arm32, x86_64)" -ForegroundColor White
    Write-Host "  [4] Compilar TODO (AAB Play Store + APK Release)" -ForegroundColor Magenta
    Write-Host "  [5] Compilar APK Debug (Para pruebas rapidas)" -ForegroundColor Gray
    Write-Host "  [6] Limpiar proyecto (flutter clean + flutter pub get)" -ForegroundColor Cyan
    Write-Host "  [0] Salir" -ForegroundColor Red
    Write-Host ""
    Write-Host "=====================================================================" -ForegroundColor Cyan
}

do {
    Show-Menu
    $opcion = Read-Host "Seleccione una opción (1-6 o 0)"

    switch ($opcion) {
        "1" {
            Clear-Host
            Write-Host "Compilando AAB para Google Play..." -ForegroundColor Yellow
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            flutter build appbundle --flavor github --release
            $sw.Stop()

            if ($LASTEXITCODE -eq 0) {
                Write-Host "`n[EXITO] AAB generado en $($sw.Elapsed.TotalSeconds.ToString('F1'))s:" -ForegroundColor Green
                Write-Host "build\app\outputs\bundle\githubRelease\app-github-release.aab" -ForegroundColor Cyan
                Invoke-Item "build\app\outputs\bundle\githubRelease"
            } else {
                Write-Host "`n[ERROR] Falló la compilación del AAB." -ForegroundColor Red
            }
            Read-Host "`nPresione ENTER para volver al menú..."
        }
        "2" {
            Clear-Host
            Write-Host "Compilando APK Release Universal..." -ForegroundColor Yellow
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            flutter build apk --flavor github --release
            $sw.Stop()

            if ($LASTEXITCODE -eq 0) {
                Write-Host "`n[EXITO] APK Release generado en $($sw.Elapsed.TotalSeconds.ToString('F1'))s:" -ForegroundColor Green
                Write-Host "build\app\outputs\flutter-apk\app-github-release.apk" -ForegroundColor Cyan
                Invoke-Item "build\app\outputs\flutter-apk"
            } else {
                Write-Host "`n[ERROR] Falló la compilación del APK." -ForegroundColor Red
            }
            Read-Host "`nPresione ENTER para volver al menú..."
        }
        "3" {
            Clear-Host
            Write-Host "Compilando APKs Split por Arquitectura..." -ForegroundColor Yellow
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            flutter build apk --flavor github --release --split-per-abi
            $sw.Stop()

            if ($LASTEXITCODE -eq 0) {
                Write-Host "`n[EXITO] APKs Split generados en $($sw.Elapsed.TotalSeconds.ToString('F1'))s:" -ForegroundColor Green
                Write-Host "build\app\outputs\flutter-apk\" -ForegroundColor Cyan
                Invoke-Item "build\app\outputs\flutter-apk"
            } else {
                Write-Host "`n[ERROR] Falló la compilación de APKs Split." -ForegroundColor Red
            }
            Read-Host "`nPresione ENTER para volver al menú..."
        }
        "4" {
            Clear-Host
            Write-Host "Compilando AAB y APK Release..." -ForegroundColor Magenta
            flutter build apk --flavor github --release
            if ($LASTEXITCODE -eq 0) {
                flutter build appbundle --flavor github --release
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "`n[EXITO] Todos los paquetes generados correctamente." -ForegroundColor Green
                    Invoke-Item "build\app\outputs\bundle\githubRelease"
                    Invoke-Item "build\app\outputs\flutter-apk"
                }
            }
            Read-Host "`nPresione ENTER para volver al menú..."
        }
        "5" {
            Clear-Host
            Write-Host "Compilando APK Debug..." -ForegroundColor Gray
            flutter build apk --flavor github --debug
            if ($LASTEXITCODE -eq 0) {
                Write-Host "`n[EXITO] APK Debug generado." -ForegroundColor Green
                Invoke-Item "build\app\outputs\flutter-apk"
            }
            Read-Host "`nPresione ENTER para volver al menú..."
        }
        "6" {
            Clear-Host
            Write-Host "Limpiando proyecto y actualizando paquetes..." -ForegroundColor Cyan
            flutter clean
            flutter pub get
            Write-Host "`n[LISTO] Dependencias listas." -ForegroundColor Green
            Read-Host "`nPresione ENTER para volver al menú..."
        }
        "0" {
            Write-Host "Saliendo..." -ForegroundColor Yellow
            break
        }
        Default {
            Write-Host "Opción inválida." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
} while ($opcion -ne "0")
