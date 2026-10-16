# Fix broken bat file on user desktop - run in PowerShell
$dest = "$env:USERPROFILE\Desktop\r4"
New-Item -ItemType Directory -Force -Path $dest | Out-Null

@'
@echo off
chcp 65001 >nul 2>&1
title Printer Sharing - r4
color 0B
echo.
echo  ============================================
echo     Printer Sharing - r4
echo  ============================================
echo.
echo  [1] Host  - Computer WITH printer
echo  [2] Client - Computer WITHOUT printer
echo  [3] Exit
echo.
set /p choice="  Choose [1-3]: "
if "%choice%"=="1" goto host
if "%choice%"=="2" goto client
if "%choice%"=="3" exit /b 0
echo Invalid choice!
pause
exit /b 1
:host
echo.
echo Starting HOST script...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0host-share-printer.ps1"
goto end
:client
echo.
echo Starting CLIENT script...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0client-connect-printer.ps1"
goto end
:end
echo.
pause
'@ | Set-Content -Path "$dest\START.bat" -Encoding ASCII

Write-Host "Fixed! Use START.bat in folder: $dest" -ForegroundColor Green
explorer $dest
