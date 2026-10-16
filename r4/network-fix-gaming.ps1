#Requires -RunAsAdministrator
# Network diagnostic + gaming fix for Windows
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File network-fix-gaming.ps1

$ErrorActionPreference = "Continue"
$ReportDir = Join-Path $env:USERPROFILE "Desktop\network-report"
New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
$ReportFile = Join-Path $ReportDir ("report-{0}.txt" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
$Issues = New-Object System.Collections.Generic.List[string]
$Fixes  = New-Object System.Collections.Generic.List[string]

function Write-Sec([string]$Title) {
    $line = "`r`n========== $Title ==========`r`n"
    Write-Host $line -ForegroundColor Cyan
    Add-Content -Path $ReportFile -Value $line
}

function Out-Both([string]$Text, [string]$Color = "White") {
    Write-Host $Text -ForegroundColor $Color
    Add-Content -Path $ReportFile -Value $Text
}

function Add-Issue([string]$Text) { $Issues.Add($Text) | Out-Null; Out-Both "[ISSUE] $Text" "Red" }
function Add-Fix([string]$Text)   { $Fixes.Add($Text)  | Out-Null; Out-Both "[FIX]   $Text" "Yellow" }
function Add-Ok([string]$Text)    { Out-Both "[OK]    $Text" "Green" }

Clear-Host
Out-Both "Network Diagnostic for Gaming - $(Get-Date)" "Cyan"
Out-Both "Report will be saved to: $ReportFile" "DarkGray"

# ---------- 1) Adapter & WiFi signal ----------
Write-Sec "1) Network Adapter & WiFi Signal"
$wifi = $null
try {
    $wifiOut = netsh wlan show interfaces 2>$null
    if ($wifiOut) {
        Add-Content $ReportFile ($wifiOut -join "`r`n")
        $ssid   = ($wifiOut | Select-String '^\s*SSID\s*:\s*(.+)$' | Select-Object -First 1).Matches.Groups[1].Value.Trim()
        $signal = ($wifiOut | Select-String '^\s*Signal\s*:\s*(\d+)%' | Select-Object -First 1).Matches.Groups[1].Value
        $radio  = ($wifiOut | Select-String '^\s*Radio type\s*:\s*(.+)$' | Select-Object -First 1).Matches.Groups[1].Value.Trim()
        $channel= ($wifiOut | Select-String '^\s*Channel\s*:\s*(\d+)' | Select-Object -First 1).Matches.Groups[1].Value
        $rx     = ($wifiOut | Select-String '^\s*Receive rate \(Mbps\)\s*:\s*(.+)$' | Select-Object -First 1).Matches.Groups[1].Value.Trim()
        $tx     = ($wifiOut | Select-String '^\s*Transmit rate \(Mbps\)\s*:\s*(.+)$' | Select-Object -First 1).Matches.Groups[1].Value.Trim()
        $band   = ($wifiOut | Select-String '^\s*Band\s*:\s*(.+)$' | Select-Object -First 1).Matches.Groups[1].Value

        Out-Both "SSID: $ssid | Signal: $signal% | Radio: $radio | Channel: $channel | RX/TX: $rx/$tx Mbps | Band: $band"

        if ($signal) {
            $sigNum = [int]$signal
            if ($sigNum -lt 50) {
                Add-Issue "WiFi signal is weak ($signal%). Gaming will lag."
                Add-Fix "Move closer to router, use 5GHz/6GHz, or use Ethernet cable."
            }
            elseif ($sigNum -lt 70) {
                Add-Issue "WiFi signal is average ($signal%)."
                Add-Fix "Prefer 5GHz band and reduce walls between PC and router."
            }
            else { Add-Ok "WiFi signal looks good ($signal%)." }
        }

        if ($radio -match '802\.11n|802\.11g|802\.11b') {
            Add-Issue "Old WiFi radio type ($radio)."
            Add-Fix "Connect to 5GHz / WiFi 5 or WiFi 6 SSID if available."
        }

        if ($rx -and ([double]$rx -lt 50)) {
            Add-Issue "WiFi receive rate is low ($rx Mbps)."
            Add-Fix "Change WiFi channel / move closer / use Ethernet."
        }
        $wifi = $true
    }
    else {
        Out-Both "No WiFi interface found (maybe Ethernet only)." "DarkYellow"
    }
}
catch {
    Out-Both "WiFi check failed: $($_.Exception.Message)" "DarkYellow"
}

# ---------- 2) IP / Gateway / DNS ----------
Write-Sec "2) IP, Gateway, DNS"
$cfg = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } | Select-Object -First 1
if (-not $cfg) {
    Add-Issue "No active gateway found."
    Add-Fix "Reconnect WiFi/Ethernet or restart router."
}
else {
    $ip = ($cfg.IPv4Address | Select-Object -First 1).IPAddress
    $gw = ($cfg.IPv4DefaultGateway | Select-Object -First 1).NextHop
    $dns = ($cfg.DNSServer | Where-Object { $_.AddressFamily -eq 2 } | ForEach-Object { $_.ServerAddresses }) -join ', '
    Out-Both "IP: $ip | Gateway: $gw | DNS: $dns | Interface: $($cfg.InterfaceAlias)"

    if ($ip -like '169.254.*') {
        Add-Issue "APIPA address ($ip) - no DHCP from router."
        Add-Fix "Restart router and run: ipconfig /release & ipconfig /renew"
    }
    else { Add-Ok "Local IP looks valid." }

    if ($dns -match '198\.18\.|0\.0\.0\.0') {
        Add-Issue "Unusual DNS detected ($dns)."
        Add-Fix "Set DNS to 1.1.1.1 and 8.8.8.8"
    }
}

