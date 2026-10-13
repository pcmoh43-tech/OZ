#Requires -RunAsAdministrator
# Gaming network boost: closes bandwidth hogs, disables their autostart, tunes WiFi and TCP.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File gaming-boost.ps1

$ErrorActionPreference = "Continue"

function Say([string]$Msg, [string]$Color = "White") { Write-Host $Msg -ForegroundColor $Color }
function Ok([string]$Msg)   { Say "[OK]   $Msg" "Green" }
function Warn([string]$Msg) { Say "[SKIP] $Msg" "DarkYellow" }

function Measure-Latency {
    param([string]$Target = "1.1.1.1", [int]$Count = 10)
    try {
        $r = Test-Connection -ComputerName $Target -Count $Count -ErrorAction Stop
        $times = @($r | ForEach-Object { $_.ResponseTime })
        $avg = [math]::Round(($times | Measure-Object -Average).Average, 1)
        $max = ($times | Measure-Object -Maximum).Maximum
        $loss = [math]::Round((($Count - $times.Count) / $Count) * 100, 1)
        return [pscustomobject]@{ Avg = $avg; Max = $max; Loss = $loss }
    }
    catch { return [pscustomobject]@{ Avg = 9999; Max = 9999; Loss = 100 } }
}

Clear-Host
Say "============================================" "Cyan"
Say "   Gaming Network Boost" "Cyan"
Say "============================================" "Cyan"

Say "`n[0/6] Measuring BEFORE..." "Yellow"
$before = Measure-Latency
Say ("   Before: avg={0}ms max={1}ms loss={2}%" -f $before.Avg, $before.Max, $before.Loss)

Say "`n[1/6] Closing background bandwidth hogs..." "Yellow"
$hogs = @(
    "AnyDesk", "AdobeCollabSync", "AdobeUpdateService", "AdobeIPCBroker", "CCXProcess", "CCLibrary",
    "Creative Cloud", "OneDrive", "Dropbox", "GoogleDriveFS", "BitTorrent", "uTorrent", "qBittorrent",
    "TeamViewer", "Skype", "SearchApp", "YourPhone", "PhoneExperienceHost", "WidgetService", "Widgets"
)
foreach ($name in $hogs) {
    $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
    if ($procs) {
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        Ok "Closed $name"
    }
}

Say "`n[2/6] Disabling autostart of AnyDesk / Adobe sync..." "Yellow"
$runKeys = @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
)
$autostartMatch = "AnyDesk|AdobeCollab|Adobe Creative|CCXProcess|AdobeGCInvoker|AdobeAAMUpdater"
foreach ($key in $runKeys) {
    if (Test-Path $key) {
        $props = (Get-ItemProperty -Path $key).PSObject.Properties |
            Where-Object { $_.Name -match $autostartMatch -and $_.Name -notmatch '^PS' }
        foreach ($p in $props) {
            Remove-ItemProperty -Path $key -Name $p.Name -ErrorAction SilentlyContinue
            Ok "Removed autostart: $($p.Name)"
        }
    }
}
Get-ScheduledTask -ErrorAction SilentlyContinue |
    Where-Object { $_.TaskName -match "AdobeGCInvoker|Adobe Acrobat Update|AdobeAAMUpdater|AnyDesk" -and $_.State -ne 'Disabled' } |
    ForEach-Object {
        Disable-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -ErrorAction SilentlyContinue | Out-Null
        Ok "Disabled scheduled task: $($_.TaskName)"
    }
$anydeskSvc = Get-Service -Name "AnyDesk" -ErrorAction SilentlyContinue
if ($anydeskSvc) {
    Stop-Service -Name AnyDesk -Force -ErrorAction SilentlyContinue
    Set-Service -Name AnyDesk -StartupType Manual -ErrorAction SilentlyContinue
    Ok "AnyDesk service set to Manual"
}

Say "`n[3/6] Tuning WiFi adapter..." "Yellow"
$wifiAdapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
    Where-Object { $_.Status -eq 'Up' -and ($_.InterfaceDescription -match 'Wi-?Fi|Wireless|802\.11|WLAN' -or $_.Name -match 'Wi-?Fi|Wireless|WLAN') }
