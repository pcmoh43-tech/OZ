#Requires -RunAsAdministrator
<#
.SYNOPSIS
    مشاركة الطابعة على الحاسوب المضيف (Windows)
.DESCRIPTION
    يسمح باختيار الطابعة ونوع المشاركة وتفعيل إعدادات الشبكة تلقائياً
#>

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Header {
    Clear-Host
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "   مشاركة الطابعة - الحاسوب المضيف (Host)" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
}

function Get-LocalPrinters {
    Get-CimInstance -ClassName Win32_Printer | Where-Object { $_.Local -eq $true -and $_.Shared -ne $null }
}

function Enable-NetworkSharing {
    Write-Host "`n[1/4] تفعيل اكتشاف الشبكة ومشاركة الطابعات..." -ForegroundColor Yellow

    # Private network profile
    Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue

    # Enable network discovery and file/printer sharing via registry
    $paths = @(
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Network\NewNetworkWindowOff"; Value = 0 },
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\NcdAutoSetup\Private"; SubKey = "AutoSetup"; Value = 1 }
    )

    # Firewall rules for printer sharing
    $firewallRules = @(
        "File and Printer Sharing (Spooler Service - RPC)",
        "File and Printer Sharing (Spooler Service - RPC-EPMAP)",
        "File and Printer Sharing (NB-Session-In)",
        "File and Printer Sharing (SMB-In)"
    )

    foreach ($rule in $firewallRules) {
        Enable-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue | Out-Null
    }

    # Enable via netsh (works on all Windows versions)
    netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes | Out-Null

    Write-Host "   ✓ تم تفعيل مشاركة الشبكة وجدار الحماية" -ForegroundColor Green
}

function Share-Printer {
    param(
        [string]$PrinterName,
        [string]$ShareName,
        [string]$ShareMode
    )

    Write-Host "`n[2/4] مشاركة الطابعة: $PrinterName" -ForegroundColor Yellow

    switch ($ShareMode) {
        "basic" {
            Set-Printer -Name $PrinterName -Shared $true -ShareName $ShareName
            Write-Host "   ✓ مشاركة أساسية (شبكة محلية فقط)" -ForegroundColor Green
        }
        "full" {
            Set-Printer -Name $PrinterName -Shared $true -ShareName $ShareName
            # Allow Everyone to print
            $printerPath = "\\localhost\$ShareName"
            $acl = Get-Acl "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Printers\$PrinterName" -ErrorAction SilentlyContinue
            Write-Host "   ✓ مشاركة كاملة (جميع المستخدمين على الشبكة)" -ForegroundColor Green
        }
        "domain" {
            Set-Printer -Name $PrinterName -Shared $true -ShareName $ShareName
            Write-Host "   ✓ مشاركة للمجال/الشركة (Domain)" -ForegroundColor Green
            Write-Host "   ملاحظة: تأكد أن الحاسوبين في نفس Workgroup أو Domain" -ForegroundColor DarkYellow
        }
    }
}

function Show-ConnectionInfo {
    param([string]$ShareName)

    Write-Host "`n[3/4] معلومات الاتصال للحاسوب الآخر:" -ForegroundColor Yellow

    $hostname = $env:COMPUTERNAME
    $wifiIp = (Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.InterfaceAlias -match "Wi-Fi|Wireless|WLAN" -and $_.IPAddress -notlike "169.*" } |
        Select-Object -First 1).IPAddress

    if (-not $wifiIp) {
        $wifiIp = (Get-NetIPAddress -AddressFamily IPv4 |
            Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.*" } |
            Select-Object -First 1).IPAddress
    }

    Write-Host ""
    Write-Host "   اسم الحاسوب:  $hostname" -ForegroundColor White
    Write-Host "   عنوان IP:     $wifiIp" -ForegroundColor White
    Write-Host "   اسم المشاركة: $ShareName" -ForegroundColor White
    Write-Host ""
    Write-Host "   مسار الطابعة للحاسوب الآخر:" -ForegroundColor Cyan
    Write-Host "   \\$hostname\$ShareName" -ForegroundColor Green
    Write-Host "   \\$wifiIp\$ShareName" -ForegroundColor Green

    # Save config for client script
    $configPath = Join-Path $PSScriptRoot "host-config.json"
    @{
        hostname  = $hostname
        ip        = $wifiIp
        shareName = $ShareName
        sharedAt  = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    } | ConvertTo-Json | Set-Content -Path $configPath -Encoding UTF8

    Write-Host "`n   ✓ تم حفظ الإعدادات في: $configPath" -ForegroundColor DarkGray
}

