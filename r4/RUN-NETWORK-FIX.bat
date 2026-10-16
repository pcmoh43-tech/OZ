@echo off
title Network Diagnostic for Gaming
echo.
echo  Running network diagnostic (Administrator required)...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0network-fix-gaming.ps1\"'"
echo.
echo  If a UAC window appeared, click Yes.
pause
