# ============================================================
#  Copy ALL and paste in PowerShell (Admin) on your Windows PC
#  Creates/updates Desktop\r4 with Host + Client scripts
# ============================================================

$dest = "$env:USERPROFILE\Desktop\r4"
New-Item -ItemType Directory -Force -Path $dest | Out-Null

$base = "https://raw.githubusercontent.com/pcmoh43-tech/OZ/cursor/printer-sharing-scripts-3595/r4"
$files = @("host-wait.ps1", "client-connect.ps1", "RUN-HOST.bat", "RUN-CLIENT.bat")

$downloaded = $false
foreach ($f in $files) {
    try {
        Invoke-WebRequest "$base/$f" -OutFile "$dest\$f" -UseBasicParsing -TimeoutSec 10
        Write-Host "Downloaded: $f" -ForegroundColor Green
        $downloaded = $true
    }
    catch {
        Write-Host "Could not download $f (will use embedded copy)" -ForegroundColor Yellow
    }
}

if (-not $downloaded) {
    Write-Host "Using embedded scripts..." -ForegroundColor Yellow
    Copy-Item -Path "$PSScriptRoot\*" -Destination $dest -Include "*.ps1","*.bat" -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Folder ready: $dest" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  PC 1 (USB printer):  RUN-HOST.bat" -ForegroundColor Yellow
Write-Host "  PC 2 (other PC):     RUN-CLIENT.bat" -ForegroundColor Yellow
Write-Host ""
explorer $dest
