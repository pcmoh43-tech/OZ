#Requires -RunAsAdministrator
# Client PC - connect, install printer, test print (fixed for error 0x8007007b)

$ErrorActionPreference = "Continue"
$Port = 9876

function Write-Status([string]$Msg, [string]$Color = "White") {
    Write-Host $Msg -ForegroundColor $Color
}

function Enable-ClientNetworkAccess {
    Write-Status "  Enabling network printer access..." "Yellow"
    Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue
    netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes | Out-Null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" /v AllowInsecureGuestAuth /t REG_DWORD /d 1 /f 2>$null | Out-Null
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" /v RequireSecuritySignature /t REG_DWORD /d 0 /f 2>$null | Out-Null
    Write-Status "  OK" "Green"
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

function Get-NetworkShares {
    param([string]$HostIP)
    Write-Status "  Checking shares on \\$HostIP ..." "Yellow"
    $output = cmd /c "net view \\$HostIP 2>&1"
    $shares = @()
    foreach ($line in ($output -split "`n")) {
        if ($line -match '^\s+(\S+)') {
            $name = $Matches[1]
            if ($name -notin @('Share', 'name', '----', 'The', 'System', 'IPC$')) {
                $shares += $name
            }
        }
    }
    return $shares | Where-Object { $_ -and $_ -ne 'Share' -and $_ -notmatch '^-+$' } | Select-Object -Unique
}

function Connect-Share {
    param(
        [string]$UncPath,
        [string]$Username = "",
        [string]$Password = ""
    )
    cmd /c "net use `"$UncPath`" /delete /y" 2>$null | Out-Null
    if ($Username) {
        $result = cmd /c "net use `"$UncPath`" /user:$Username $Password 2>&1"
    }
    else {
        $result = cmd /c "net use `"$UncPath`" 2>&1"
    }
    return ($LASTEXITCODE -eq 0) -or ($result -match "completed successfully|Command completed")
}

function Install-SharedPrinter {
    param(
        [string]$HostIP,
        [string]$ShareName,
        [string]$Hostname = ""
    )

    $candidates = @()
    if ($HostIP -and $ShareName) { $candidates += "\\$HostIP\$ShareName" }
    if ($Hostname -and $ShareName) { $candidates += "\\$Hostname\$ShareName" }
    $candidates = $candidates | Select-Object -Unique

    foreach ($path in $candidates) {
        Write-Status "  Trying path: $path" "Yellow"

        # Step 1: connect share with net use
        if (-not (Connect-Share -UncPath $path)) {
            Write-Status "  Share login failed, trying with credentials..." "DarkYellow"
            $user = Read-Host "  Host username (e.g. OZ\username) or Enter to skip"
            if ($user) {
                $pass = Read-Host "  Password" -AsSecureString
                $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass)
                $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
                Connect-Share -UncPath $path -Username $user -Password $plain | Out-Null
            }
        }

        # Step 2: rundll32 (most reliable on Windows 10/11)
        Write-Status "  Method 1: printui..." "DarkGray"
        $proc = Start-Process "rundll32.exe" -ArgumentList "printui.dll,PrintUIEntry /in /n `"$path`"" -Wait -PassThru -NoNewWindow
        Start-Sleep -Seconds 2
        $installed = Get-Printer -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -like "*$ShareName*" -or $_.PortName -like "*$HostIP*" -or $_.Name -like "*$path*"
        }
        if ($installed) {
            Write-Status "  OK - Installed: $($installed[0].Name)" "Green"
            return $true
        }

        # Step 3: Add-Printer
        Write-Status "  Method 2: Add-Printer..." "DarkGray"
        try {
            Add-Printer -ConnectionName $path -ErrorAction Stop
            Write-Status "  OK - Add-Printer worked!" "Green"
            return $true
        }
        catch {
            Write-Status "  Add-Printer failed: $($_.Exception.Message)" "DarkYellow"
        }

        # Step 4: WMI
        Write-Status "  Method 3: WMI..." "DarkGray"
        try {
            ([WMIClass]"Win32_Printer").AddPrinterConnection($path) | Out-Null
            Start-Sleep -Seconds 2
            $installed = Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$ShareName*" }
            if ($installed) {
                Write-Status "  OK - WMI worked!" "Green"
                return $true
            }
        }
        catch {
            Write-Status "  WMI failed: $($_.Exception.Message)" "DarkYellow"
        }
    }

    return $false
}

