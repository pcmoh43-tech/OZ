@echo off
title Download PrtEasyServer to Desktop
echo.
echo  Downloading PrtEasyServer.exe to Desktop...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest 'https://github.com/Terence0816/Windows-PrtEasyServer/releases/download/v2.0.0.0/PrtEasyServer.exe' -OutFile ($env:USERPROFILE + '\Desktop\PrtEasyServer.exe') -UseBasicParsing; Write-Host 'Saved to Desktop' -ForegroundColor Green; explorer ($env:USERPROFILE + '\Desktop')"
pause
