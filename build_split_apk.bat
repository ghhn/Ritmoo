@echo off
chcp 65001 >nul
title Compilar APKs Split - Ritmoo

if "%JAVA_HOME%"=="" (
    if exist "C:\Program Files\Eclipse Adoptium\jdk-17.0.20.8-hotspot" (
        set "JAVA_HOME=C:\Program Files\Eclipse Adoptium\jdk-17.0.20.8-hotspot"
        set "PATH=%JAVA_HOME%\bin;%PATH%"
    )
)

echo =====================================================================
echo   Compilando APKs Split por Arquitectura (arm64, arm32, x86_64)...
echo =====================================================================
echo.
call flutter build apk --flavor github --release --split-per-abi

if %ERRORLEVEL% equ 0 (
    echo.
    echo =====================================================================
    echo [EXITO] APKs Split generados correctamente en:
    echo build\app\outputs\flutter-apk\
    echo =====================================================================
    explorer.exe "build\app\outputs\flutter-apk"
) else (
    echo.
    echo [ERROR] Hubo un problema al compilar los APKs split.
)

pause