function Send-TestPrint {
    param([string]$ShareName)
    Write-Status "  Sending test page..." "Yellow"
    $printer = Get-Printer -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "*$ShareName*" } |
        Select-Object -First 1
    if (-not $printer) {
        $printer = Get-Printer -ErrorAction SilentlyContinue | Select-Object -Last 1
    }
    if (-not $printer) {
        Write-Status "  No printer found to test!" "Red"
        return $false
    }
    Set-Printer -Name $printer.Name -Default
    $testFile = Join-Path $env:TEMP "r4-test-print.txt"
    "Printer Test - $(Get-Date) - $($printer.Name)" | Set-Content $testFile -Encoding ASCII
    Start-Process -FilePath $testFile -Verb Print -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Status "  OK - Test sent to: $($printer.Name)" "Green"
    return $true
}

# ========== MAIN ==========
Clear-Host
Write-Status "============================================" "Cyan"
Write-Status "   CLIENT - Connect Printer (Fixed)" "Cyan"
Write-Status "============================================" "Cyan"
Write-Host ""

Enable-ClientNetworkAccess

$hostIp    = $null
$shareName = $null
$hostname  = $null
$configPath = Join-Path $PSScriptRoot "host-config.json"

if (Test-Path $configPath) {
    $saved = Get-Content $configPath -Raw | ConvertFrom-Json
    Write-Status "Config: IP=$($saved.ip) Share=$($saved.shareName)" "Green"
    if ((Read-Host "Use this? [Y/n]") -notmatch "^[Nn]") {
        $hostIp    = $saved.ip
        $shareName = $saved.shareName
        $hostname  = $saved.hostname
    }
}

if (-not $hostIp) {
    $hostIp = Read-Host "Enter Host IP (PC with printer, NOT router)"
}

if (-not (Test-Connection $hostIp -Count 2 -Quiet)) {
    Write-Status "Cannot ping $hostIp - check WiFi network!" "Red"
    Read-Host "Press Enter"
    exit 1
}

Write-Status "[1/4] Reading shares from Host..." "Yellow"
$shares = Get-NetworkShares -HostIP $hostIp

if ($shares.Count -gt 0) {
    Write-Status "  Shares found:" "Green"
    for ($i = 0; $i -lt $shares.Count; $i++) {
        Write-Host "    $($i + 1). $($shares[$i])"
    }
    if (-not $shareName) {
        $sel = Read-Host "Select share number"
        $shareName = $shares[[int]$sel - 1]
    }
}
else {
    Write-Status "  Could not list shares (firewall or wrong IP)" "Yellow"
    Write-Status "  TIP: Make sure IP is the PC not the router (.1)" "Yellow"
    if (-not $shareName) {
        $shareName = Read-Host "Enter share name manually (e.g. CanonGenericPlusUFRII)"
    }
}

Write-Host ""
Write-Status "Target: \\$hostIp\$shareName" "Cyan"
Write-Status "[2/4] Installing printer..." "Yellow"

$ok = Install-SharedPrinter -HostIP $hostIp -ShareName $shareName -Hostname $hostname

if (-not $ok) {
    Write-Host ""
    Write-Status "FAILED! Try these fixes:" "Red"
    Write-Status "  1. Run RUN-HOST.bat again on PC 1" "White"
    Write-Status "  2. Use correct IP (not router .1)" "White"
    Write-Status "  3. Both PCs on same WiFi" "White"
    Write-Status "  4. Manual add: Settings > Printers > Add > \\$hostIp\$shareName" "White"
    Read-Host "Press Enter"
    exit 1
}

try { Send-HostRequest -HostIP $hostIp -Command "CONNECTED" | Out-Null } catch {}

Write-Status "[3/4] Test print..." "Yellow"
Send-TestPrint -ShareName $shareName | Out-Null

try { Send-HostRequest -HostIP $hostIp -Command "TEST_PRINT" | Out-Null } catch {}

Write-Host ""
Write-Status "============================================" "Green"
Write-Status "   SUCCESS! Printer installed" "Green"
Write-Status "   \\$hostIp\$shareName" "White"
Write-Status "============================================" "Green"
Read-Host "Press Enter"
