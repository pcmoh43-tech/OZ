#Requires -RunAsAdministrator
<#
.SYNOPSIS
    الاتصال بطابعة مشتركة على حاسوب آخر (Windows)
.DESCRIPTION
    يكتشف الطابعات المشتركة ويربطها ويضبط الإعدادات
#>

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Header {
    Clear-Host
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "   الاتصال بطابعة مشتركة - الحاسوب العميل" -ForegroundColor Cyan
    Write-Host "   (Client)" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
}

function Test-HostReachable {
    param([string]$HostAddress)

    Write-Host "   جاري التحقق من الاتصال بـ $HostAddress..." -ForegroundColor Yellow
    $ping = Test-Connection -ComputerName $HostAddress -Count 2 -Quiet -ErrorAction SilentlyContinue
    if ($ping) {
        Write-Host "   ✓ الحاسوب المضيف متصل" -ForegroundColor Green
        return $true
    }
    else {
        Write-Host "   ✗ لا يمكن الوصول للحاسوب المضيف" -ForegroundColor Red
        Write-Host "   تأكد من:" -ForegroundColor Yellow
        Write-Host "     - كلا الحاسوبين على نفس شبكة الواي-فاي" -ForegroundColor White
        Write-Host "     - عنوان IP صحيح" -ForegroundColor White
        Write-Host "     - جدار الحماية يسمح بالاتصال" -ForegroundColor White
        return $false
    }
}

function Find-SharedPrinters {
    param([string]$HostAddress)

    Write-Host "`n   جاري البحث عن الطابعات المشتركة..." -ForegroundColor Yellow

    $printers = @()
    try {
        $printers = Get-CimInstance -ClassName Win32_Printer -ComputerName $HostAddress -ErrorAction Stop |
            Where-Object { $_.Shared -eq $true }
    }
    catch {
        Write-Host "   تحذير: لم يتم العثور تلقائياً. سيتم الاتصال يدوياً." -ForegroundColor DarkYellow
    }

    return $printers
}

function Add-NetworkPrinter {
    param(
        [string]$HostAddress,
        [string]$ShareName,
        [string]$DisplayName
    )

    $printerPath = "\\$HostAddress\$ShareName"
    Write-Host "`n   جاري تثبيت الطابعة: $printerPath" -ForegroundColor Yellow

    # Remove existing connection with same name if exists
    $existing = Get-Printer -Name $DisplayName -ErrorAction SilentlyContinue
    if ($existing) {
        Remove-Printer -Name $DisplayName -ErrorAction SilentlyContinue
    }

    try {
        Add-Printer -ConnectionName $printerPath -ErrorAction Stop
        Write-Host "   ✓ تم تثبيت الطابعة بنجاح!" -ForegroundColor Green
        return $true
    }
    catch {
        # Fallback: use rundll32
        Write-Host "   محاولة طريقة بديلة..." -ForegroundColor DarkYellow
        $result = Start-Process -FilePath "rundll32.exe" -ArgumentList "printui.dll,PrintUIEntry /in /n `"$printerPath`"" -Wait -PassThru -NoNewWindow
        if ($result.ExitCode -eq 0) {
            Write-Host "   ✓ تم تثبيت الطابعة (طريقة بديلة)!" -ForegroundColor Green
            return $true
        }
        Write-Host "   ✗ فشل التثبيت: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Set-PrinterOptions {
    param(
        [string]$PrinterName,
        [bool]$SetAsDefault,
        [bool]$TestPrint
    )

    if ($SetAsDefault) {
        Write-Host "`n   تعيين كطابعة افتراضية..." -ForegroundColor Yellow
        $printer = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
        if (-not $printer) {
            # Find by connection name
            $printer = Get-Printer | Where-Object { $_.Name -like "*$PrinterName*" } | Select-Object -First 1
        }
        if ($printer) {
            Set-Printer -Name $printer.Name -Default
            Write-Host "   ✓ تم تعيين '$($printer.Name)' كطابعة افتراضية" -ForegroundColor Green
        }
    }

    if ($TestPrint) {
        Write-Host "`n   إرسال صفحة اختبار..." -ForegroundColor Yellow
        $printer = Get-Printer | Where-Object { $_.Name -like "*$PrinterName*" -or $_.ShareName -eq $PrinterName } | Select-Object -First 1
        if ($printer) {
            $testFile = Join-Path $env:TEMP "printer-test.txt"
            @"
================================
   اختبار الطابعة - Printer Test
================================
التاريخ: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
الحاسوب: $env:COMPUTERNAME
================================
"@ | Set-Content -Path $testFile -Encoding UTF8

            Start-Process -FilePath $testFile -Verb Print -ErrorAction SilentlyContinue
            Write-Host "   ✓ تم إرسال صفحة الاختبار" -ForegroundColor Green
        }
    }
}

