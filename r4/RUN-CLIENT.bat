@echo off
title CLIENT - Connect to Printer
echo.
echo  Starting CLIENT script...
echo  Make sure HOST script is running first!
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0client-connect.ps1"
pause
