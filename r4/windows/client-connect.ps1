#Requires -RunAsAdministrator
# Client PC - finds Host, installs printer, test print
# Usage: powershell -ExecutionPolicy Bypass -File client-connect.ps1

$ErrorActionPreference = "Stop"
$Port = 9876

function Write-Status([string]$Msg, [string]$Color = "White") {
    Write-Host $Msg -ForegroundColor $Color
}

function Send-HostRequest {
    param([string]$HostIP, [string]$Command)

    $client = New-Object System.Net.Sockets.TcpClient
    $client.ReceiveTimeout = 3000
    $client.SendTimeout    = 3000
    $client.Connect($HostIP, $Port)

    $stream = $client.GetStream()
    $writer = New-Object System.IO.StreamWriter($stream)
    $reader = New-Object System.IO.StreamReader($stream)
    $writer.AutoFlush = $true

    $writer.WriteLine($Command)
    $response = $reader.ReadLine()

    $client.Close()
    return $response
}

function Find-HostOnNetwork {
    Write-Status "  Scanning network for Host PC..." "Yellow"

    $myIp = (Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.*" } |
        Select-Object -First 1).IPAddress

    if (-not $myIp) { return $null }

    $parts = $myIp.Split(".")
    $subnet = "$($parts[0]).$($parts[1]).$($parts[2])"

    Write-Status "  Subnet: $subnet.0/24" "DarkGray"

    for ($i = 1; $i -le 254; $i++) {
        $target = "$subnet.$i"
        Write-Host "`r  Scanning $target...  " -NoNewline
        try {
            $resp = Send-HostRequest -HostIP $target -Command "PING"
            if ($resp -match "PONG\|") {
                Write-Host ""
                Write-Status "  Found Host at: $target" "Green"
                return ($resp -replace "^PONG\|", "") | ConvertFrom-Json
            }
        }
        catch { }
    }
    Write-Host ""
    return $null
}

function Install-SharedPrinter {
    param([string]$Path, [string]$ShareName)

    Write-Status "  Installing: $Path" "Yellow"

    $existing = Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$ShareName*" }
    foreach ($p in $existing) {
        Remove-Printer -Name $p.Name -ErrorAction SilentlyContinue
    }

    try {
        Add-Printer -ConnectionName $Path -ErrorAction Stop
        Write-Status "  OK - Printer installed!" "Green"
        return $true
    }
    catch {
        $result = Start-Process "rundll32.exe" -ArgumentList "printui.dll,PrintUIEntry /in /n `"$Path`"" -Wait -PassThru -NoNewWindow
        if ($result.ExitCode -eq 0) {
            Write-Status "  OK - Printer installed (alt method)!" "Green"
            return $true
        }
        Write-Status "  FAILED: $($_.Exception.Message)" "Red"
        return $false
    }
}

function Send-TestPrint {
    param([string]$ShareName)

    Write-Status "  Sending test page..." "Yellow"

    $printer = Get-Printer -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "*$ShareName*" -or $_.ShareName -eq $ShareName } |
        Select-Object -First 1

    if (-not $printer) {
        $printer = Get-Printer -ErrorAction SilentlyContinue | Select-Object -Last 1
    }

    if (-not $printer) {
        Write-Status "  Could not find installed printer!" "Red"
        return $false
    }

    Set-Printer -Name $printer.Name -Default
    Write-Status "  Set as default: $($printer.Name)" "Green"

    $testFile = Join-Path $env:TEMP "r4-test-print.txt"
    @"
========================================
       PRINTER TEST PAGE - R4
========================================
Date   : $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Client : $env:COMPUTERNAME
Printer: $($printer.Name)
========================================
If you see this, printer works!
========================================
"@ | Set-Content $testFile -Encoding UTF8

    Start-Process -FilePath $testFile -Verb Print -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Status "  OK - Test page sent to printer!" "Green"
    return $true
}

# ========== MAIN ==========
Clear-Host
Write-Status "============================================" "Cyan"
Write-Status "   CLIENT - Connect & Install Printer" "Cyan"
Write-Status "============================================" "Cyan"
Write-Host ""

$hostInfo = $null
$configPath = Join-Path $PSScriptRoot "host-config.json"

# Try saved config
if (Test-Path $configPath) {
    $saved = Get-Content $configPath | ConvertFrom-Json
    Write-Status "Saved config found: IP=$($saved.ip) Share=$($saved.shareName)" "Green"
    $use = Read-Host "Use saved config? [Y/n]"
    if ($use -notmatch "^[Nn]") {
        $hostInfo = $saved
    }
}

# Try auto-discover
if (-not $hostInfo) {
    Write-Status "[1/4] Searching for Host PC on network..." "Yellow"
    Write-Status "  (Make sure Host script is running and waiting)" "DarkGray"
    Write-Host ""

    $discover = Read-Host "Auto-scan network? [Y/n]"
    if ($discover -notmatch "^[Nn]") {
        $hostInfo = Find-HostOnNetwork
    }
}

# Manual IP
if (-not $hostInfo) {
    Write-Host ""
    $manualIp = Read-Host "Enter Host IP address (e.g. 192.168.41.1)"
    try {
        $resp = Send-HostRequest -HostIP $manualIp -Command "DISCOVER"
        $hostInfo = $resp | ConvertFrom-Json
        Write-Status "  Connected to Host: $($hostInfo.hostname)" "Green"
    }
    catch {
        Write-Status "  Cannot reach Host at $manualIp !" "Red"
        Write-Status "  Make sure Host script is running first." "Yellow"
        Read-Host "Press Enter to exit"
        exit 1
    }
}

Write-Host ""
Write-Status "Host found:" "Green"
Write-Status "  IP   : $($hostInfo.ip)" "White"
Write-Status "  Share: $($hostInfo.shareName)" "White"
Write-Status "  Path : $($hostInfo.path)" "Green"
Write-Host ""

# Notify host - installing
Write-Status "[2/4] Notifying Host..." "Yellow"
try { Send-HostRequest -HostIP $hostInfo.ip -Command "INSTALL" | Out-Null } catch {}
Write-Status "      OK" "Green"

# Install printer
Write-Status "[3/4] Installing printer on this PC..." "Yellow"
$path = "\\$($hostInfo.ip)\$($hostInfo.shareName)"
$ok = Install-SharedPrinter -Path $path -ShareName $hostInfo.shareName

if (-not $ok) {
    Read-Host "Press Enter to exit"
    exit 1
}

# Notify connected
try { Send-HostRequest -HostIP $hostInfo.ip -Command "CONNECTED" | Out-Null } catch {}

# Test print
Write-Status "[4/4] Test print..." "Yellow"
$testOk = Send-TestPrint -ShareName $hostInfo.shareName

if ($testOk) {
    try { Send-HostRequest -HostIP $hostInfo.ip -Command "TEST_PRINT" | Out-Null } catch {}
}

# Save client config
@{
    hostIp      = $hostInfo.ip
    shareName   = $hostInfo.shareName
    connectedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
} | ConvertTo-Json | Set-Content (Join-Path $PSScriptRoot "client-config.json") -Encoding UTF8

Write-Host ""
Write-Status "============================================" "Green"
Write-Status "   DONE! Printer ready on this PC" "Green"
Write-Status "   Path: $path" "White"
Write-Status "============================================" "Green"
Read-Host "`nPress Enter to exit"