# ---------- 3) Ping gateway / internet / gaming DNS ----------
Write-Sec "3) Latency & Packet Loss"
function Test-Target([string]$Name, [string]$Target) {
    try {
        $r = Test-Connection -ComputerName $Target -Count 8 -ErrorAction Stop
        $times = $r | ForEach-Object { $_.ResponseTime }
        $avg = [math]::Round(($times | Measure-Object -Average).Average, 1)
        $max = ($times | Measure-Object -Maximum).Maximum
        $loss = [math]::Round(100 - (($r.Count / 8.0) * 100), 1)
        # Test-Connection may return fewer replies on loss; compute from attempts
        $sent = 8
        $recv = @($r).Count
        $lossPct = [math]::Round((($sent - $recv) / $sent) * 100, 1)
        Out-Both ("{0,-18} {1,-16} avg={2}ms max={3}ms loss={4}%" -f $Name, $Target, $avg, $max, $lossPct)
        return @{ Name=$Name; Target=$Target; Avg=$avg; Max=$max; Loss=$lossPct }
    }
    catch {
        Out-Both ("{0,-18} {1,-16} FAILED" -f $Name, $Target) "Red"
        return @{ Name=$Name; Target=$Target; Avg=9999; Max=9999; Loss=100 }
    }
}

$targets = @()
if ($cfg -and $cfg.IPv4DefaultGateway) {
    $targets += Test-Target "Router/Gateway" (($cfg.IPv4DefaultGateway | Select-Object -First 1).NextHop)
}
$targets += Test-Target "Cloudflare" "1.1.1.1"
$targets += Test-Target "Google DNS" "8.8.8.8"
$targets += Test-Target "Google.com" "google.com"

$gwResult = $targets | Where-Object { $_.Name -eq 'Router/Gateway' } | Select-Object -First 1
$inetResult = $targets | Where-Object { $_.Name -eq 'Cloudflare' } | Select-Object -First 1

if ($gwResult -and $gwResult.Avg -gt 20) {
    Add-Issue "High latency to router ($($gwResult.Avg) ms). WiFi/local network problem."
    Add-Fix "Use Ethernet, change WiFi channel, reduce interference (microwave/cordless phones)."
}
elseif ($gwResult -and $gwResult.Avg -le 10) { Add-Ok "Router latency is good ($($gwResult.Avg) ms)." }

if ($gwResult -and $gwResult.Loss -gt 1) {
    Add-Issue "Packet loss to router ($($gwResult.Loss)%)."
    Add-Fix "WiFi interference or bad cable. Prefer wired connection for gaming."
}

if ($inetResult -and $inetResult.Avg -gt 80) {
    Add-Issue "High internet latency ($($inetResult.Avg) ms)."
    Add-Fix "ISP congestion or long route. Avoid VPN; restart modem/router."
}
elseif ($inetResult -and $inetResult.Avg -le 40) { Add-Ok "Internet latency OK ($($inetResult.Avg) ms)." }

if ($inetResult -and $inetResult.Loss -gt 1) {
    Add-Issue "Internet packet loss ($($inetResult.Loss)%)."
    Add-Fix "Contact ISP if persists after router reboot."
}

