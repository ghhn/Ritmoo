@echo off
chcp 65001 >nul
title Compilar AAB para Google Play - Ritmoo

if "%JAVA_HOME%"=="" (
    if exist "C:\Program Files\Eclipse Adoptium\jdk-17.0.20.8-hotspot" (
        set "JAVA_HOME=C:\Program Files\Eclipse Adoptium\jdk-17.0.20.8-hotspot"
        set "PATH=%JAVA_HOME%\bin;%PATH%"
    )
)

echo =====================================================================
echo   Compilando App Bundle (.aab) para Google Play Store...
echo =====================================================================
echo.
call flutter build appbundle --flavor github --release

if %ERRORLEVEL% equ 0 (
    echo.
    echo =====================================================================
    echo [EXITO] Archivo AAB generado correctamente en:
    echo build\app\outputs\bundle\githubRelease\app-github-release.aab
    echo =====================================================================
    explorer.exe "build\app\outputs\bundle\githubRelease"
) else (
    echo.
    echo [ERROR] Hubo un problema al compilar el archivo AAB.
)

pause
