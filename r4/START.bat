@echo off
title R4 Printer Sharing
echo.
echo  [1] PC 1 - HOST  (USB printer - wait for client)
echo  [2] PC 2 - CLIENT (connect and install printer)
echo  [3] Exit
echo.
set /p c="Choose [1-3]: "
if "%c%"=="1" call "%~dp0RUN-HOST.bat"
if "%c%"=="2" call "%~dp0RUN-CLIENT.bat"
exit /b 0