# ---------- 4) Bandwidth hogs / servers ----------
Write-Sec "4) Programs Using Network (possible bandwidth hogs)"
try {
    $conns = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
        Where-Object { $_.RemoteAddress -notmatch '^(127\.|::1|0\.0\.0\.0)' }
    $byPid = $conns | Group-Object OwningProcess | Sort-Object Count -Descending | Select-Object -First 15
    foreach ($g in $byPid) {
        $p = Get-Process -Id $g.Name -ErrorAction SilentlyContinue
        $name = if ($p) { $p.ProcessName } else { "PID $($g.Name)" }
        $path = if ($p) { try { $p.Path } catch { "" } } else { "" }
        Out-Both ("{0,4} conns | {1,-25} | {2}" -f $g.Count, $name, $path)
    }

    $suspectNames = @(
        'Steam','EpicGamesLauncher','Discord','OneDrive','Dropbox','GoogleDriveFS',
        'BitTorrent','uTorrent','qBittorrent','Transmission','Skype','Teams','Zoom',
        'AnyDesk','TeamViewer','Chrome','msedge','firefox','GameBar','XboxApp',
        'DeliveryOptimization','MoUsoCoreWorker','WUDFHost','PrtEasyServer','ShaPrint'
    )
    $runningSuspects = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $suspectNames -contains $_.ProcessName -or $_.ProcessName -match 'update|download|torrent|sync'
    } | Select-Object ProcessName, Id, CPU, WorkingSet -Unique

    if ($runningSuspects) {
        Out-Both "`nPossible bandwidth/CPU consumers:" "Yellow"
        $runningSuspects | ForEach-Object {
            Out-Both (" - {0} (PID {1})" -f $_.ProcessName, $_.Id)
        }
        Add-Issue "Background apps that may steal bandwidth are running."
        Add-Fix "Close torrents, cloud sync, Steam downloads, Discord overlays while gaming."
    }
    else { Add-Ok "No common bandwidth hogs detected by name." }
}
catch {
    Out-Both "Could not list connections: $($_.Exception.Message)" "DarkYellow"
}

# ---------- 5) Listening servers on this PC ----------
Write-Sec "5) Servers Listening on This PC"
try {
    $listeners = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Sort-Object LocalPort |
        Select-Object -First 40 LocalAddress, LocalPort, OwningProcess
    foreach ($l in $listeners) {
        $p = Get-Process -Id $l.OwningProcess -ErrorAction SilentlyContinue
        Out-Both ("LISTEN {0}:{1,-5} <- {2}" -f $l.LocalAddress, $l.LocalPort, $(if ($p) { $p.ProcessName } else { $l.OwningProcess }))
    }
    $gamePorts = $listeners | Where-Object { $_.LocalPort -in 27015,27036,3074,3478,4380,6112,7777,27000,25565,9876,9877,9100 }
    if ($gamePorts) {
        Out-Both "Game/share related listeners found (OK if you host/share)." "DarkYellow"
    }
}
catch {
    Out-Both "Listener scan failed: $($_.Exception.Message)" "DarkYellow"
}

# ---------- 6) Windows update / Delivery Optimization ----------
Write-Sec "6) Windows Update / Delivery Optimization"
try {
    $bits = Get-BitsTransfer -AllUsers -ErrorAction SilentlyContinue |
        Where-Object { $_.JobState -match 'Transferring|Connecting|Queued' }
    if ($bits) {
        Add-Issue "BITS downloads active ($($bits.Count) jobs) - can kill gaming bandwidth."
        Add-Fix "Pause Windows Update / Delivery Optimization while gaming."
        $bits | ForEach-Object { Out-Both (" BITS: {0} [{1}]" -f $_.DisplayName, $_.JobState) }
    }
    else { Add-Ok "No active BITS transfers." }

    $doSvc = Get-Service DoSvc -ErrorAction SilentlyContinue
    if ($doSvc -and $doSvc.Status -eq 'Running') {
        Out-Both "Delivery Optimization service is Running." "DarkYellow"
    }
}
catch {
    Out-Both "Update check skipped: $($_.Exception.Message)" "DarkYellow"
}

