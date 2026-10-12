@echo off
chcp 65001 >nul
title Compilador Ritmoo (Ritmoo)

:: Configurar JAVA_HOME si no esta presente
if "%JAVA_HOME%"=="" (
    if exist "C:\Program Files\Eclipse Adoptium\jdk-17.0.20.8-hotspot" (
        set "JAVA_HOME=C:\Program Files\Eclipse Adoptium\jdk-17.0.20.8-hotspot"
        set "PATH=%JAVA_HOME%\bin;%PATH%"
    )
)

:MENU
cls
echo =====================================================================
echo                     COMPILADOR RITMOO
echo =====================================================================
echo.
echo   [1] Compilar AAB para Google Play (.aab) [RECOMENDADO PARA PLAY STORE]
echo   [2] Compilar APK Release Universal (.apk) [Para instalar en celular]
echo   [3] Compilar APKs Split por Arquitectura (arm64, arm32, x86_64)
echo   [4] Compilar TODO (AAB para Play Store + APK Release)
echo   [5] Compilar APK Debug (Para pruebas rapidas)
echo   [6] Limpiar proyecto (flutter clean + flutter pub get)
echo   [0] Salir
echo.
echo =====================================================================
set /p OPCION="Seleccione una opcion (1-6 o 0): "

if "%OPCION%"=="1" goto BUILD_AAB
if "%OPCION%"=="2" goto BUILD_APK
if "%OPCION%"=="3" goto BUILD_SPLIT
if "%OPCION%"=="4" goto BUILD_ALL
if "%OPCION%"=="5" goto BUILD_DEBUG
if "%OPCION%"=="6" goto CLEAN
if "%OPCION%"=="0" goto SALIR

echo.
echo Opcion no valida. Intente de nuevo.
timeout /t 2 >nul
goto MENU

:BUILD_AAB
cls
echo =====================================================================
echo   Compilando App Bundle (.aab) para Google Play...
echo =====================================================================
echo Comando: flutter build appbundle --flavor github --release
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
    echo [ERROR] Hubo un problema al compilar el AAB.
)
pause
goto MENU

:BUILD_APK
cls
echo =====================================================================
echo   Compilando APK Release Universal...
echo =====================================================================
echo Comando: flutter build apk --flavor github --release
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
    echo [ERROR] Hubo un problema al compilar el APK.
)
pause
goto MENU

:BUILD_SPLIT
cls
echo =====================================================================
echo   Compilando APKs Split por Arquitectura...
echo =====================================================================
echo Comando: flutter build apk --flavor github --release --split-per-abi
echo.
call flutter build apk --flavor github --release --split-per-abi
if %ERRORLEVEL% equ 0 (
    echo.
    echo =====================================================================
    echo [EXITO] APKs generados correctamente en:
    echo build\app\outputs\flutter-apk\
    echo =====================================================================
    explorer.exe "build\app\outputs\flutter-apk"
) else (
    echo.
    echo [ERROR] Hubo un problema al compilar los APKs split.
)
pause
goto MENU

:BUILD_ALL
cls
echo =====================================================================
echo   Compilando AAB para Google Play y APK Release...
echo =====================================================================
echo [1/2] Compilando APK Release...
call flutter build apk --flavor github --release
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Fallo la compilacion del APK.
    pause
    goto MENU
)
echo.
echo [2/2] Compilando AAB para Google Play...
call flutter build appbundle --flavor github --release
if %ERRORLEVEL% equ 0 (
    echo.
    echo =====================================================================
    echo [EXITO] Todos los paquetes fueron generados correctamente:
    echo - APK: build\app\outputs\flutter-apk\app-github-release.apk
    echo - AAB: build\app\outputs\bundle\githubRelease\app-github-release.aab
    echo =====================================================================
    explorer.exe "build\app\outputs\bundle\githubRelease"
    explorer.exe "build\app\outputs\flutter-apk"
) else (
    echo.
    echo [ERROR] Fallo la compilacion del AAB.
)
pause
goto MENU

:BUILD_DEBUG
cls
echo =====================================================================
echo   Compilando APK Debug...
echo =====================================================================
echo Comando: flutter build apk --flavor github --debug
echo.
call flutter build apk --flavor github --debug
if %ERRORLEVEL% equ 0 (
    echo.
    echo =====================================================================
    echo [EXITO] APK Debug generado en:
    echo build\app\outputs\flutter-apk\
    echo =====================================================================
    explorer.exe "build\app\outputs\flutter-apk"
) else (
    echo.
    echo [ERROR] Hubo un problema al compilar el APK debug.
)
pause
goto MENU

:CLEAN
cls
echo =====================================================================
echo   Limpiando proyecto y reinstalando dependencias...
echo =====================================================================
call flutter clean
echo.
echo Obteniendo paquetes...
call flutter pub get
echo.
echo [LISTO] Proyecto limpio y dependencias actualizadas.
pause
goto MENU

:SALIR
exit /b 0
