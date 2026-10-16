@echo off
chcp 65001 >nul
title مشاركة الطابعة - r4
cd /d "%~dp0windows"
if not exist "run.bat" (
    echo.
    echo  خطأ: لم يتم العثور على السكربت!
    echo  تأكد أن مجلد windows موجود داخل r4
    echo.
    pause
    exit /b 1
)
powershell -Command "Start-Process cmd -ArgumentList '/c run.bat' -Verb RunAs -WorkingDirectory '%~dp0windows'"
exit /b 0
