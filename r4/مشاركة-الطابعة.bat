@echo off
chcp 65001 >nul
title مشاركة الطابعة - r4
color 0B

echo.
echo  ============================================
echo     مشاركة الطابعة - r4
echo  ============================================
echo.
echo  الملفات في هذا المجلد:
echo    - مشاركة-الطابعة.bat  (هذا الملف)
echo    - host-share-printer.ps1
echo    - client-connect-printer.ps1
echo.
echo  اختر:
echo    [1] الحاسوب الذي عليه الطابعة (Host)
echo    [2] الحاسوب الثاني (Client)
echo    [3] عرض محتويات المجلد
echo    [4] خروج
echo.

set /p choice="  اختر [1-4]: "

if "%choice%"=="1" goto host
if "%choice%"=="2" goto client
if "%choice%"=="3" goto list
if "%choice%"=="4" exit /b 0
echo  اختيار غير صالح!
pause
exit /b 1

:host
powershell -ExecutionPolicy Bypass -File "%~dp0host-share-printer.ps1"
goto end

:client
powershell -ExecutionPolicy Bypass -File "%~dp0client-connect-printer.ps1"
goto end

:list
echo.
echo  === محتويات المجلد ===
dir /b "%~dp0"
echo.
echo  === مجلد windows ===
dir /b "%~dp0windows" 2>nul
echo.
echo  === مجلد linux ===
dir /b "%~dp0linux" 2>nul
echo.
pause
goto end

:end
pause
