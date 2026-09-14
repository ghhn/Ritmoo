@echo off
chcp 65001 >nul
title Compilar APK Release - Ritmoo

if "%JAVA_HOME%"=="" (
    if exist "C:\Program Files\Eclipse Adoptium\jdk-17.0.20.8-hotspot" (
        set "JAVA_HOME=C:\Program Files\Eclipse Adoptium\jdk-17.0.20.8-hotspot"
        set "PATH=%JAVA_HOME%\bin;%PATH%"
    )
)

echo =====================================================================
echo   Compilando APK Release Universal...
echo =====================================================================
echo.
call flutter build apk --flavor github --release

if %ERRORLEVEL% equ 0 (
    echo.
    echo =====================================================================
    echo [EXITO] APK Release generado correctamente en:
    echo build\app\outputs\flutter-apk\app-github-release.apk
    echo =====================================================================
    explorer.exe "build\app\outputs\flutter-apk"
) else (
    echo.
    echo [ERROR] Hubo un problema al compilar el APK Release.
)

pause
