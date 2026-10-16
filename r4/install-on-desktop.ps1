# Install ALL missing files into Desktop\r4
# Run: powershell -ExecutionPolicy Bypass -File install-on-desktop.ps1

$dest = if ($PSScriptRoot -match "Desktop\\r4") { $PSScriptRoot } else { "$env:USERPROFILE\Desktop\r4" }
New-Item -ItemType Directory -Force -Path $dest | Out-Null

$base = "https://raw.githubusercontent.com/pcmoh43-tech/OZ/cursor/printer-sharing-scripts-3595/r4"
$files = @(
    "host-wait.ps1",
    "client-connect.ps1",
    "host-share-printer.ps1",
    "client-connect-printer.ps1",
    "RUN-HOST.bat",
    "RUN-CLIENT.bat",
    "START.bat"
)

Write-Host ""
Write-Host "Installing to: $dest" -ForegroundColor Cyan
Write-Host ""

foreach ($f in $files) {
    $out = Join-Path $dest $f
    try {
        Invoke-WebRequest "$base/$f" -OutFile $out -UseBasicParsing -TimeoutSec 15
        Write-Host "  OK  $f" -ForegroundColor Green
    }
    catch {
        Write-Host "  FAIL $f - using local copy" -ForegroundColor Yellow
        $local = Join-Path $PSScriptRoot $f
        if (Test-Path $local) { Copy-Item $local $out -Force; Write-Host "  OK  $f (local)" -ForegroundColor Green }
    }
}

# Ensure bat launchers exist even if download failed
if (-not (Test-Path "$dest\RUN-HOST.bat")) {
    @'
@echo off
title HOST - Wait for Client
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0host-wait.ps1"
pause
'@ | Set-Content "$dest\RUN-HOST.bat" -Encoding ASCII
    Write-Host "  OK  RUN-HOST.bat (created)" -ForegroundColor Green
}

if (-not (Test-Path "$dest\RUN-CLIENT.bat")) {
    @'
@echo off
title CLIENT - Connect Printer
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0client-connect.ps1"
pause
'@ | Set-Content "$dest\RUN-CLIENT.bat" -Encoding ASCII
    Write-Host "  OK  RUN-CLIENT.bat (created)" -ForegroundColor Green
}

if (-not (Test-Path "$dest\START.bat")) {
    @'
@echo off
echo [1] PC1 HOST   [2] PC2 CLIENT   [3] Exit
set /p c="Choose: "
if "%c%"=="1" call "%~dp0RUN-HOST.bat"
if "%c%"=="2" call "%~dp0RUN-CLIENT.bat"
'@ | Set-Content "$dest\START.bat" -Encoding ASCII
    Write-Host "  OK  START.bat (created)" -ForegroundColor Green
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  All files installed!" -ForegroundColor Green
Write-Host "  Folder: $dest" -ForegroundColor White
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  PC 1 (USB printer):  RUN-HOST.bat" -ForegroundColor Yellow
Write-Host "  PC 2 (other PC):     RUN-CLIENT.bat" -ForegroundColor Yellow
Write-Host ""

Get-ChildItem $dest | Format-Table Name, Length, LastWriteTime
explorer $dest
