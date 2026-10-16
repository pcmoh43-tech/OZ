@echo off
title Install All R4 Scripts
echo.
echo  This will add ALL missing files to Desktop\r4
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-on-desktop.ps1"
pause
