@echo off
chcp 65001 >nul
title SmartPower ERP - Setup Builder
echo ========================================================
echo  SmartPower ERP - Standalone Installer Build Pipeline
echo ========================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_setup.ps1"
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Build failed with error code %ERRORLEVEL%
    pause
    exit /b %ERRORLEVEL%
)
echo.
echo [SUCCESS] Build completed successfully!
pause