# ---------- 7) Power / NIC optimizations ----------
Write-Sec "7) Apply Safe Gaming Network Fixes"
$apply = Read-Host "Apply safe fixes now? (flush DNS, reset Winsock, set DNS 1.1.1.1, disable Delivery Optimization download from PCs) [Y/n]"
if ($apply -notmatch '^[Nn]') {
    try {
        ipconfig /flushdns | Out-Null
        Add-Ok "Flushed DNS cache."

        # Prefer Cloudflare/Google DNS on active adapter
        if ($cfg) {
            $alias = $cfg.InterfaceAlias
            try {
                Set-DnsClientServerAddress -InterfaceAlias $alias -ServerAddresses ("1.1.1.1","8.8.8.8") -ErrorAction Stop
                Add-Ok "DNS set to 1.1.1.1 / 8.8.8.8 on $alias"
            }
            catch { Add-Fix "Could not set DNS automatically. Set manually in adapter properties." }
        }

        # Limit Delivery Optimization to local network only / off for downloads from internet PCs
        try {
            New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Force | Out-Null
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Name "DODownloadMode" -Value 0 -Type DWord -Force
            Add-Ok "Disabled Delivery Optimization peer downloads (DODownloadMode=0)."
        }
        catch { Out-Both "Could not change Delivery Optimization registry." "DarkYellow" }

        # Disable WiFi power saving on WiFi adapters
        Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' -and $_.Name -match 'Wi-Fi|Wireless|WLAN' } | ForEach-Object {
            try {
                Set-NetAdapterPowerManagement -Name $_.Name -ArpOffload Disabled -NSOffload Disabled -ErrorAction SilentlyContinue
                powercfg /change monitor-timeout-ac 0 | Out-Null
                Add-Ok "Checked power options for adapter $($_.Name)."
            } catch {}
        }

        # Network throttling index (Xbox/multimedia)
        try {
            New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Force | Out-Null
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" -Value 0xffffffff -Type DWord -Force
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "SystemResponsiveness" -Value 0 -Type DWord -Force
            Add-Ok "Disabled Windows network throttling for multimedia/gaming profile."
        }
        catch { Out-Both "Could not set NetworkThrottlingIndex." "DarkYellow" }

        Out-Both "Optional deeper reset (needs reboot): netsh winsock reset & netsh int ip reset" "DarkYellow"
        $deep = Read-Host "Run Winsock/IP reset now (reboot required after)? [y/N]"
        if ($deep -match '^[Yy]') {
            netsh winsock reset | Out-Null
            netsh int ip reset | Out-Null
            Add-Ok "Winsock + IP stack reset queued. REBOOT your PC."
        }
    }
    catch {
        Out-Both "Fix section error: $($_.Exception.Message)" "Red"
    }
}
else {
    Out-Both "Skipped applying fixes." "DarkYellow"
}

# ---------- 8) Gaming checklist ----------
Write-Sec "8) Router / Signal Checklist (manual)"
Out-Both @"
On the ROUTER admin page (usually http://192.168.1.1 or http://192.168.0.1):
 1) Enable QoS / Gaming priority for this PC MAC address
 2) Use 5GHz SSID for gaming PC (not 2.4GHz)
 3) Set WiFi channel: 5GHz auto or less crowded (36/40/44/149)
 4) Disable Smart Connect if it keeps pushing you to 2.4GHz
 5) Reboot modem + router (power off 30 seconds)
 6) Best fix for games: Ethernet cable instead of WiFi

On THIS PC while gaming:
 - Pause Steam/Epic downloads
 - Close torrents / cloud sync
 - Exit AnyDesk/TeamViewer if unused
 - Turn off VPN
 - Close unused Chrome tabs with video
"@ "White"

# ---------- Summary ----------
Write-Sec "SUMMARY"
if ($Issues.Count -eq 0) {
    Add-Ok "No major local issues found by this scan."
    Out-Both "If game still lags: problem is likely ISP route, WiFi interference, or game server region." "Yellow"
}
else {
    Out-Both "Issues found: $($Issues.Count)" "Red"
    $Issues | ForEach-Object { Out-Both " - $_" "Red" }
    Out-Both "`nRecommended fixes:" "Yellow"
    $Fixes | Select-Object -Unique | ForEach-Object { Out-Both " - $_" "Yellow" }
}

Out-Both "`nFull report saved to:`n$ReportFile" "Cyan"
Out-Both "Open report folder? (Y/n)"
$open = Read-Host
if ($open -notmatch '^[Nn]') { explorer $ReportDir }

Read-Host "`nPress Enter to exit"
