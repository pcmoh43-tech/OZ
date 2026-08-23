@echo off
chcp 65001 >nul
title Printer Sharing - r4
cd /d "%~dp0windows"
if not exist "run.bat" (
    echo ERROR: Script not found. Make sure windows folder exists inside r4.
    pause
    exit /b 1
)
powershell -Command "Start-Process cmd -ArgumentList '/c run.bat' -Verb RunAs -WorkingDirectory '%~dp0windows'"
exit /b 0
