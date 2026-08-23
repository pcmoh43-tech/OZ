#Requires -RunAsAdministrator
# Wrapper - runs fixed client-connect.ps1
$script = Join-Path $PSScriptRoot "client-connect.ps1"
if (Test-Path $script) {
    & $script
}
else {
    Write-Host "client-connect.ps1 not found! Run INSTALL.bat first." -ForegroundColor Red
    Read-Host "Press Enter"
}
