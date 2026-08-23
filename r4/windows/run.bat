@echo off
chcp 65001 >nul
title مشاركة الطابعة - Printer Sharing

echo.
echo  ============================================
echo     مشاركة الطابعة - Printer Sharing
echo  ============================================
echo.
echo  اختر السكربت المطلوب:
echo.
echo    [1] الحاسوب المضيف (Host) - مشاركة الطابعة
echo    [2] الحاسوب العميل (Client) - الاتصال بالطابعة
echo    [3] خروج
echo.

set /p choice="  اختر [1-3]: "

if "%choice%"=="1" goto host
if "%choice%"=="2" goto client
if "%choice%"=="3" exit /b 0

echo  اختيار غير صالح!
pause
exit /b 1

:host
echo.
echo  جاري تشغيل سكربت المشاركة...
echo  (يتطلب صلاحيات المسؤول)
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0host-share-printer.ps1"
goto end

:client
echo.
echo  جاري تشغيل سكربت الاتصال...
echo  (يتطلب صلاحيات المسؤول)
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0client-connect-printer.ps1"
goto end

:end
pause
