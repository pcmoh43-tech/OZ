# ============================================================
#  انسخ هذا السكربت كاملاً والصقه في PowerShell على حاسوبك
#  (كليك يمين على PowerShell -> Run as administrator)
# ============================================================

$dest = "$env:USERPROFILE\Desktop\r4"
New-Item -ItemType Directory -Force -Path $dest | Out-Null

# --- ملف التشغيل الرئيسي ---
@'
@echo off
chcp 65001 >nul
title مشاركة الطابعة - r4
echo.
echo  [1] الحاسوب الذي عليه الطابعة (Host)
echo  [2] الحاسوب الثاني (Client)
echo  [3] خروج
echo.
set /p c="  اختر [1-3]: "
if "%c%"=="1" powershell -ExecutionPolicy Bypass -File "%~dp0host-share-printer.ps1"
if "%c%"=="2" powershell -ExecutionPolicy Bypass -File "%~dp0client-connect-printer.ps1"
if "%c%"=="3" exit /b 0
pause
'@ | Set-Content -Path "$dest\مشاركة-الطابعة.bat" -Encoding UTF8

# --- سكربت Host ---
@'
#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Clear-Host
Write-Host "=== مشاركة الطابعة - Host ===" -ForegroundColor Cyan
$printers = @(Get-CimInstance Win32_Printer | Where-Object { $_.Local -eq $true })
if ($printers.Count -eq 0) { Write-Host "لا توجد طابعات!" -ForegroundColor Red; Read-Host "Enter"; exit 1 }
for ($i=0; $i -lt $printers.Count; $i++) { Write-Host "  $($i+1). $($printers[$i].Name)" }
$sel = [int](Read-Host "اختر رقم الطابعة") - 1
$p = $printers[$sel]
$share = Read-Host "اسم المشاركة (Enter=$($p.Name))"
if ([string]::IsNullOrWhiteSpace($share)) { $share = ($p.Name -replace '[^a-zA-Z0-9]','') }
Write-Host "`n[1] تفعيل الشبكة..." -ForegroundColor Yellow
Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue
netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes | Out-Null
Write-Host "[2] مشاركة الطابعة..." -ForegroundColor Yellow
Set-Printer -Name $p.Name -Shared $true -ShareName $share
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.*" } | Select-Object -First 1).IPAddress
Write-Host "`n=== تم! ===" -ForegroundColor Green
Write-Host "IP: $ip"
Write-Host "المسار: \\$ip\$share" -ForegroundColor Green
@{hostname=$env:COMPUTERNAME;ip=$ip;shareName=$share} | ConvertTo-Json | Set-Content "$PSScriptRoot\host-config.json"
Read-Host "`nEnter للخروج"
'@ | Set-Content -Path "$dest\host-share-printer.ps1" -Encoding UTF8

# --- سكربت Client ---
@'
#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Clear-Host
Write-Host "=== الاتصال بالطابعة - Client ===" -ForegroundColor Cyan
$config = "$PSScriptRoot\host-config.json"
$host_ip = $null; $share = $null
if (Test-Path $config) {
    $s = Get-Content $config | ConvertFrom-Json
    Write-Host "إعدادات محفوظة: IP=$($s.ip) Share=$($s.shareName)"
    if ((Read-Host "استخدامها؟ [Y/n]") -notmatch "^[Nn]") { $host_ip = $s.ip; $share = $s.shareName }
}
if (-not $host_ip) { $host_ip = Read-Host "عنوان IP للحاسوب الأول" }
if (-not $share) { $share = Read-Host "اسم مشاركة الطابعة" }
if (-not (Test-Connection $host_ip -Count 2 -Quiet)) { Write-Host "لا يمكن الوصول!" -ForegroundColor Red; Read-Host "Enter"; exit 1 }
$path = "\\$host_ip\$share"
Write-Host "جاري التثبيت: $path" -ForegroundColor Yellow
try { Add-Printer -ConnectionName $path; Write-Host "تم بنجاح!" -ForegroundColor Green }
catch { rundll32 printui.dll,PrintUIEntry /in /n $path; Write-Host "تم (طريقة بديلة)" -ForegroundColor Green }
if ((Read-Host "طابعة افتراضية؟ [Y/n]") -notmatch "^[Nn]") { Set-Printer -Name (Get-Printer | Select-Object -Last 1).Name -Default }
Read-Host "`nEnter للخروج"
'@ | Set-Content -Path "$dest\client-connect-printer.ps1" -Encoding UTF8

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  تم! المجلد جاهز على سطح المكتب:" -ForegroundColor Green
Write-Host "  $dest" -ForegroundColor White
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  افتح مجلد r4 واضغط على: مشاركة-الطابعة.bat" -ForegroundColor Yellow
Write-Host ""
explorer $dest