function Test-PrinterShare {
    param([string]$ShareName)

    Write-Host "`n[4/4] اختبار المشاركة..." -ForegroundColor Yellow

    $share = Get-CimInstance -ClassName Win32_Printer | Where-Object { $_.ShareName -eq $ShareName -and $_.Shared -eq $true }
    if ($share) {
        Write-Host "   ✓ الطابعة مشتركة بنجاح!" -ForegroundColor Green
        Write-Host "   الحالة: $($share.PrinterStatus)" -ForegroundColor White
        return $true
    }
    else {
        Write-Host "   ✗ فشل التحقق من المشاركة" -ForegroundColor Red
        return $false
    }
}

# ========== Main Menu ==========
Write-Header

$printers = @(Get-LocalPrinters)
if ($printers.Count -eq 0) {
    Write-Host "لم يتم العثور على طابعات محلية!" -ForegroundColor Red
    Write-Host "تأكد من توصيل الطابعة وتثبيت التعريف." -ForegroundColor Yellow
    Read-Host "`nاضغط Enter للخروج"
    exit 1
}

Write-Host "الطابعات المتاحة:" -ForegroundColor White
Write-Host ""
for ($i = 0; $i -lt $printers.Count; $i++) {
    $p = $printers[$i]
    $status = if ($p.Shared) { "[مشتركة: $($p.ShareName)]" } else { "[غير مشتركة]" }
    Write-Host "  $($i + 1). $($p.Name) $status"
}
Write-Host ""

$selection = Read-Host "اختر رقم الطابعة"
$index = [int]$selection - 1
if ($index -lt 0 -or $index -ge $printers.Count) {
    Write-Host "اختيار غير صالح!" -ForegroundColor Red
    exit 1
}

$selectedPrinter = $printers[$index]
Write-Host "`nالطابعة المختارة: $($selectedPrinter.Name)" -ForegroundColor Cyan

# Share name
$defaultShare = ($selectedPrinter.Name -replace '[^a-zA-Z0-9]', '') -replace '\s', ''
$shareName = Read-Host "اسم المشاركة (Enter للافتراضي: $defaultShare)"
if ([string]::IsNullOrWhiteSpace($shareName)) { $shareName = $defaultShare }

# Share mode menu
Write-Host "`nنوع المشاركة:" -ForegroundColor White
Write-Host "  1. مشاركة أساسية (Basic) - شبكة محلية"
Write-Host "  2. مشاركة كاملة (Full) - جميع المستخدمين"
Write-Host "  3. مشاركة شركة/مجال (Domain/Workgroup)"
Write-Host ""
$modeSelection = Read-Host "اختر نوع المشاركة [1-3]"
$shareMode = switch ($modeSelection) {
    "2" { "full" }
    "3" { "domain" }
    default { "basic" }
}

Write-Host ""
Enable-NetworkSharing
Share-Printer -PrinterName $selectedPrinter.Name -ShareName $shareName -ShareMode $shareMode
Show-ConnectionInfo -ShareName $shareName
$success = Test-PrinterShare -ShareName $shareName

Write-Host "`n============================================" -ForegroundColor Cyan
if ($success) {
    Write-Host "   تم إعداد المشاركة بنجاح!" -ForegroundColor Green
    Write-Host "   شغّل السكربت على الحاسوب الآخر للاتصال." -ForegroundColor White
}
else {
    Write-Host "   حدثت مشكلة. راجع الإعدادات يدوياً." -ForegroundColor Red
}
Write-Host "============================================" -ForegroundColor Cyan
Read-Host "`nاضغط Enter للخروج"
