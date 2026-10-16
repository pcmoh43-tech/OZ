#Requires -RunAsAdministrator
# Host PC - USB printer - waits for Client PC to connect
# Usage: powershell -ExecutionPolicy Bypass -File host-wait.ps1

$ErrorActionPreference = "Stop"
$Port = 9876

function Write-Status([string]$Msg, [string]$Color = "White") {
    Write-Host $Msg -ForegroundColor $Color
}

function Get-MyIP {
    $ip = (Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.*" } |
        Select-Object -First 1).IPAddress
    return $ip
}

function Enable-Sharing {
    Write-Status "[1/3] Enabling network sharing..." "Yellow"
    Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue
    netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes | Out-Null
    New-NetFirewallRule -DisplayName "R4-Printer-Wait" -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow -ErrorAction SilentlyContinue | Out-Null
    Write-Status "      OK - Network ready" "Green"
}

function Get-UsbPrinters {
    Get-CimInstance Win32_Printer | Where-Object {
        $_.Local -eq $true -and (
            $_.PortName -match "USB|WSD" -or
            $_.Name -notmatch "OneNote|PDF|XPS|Fax|AnyDesk"
        )
    }
}

function Start-WaitServer {
    param(
        [string]$ShareName,
        [string]$PrinterName,
        [string]$IP
    )

    $info = @{
        ip          = $IP
        hostname    = $env:COMPUTERNAME
        shareName   = $ShareName
        printerName = $PrinterName
        path        = "\\$IP\$ShareName"
    } | ConvertTo-Json -Compress

    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
    $listener.Start()

    Write-Host ""
    Write-Status "============================================" "Cyan"
    Write-Status "   HOST READY - Waiting for Client PC..." "Green"
    Write-Status "============================================" "Cyan"
    Write-Host ""
    Write-Status "  IP Address : $IP" "White"
    Write-Status "  Share Name : $ShareName" "White"
    Write-Status "  Path       : \\$IP\$ShareName" "Green"
    Write-Status "  Port       : $Port" "White"
    Write-Host ""
    Write-Status "  >> Run CLIENT script on the other PC <<" "Yellow"
    Write-Status "  Press Ctrl+C to stop waiting" "DarkGray"
    Write-Host ""

    $connected = $false
    $testDone  = $false

    while ($true) {
        if ($listener.Pending()) {
            $client = $listener.AcceptTcpClient()
            $stream = $client.GetStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $writer = New-Object System.IO.StreamWriter($stream)
            $writer.AutoFlush = $true

            $request = $reader.ReadLine()
            $remote  = $client.Client.RemoteEndPoint.Address.ToString()

            switch ($request) {
                "DISCOVER" {
                    Write-Status "[$(Get-Date -Format 'HH:mm:ss')] Client $remote searching..." "Cyan"
                    $writer.WriteLine($info)
                }
                "INSTALL" {
                    Write-Status "[$(Get-Date -Format 'HH:mm:ss')] Client $remote installing printer..." "Yellow"
                    $writer.WriteLine("OK")
                }
                "CONNECTED" {
                    Write-Status "[$(Get-Date -Format 'HH:mm:ss')] Client $remote connected!" "Green"
                    $connected = $true
                    $writer.WriteLine("OK")
                }
                "TEST_PRINT" {
                    Write-Status "[$(Get-Date -Format 'HH:mm:ss')] Client $remote sent test print!" "Green"
                    $testDone = $true
                    $writer.WriteLine("OK")
                }
                "PING" {
                    $writer.WriteLine("PONG|$info")
                }
                default {
                    $writer.WriteLine("UNKNOWN")
                }
            }

            $client.Close()

            if ($testDone) {
                Write-Host ""
                Write-Status "============================================" "Green"
                Write-Status "   SUCCESS! Client installed and test printed" "Green"
                Write-Status "============================================" "Green"
                Read-Host "`nPress Enter to exit"
                break
            }
        }
        Start-Sleep -Milliseconds 300
    }

    $listener.Stop()
}

# ========== MAIN ==========
Clear-Host
Write-Status "============================================" "Cyan"
Write-Status "   HOST - USB Printer (Wait for Client)" "Cyan"
Write-Status "============================================" "Cyan"
Write-Host ""

$printers = @(Get-UsbPrinters)
if ($printers.Count -eq 0) {
    Write-Status "No USB printers found! Connect printer and try again." "Red"
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Status "Available printers:" "White"
for ($i = 0; $i -lt $printers.Count; $i++) {
    $port = $printers[$i].PortName
    Write-Host "  $($i + 1). $($printers[$i].Name)  [$port]"
}
Write-Host ""

$sel = [int](Read-Host "Select printer number") - 1
if ($sel -lt 0 -or $sel -ge $printers.Count) {
    Write-Status "Invalid selection!" "Red"
    exit 1
}

$printer   = $printers[$sel]
$shareName = ($printer.Name -replace '[^a-zA-Z0-9]', '')
$custom    = Read-Host "Share name (Enter = $shareName)"
if ($custom) { $shareName = ($custom -replace '[^a-zA-Z0-9]', '') }

Write-Host ""
Enable-Sharing

Write-Status "[2/3] Sharing printer: $($printer.Name)" "Yellow"
Set-Printer -Name $printer.Name -Shared $true -ShareName $shareName
Write-Status "      OK - Printer shared as: $shareName" "Green"

$ip = Get-MyIP
$configPath = Join-Path $PSScriptRoot "host-config.json"
@{ ip = $ip; shareName = $shareName; printerName = $printer.Name; port = $Port } |
    ConvertTo-Json | Set-Content $configPath -Encoding UTF8

Write-Status "[3/3] Starting wait server..." "Yellow"
Start-WaitServer -ShareName $shareName -PrinterName $printer.Name -IP $ip