function Save-ClientConfig {
    param(
        [string]$HostAddress,
        [string]$ShareName,
        [string]$PrinterName
    )

    $configPath = Join-Path $PSScriptRoot "client-config.json"
    @{
        hostAddress = $HostAddress
        shareName   = $ShareName
        printerName = $PrinterName
        connectedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    } | ConvertTo-Json | Set-Content -Path $configPath -Encoding UTF8

    Write-Host "   ✓ تم حفظ الإعدادات في: $configPath" -ForegroundColor DarkGray
}

# ========== Main Menu ==========
Write-Header

# Check for saved host config
$configPath = Join-Path $PSScriptRoot "host-config.json"
$hostAddress = $null

if (Test-Path $configPath) {
    Write-Host "تم العثور على إعدادات محفوظة من الحاسوب المضيف." -ForegroundColor Green
    $saved = Get-Content $configPath | ConvertFrom-Json
    Write-Host "  IP: $($saved.ip) | المشاركة: $($saved.shareName)" -ForegroundColor White
    $useSaved = Read-Host "`nاستخدام الإعدادات المحفوظة؟ [Y/n]"
    if ($useSaved -ne "n" -and $useSaved -ne "N") {
        $hostAddress = $saved.ip
        $savedShareName = $saved.shareName
    }
}

if (-not $hostAddress) {
    Write-Host "أدخل معلومات الحاسوب الذي عليه الطابعة:" -ForegroundColor White
    Write-Host ""
    Write-Host "  1. بالعنوان IP (مثال: 192.168.1.50)"
    Write-Host "  2. باسم الحاسوب (مثال: DESKTOP-ABC123)"
    Write-Host ""
    $inputType = Read-Host "طريقة الاتصال [1/2]"
    $hostAddress = Read-Host "أدخل $(if ($inputType -eq '2') { 'اسم الحاسوب' } else { 'عنوان IP' })"
}

if (-not (Test-HostReachable -HostAddress $hostAddress)) {
    Read-Host "`nاضغط Enter للخروج"
    exit 1
}

# Discover or manual share name
$sharedPrinters = Find-SharedPrinters -HostAddress $hostAddress
$shareName = $null

if ($savedShareName) {
    $shareName = $savedShareName
    Write-Host "`n   استخدام المشاركة المحفوظة: $shareName" -ForegroundColor Cyan
}
elseif ($sharedPrinters.Count -gt 0) {
    Write-Host "`nالطابعات المشتركة المكتشفة:" -ForegroundColor White
    for ($i = 0; $i -lt $sharedPrinters.Count; $i++) {
        Write-Host "  $($i + 1). $($sharedPrinters[$i].ShareName) ($($sharedPrinters[$i].Name))"
    }
    $sel = Read-Host "`nاختر رقم الطابعة"
    $shareName = $sharedPrinters[[int]$sel - 1].ShareName
}
else {
    $shareName = Read-Host "`nأدخل اسم مشاركة الطابعة (Share Name)"
}

# Connection options
Write-Host "`nخيارات الإعداد:" -ForegroundColor White
$setDefault = Read-Host "  تعيين كطابعة افتراضية؟ [Y/n]"
$doTestPrint = Read-Host "  طباعة صفحة اختبار؟ [Y/n]"

$setDefaultBool = ($setDefault -ne "n" -and $setDefault -ne "N")
$testPrintBool = ($doTestPrint -ne "n" -and $doTestPrint -ne "N")

# Install printer
$success = Add-NetworkPrinter -HostAddress $hostAddress -ShareName $shareName -DisplayName $shareName

if ($success) {
    Set-PrinterOptions -PrinterName $shareName -SetAsDefault $setDefaultBool -TestPrint $testPrintBool
    Save-ClientConfig -HostAddress $hostAddress -ShareName $shareName -PrinterName $shareName

    Write-Host "`n============================================" -ForegroundColor Cyan
    Write-Host "   تم الاتصال بالطابعة بنجاح!" -ForegroundColor Green
    Write-Host "   المسار: \\$hostAddress\$shareName" -ForegroundColor White
    Write-Host "============================================" -ForegroundColor Cyan
}
else {
    Write-Host "`n============================================" -ForegroundColor Cyan
    Write-Host "   فشل الاتصال. جرب:" -ForegroundColor Red
    Write-Host "   1. تشغيل host-share-printer.ps1 على الحاسوب المضيف" -ForegroundColor White
    Write-Host "   2. التأكد من نفس شبكة الواي-فاي" -ForegroundColor White
    Write-Host "   3. إيقاف VPN مؤقتاً" -ForegroundColor White
    Write-Host "============================================" -ForegroundColor Cyan
}

Read-Host "`nاضغط Enter للخروج"
