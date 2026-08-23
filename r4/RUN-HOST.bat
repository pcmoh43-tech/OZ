@echo off
title HOST - Wait for Client PC
echo.
echo  Starting HOST script (USB Printer)...
echo  Run as Administrator required.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0host-wait.ps1"
pause