foreach ($a in $wifiAdapters) {
    $props = Get-NetAdapterAdvancedProperty -Name $a.Name -ErrorAction SilentlyContinue

    $band = $props | Where-Object { $_.DisplayName -match 'Preferred Band|Band Preference' } | Select-Object -First 1
    if ($band) {
        $valid = @($band.ValidDisplayValues)
        $pref = $valid | Where-Object { $_ -match '5|Prefer.*5' } | Select-Object -First 1
        if ($pref) {
            Set-NetAdapterAdvancedProperty -Name $a.Name -DisplayName $band.DisplayName -DisplayValue $pref -ErrorAction SilentlyContinue
            Ok "$($a.Name): $($band.DisplayName) = $pref"
        }
    } else { Warn "$($a.Name): no band preference option on this driver" }

    $roam = $props | Where-Object { $_.DisplayName -match 'Roaming Aggressiveness' } | Select-Object -First 1
    if ($roam) {
        $lowest = @($roam.ValidDisplayValues) | Where-Object { $_ -match 'Lowest|1' } | Select-Object -First 1
        if ($lowest) {
            Set-NetAdapterAdvancedProperty -Name $a.Name -DisplayName $roam.DisplayName -DisplayValue $lowest -ErrorAction SilentlyContinue
            Ok "$($a.Name): roaming aggressiveness = $lowest"
        }
    }

    $ps = $props | Where-Object { $_.DisplayName -match 'Power Saving|Power Save|Throughput Booster|MIMO Power' } | Select-Object -First 3
    foreach ($p in $ps) {
        $off = @($p.ValidDisplayValues) | Where-Object { $_ -match 'Disable|Off|Maximum|No Power' } | Select-Object -First 1
        if ($off -and $p.DisplayName -notmatch 'Throughput') {
            Set-NetAdapterAdvancedProperty -Name $a.Name -DisplayName $p.DisplayName -DisplayValue $off -ErrorAction SilentlyContinue
            Ok "$($a.Name): $($p.DisplayName) = $off"
        }
    }

    try {
        Disable-NetAdapterPowerManagement -Name $a.Name -ErrorAction Stop
        Ok "$($a.Name): Windows may no longer turn this adapter off to save power"
    } catch { Warn "$($a.Name): power management option not available" }
}
if (-not $wifiAdapters) { Warn "No active WiFi adapter found (wired connection?)" }

Say "`n[4/6] TCP tuning for low latency..." "Yellow"
$ifaces = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" -ErrorAction SilentlyContinue
foreach ($i in $ifaces) {
    $props = Get-ItemProperty $i.PSPath -ErrorAction SilentlyContinue
    if ($props.DhcpIPAddress -and $props.DhcpIPAddress -notmatch '^169\.') {
        Set-ItemProperty -Path $i.PSPath -Name "TcpAckFrequency" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $i.PSPath -Name "TCPNoDelay" -Value 1 -Type DWord -Force
        Ok "Low-latency TCP on interface $($props.DhcpIPAddress)"
    }
}
netsh int tcp set global autotuninglevel=normal | Out-Null
netsh int tcp set global ecncapability=disabled | Out-Null
netsh int tcp set global rss=enabled | Out-Null
Ok "TCP autotuning normal, ECN off, RSS on"

Say "`n[5/6] Power plan + background services..." "Yellow"
$high = powercfg -list | Select-String "High performance|Ultimate Performance" | Select-Object -First 1
if ($high -and $high.Line -match '([0-9a-fA-F-]{36})') {
    powercfg -setactive $Matches[1] | Out-Null
    Ok "Power plan set to High/Ultimate performance"
} else { Warn "High performance plan not found" }

Stop-Service -Name DoSvc -Force -ErrorAction SilentlyContinue
Ok "Stopped Delivery Optimization service for this session"

$mo = Get-Process -Name MoUsoCoreWorker -ErrorAction SilentlyContinue
if ($mo) {
    try {
        $until = (Get-Date).AddDays(1).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        $wu = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
        New-Item -Path $wu -Force | Out-Null
        Set-ItemProperty -Path $wu -Name "PauseUpdatesExpiryTime" -Value $until -Type String -Force
        Set-ItemProperty -Path $wu -Name "PauseFeatureUpdatesEndTime" -Value $until -Type String -Force
        Set-ItemProperty -Path $wu -Name "PauseQualityUpdatesEndTime" -Value $until -Type String -Force
        Ok "Windows Update paused for 24 hours"
    } catch { Warn "Could not pause Windows Update automatically" }
}

ipconfig /flushdns | Out-Null
Ok "DNS cache flushed"

Say "`n[6/6] Measuring AFTER..." "Yellow"
Say "   Waiting for WiFi to reconnect after adapter changes (up to 45s)..." "DarkGray"
$deadline = (Get-Date).AddSeconds(45)
do {
    Start-Sleep -Seconds 3
    $up = Test-Connection -ComputerName 1.1.1.1 -Count 1 -Quiet -ErrorAction SilentlyContinue
} while (-not $up -and (Get-Date) -lt $deadline)
Start-Sleep -Seconds 3
$after = Measure-Latency
Say ("   After:  avg={0}ms max={1}ms loss={2}%" -f $after.Avg, $after.Max, $after.Loss)

Say "`n============================================" "Cyan"
Say ("   Before: {0}ms avg / {1}% loss" -f $before.Avg, $before.Loss) "White"
Say ("   After : {0}ms avg / {1}% loss" -f $after.Avg, $after.Loss) "Green"
Say "============================================" "Cyan"
Say "`nStill manual (cannot be done from Windows):" "Yellow"
Say " - Restart modem + router: unplug 30 seconds"
Say " - Router page: enable QoS/Gaming priority for this PC, use the 5GHz network name"
Say " - Best result: Ethernet cable"
Say " - Pause Steam/Epic downloads while playing"
Read-Host "`nPress Enter to exit"
