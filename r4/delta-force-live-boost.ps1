#Requires -RunAsAdministrator
# Delta Force live boost: run while the game is open. Does NOT close or touch the game's memory.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File delta-force-live-boost.ps1
# Stop monitoring with Ctrl+C.

$ErrorActionPreference = "SilentlyContinue"

function Say([string]$Msg, [string]$Color = "White") { Write-Host $Msg -ForegroundColor $Color }
function Ok([string]$Msg)   { Say "[OK]   $Msg" "Green" }
function Warn([string]$Msg) { Say "[NOTE] $Msg" "Yellow" }

Clear-Host
Say "============================================" "Cyan"
Say "   Delta Force - Live Boost (game stays open)" "Cyan"
Say "============================================" "Cyan"

$game = Get-Process | Where-Object { $_.ProcessName -match 'DeltaForce|Delta_?Force|DFClient' } | Sort-Object WorkingSet -Descending | Select-Object -First 1
if (-not $game) {
    Warn "Delta Force is not running. Start the game, then run this script again."
    Read-Host "Press Enter to exit"
    exit 1
}
Ok "Game found: $($game.ProcessName) (PID $($game.Id))"

Say "`n[1/5] Game priority..." "Yellow"
try {
    $game.PriorityClass = 'High'
    Ok "Game priority set to High"
} catch { Warn "Anti-cheat blocked changing priority. Not a problem; other steps still help." }

Say "`n[2/5] Lowering priority of background apps (not closing them)..." "Yellow"
$bg = 'chrome','msedge','firefox','Cursor','Code','Discord','OneDrive','Dropbox','GoogleDriveFS','Teams','Slack','Telegram',
      'vmware-vmx','vmnat','vmware-hostd','SearchApp','SearchIndexer','MsMpEng','OneNote','Spotify','steamwebhelper','EpicWebHelper'
$lowered = @()
foreach ($n in $bg) {
    Get-Process -Name $n | ForEach-Object {
        try { $_.PriorityClass = 'BelowNormal'; $lowered += $_.ProcessName } catch {}
    }
}
if ($lowered.Count -gt 0) { Ok ("Lowered: " + (($lowered | Sort-Object -Unique) -join ', ')) } else { Ok "No heavy background apps found" }

Say "`n[3/5] Windows settings that cause stutter..." "Yellow"
try {
    New-Item -Path "HKCU:\System\GameConfigStore" -Force | Out-Null
    Set-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 0 -Type DWord -Force
    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Force | Out-Null
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value 0 -Type DWord -Force
    New-Item -Path "HKCU:\Software\Microsoft\GameBar" -Force | Out-Null
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\GameBar" -Name "AutoGameModeEnabled" -Value 1 -Type DWord -Force
    Ok "Xbox Game Bar background recording off, Game Mode on (full effect next launch)"
} catch { Warn "Could not change Game Bar settings" }

$gpus = Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name
Say "   Graphics adapters: $($gpus -join ' | ')"
$exe = $null
try { $exe = $game.Path } catch {}
if ($exe) {
    New-Item -Path "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences" -Force | Out-Null
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences" -Name $exe -Value "GpuPreference=2;" -Type String -Force
    Ok "Game set to use the HIGH-PERFORMANCE GPU (applies next time you start the game)"
    if ($gpus.Count -gt 1) { Warn "Laptop with 2 GPUs detected. If the game was on the weak GPU, restart it once to fix big stutter." }
}

Say "`n[4/5] Top background consumers right now:" "Yellow"
Get-Process | Where-Object { $_.Id -ne $game.Id -and $_.ProcessName -ne 'Idle' } |
    Sort-Object CPU -Descending | Select-Object -First 6 |
    ForEach-Object { Say ("   {0,-28} CPU-time {1,8:N0}s   RAM {2,6:N0} MB" -f $_.ProcessName, $_.CPU, ($_.WorkingSet / 1MB)) }

Say "`n[5/5] Live monitor (every 5 seconds, Ctrl+C to stop)" "Yellow"
$gw = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Sort-Object RouteMetric | Select-Object -First 1).NextHop
$pings = New-Object System.Collections.Generic.List[double]
$lost = 0; $sent = 0
$cores = [Environment]::ProcessorCount

while ($true) {
    $cpu = [math]::Round((Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples[0].CookedValue, 0)
    $os = Get-CimInstance Win32_OperatingSystem
    $ramUsed = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 0)
    $gpuUse = 0
    try {
        $gpuUse = [math]::Round(((Get-Counter '\GPU Engine(*engtype_3D)\Utilization Percentage').CounterSamples | Measure-Object CookedValue -Sum).Sum, 0)
        if ($gpuUse -gt 100) { $gpuUse = 100 }
    } catch {}
    $disk = [math]::Round((Get-Counter '\PhysicalDisk(_Total)\% Disk Time').CounterSamples[0].CookedValue, 0)
    if ($disk -gt 100) { $disk = 100 }

    $sent++
    $r = Test-Connection -ComputerName 1.1.1.1 -Count 1 -ErrorAction SilentlyContinue
    if ($r) {
        $ms = if ($null -ne $r.ResponseTime) { [double]$r.ResponseTime } else { [double]$r.Latency }
        $pings.Add($ms); if ($pings.Count -gt 12) { $pings.RemoveAt(0) }
    } else { $lost++ }
    $avg = if ($pings.Count) { [math]::Round(($pings | Measure-Object -Average).Average, 0) } else { 0 }
    $jit = if ($pings.Count -gt 1) { [math]::Round((($pings | Measure-Object -Maximum).Maximum - ($pings | Measure-Object -Minimum).Minimum), 0) } else { 0 }
    $loss = [math]::Round(($lost / $sent) * 100, 0)

    $verdict = "Looks fine"; $color = "Green"
    if ($loss -ge 3 -or $jit -ge 60 -or $avg -ge 120) { $verdict = "NETWORK problem (WiFi/ISP): lag spikes"; $color = "Red" }
    elseif ($ramUsed -ge 90) { $verdict = "RAM full: close Chrome/Cursor/VMware"; $color = "Red" }
    elseif ($cpu -ge 95) { $verdict = "CPU maxed: close background apps"; $color = "Red" }
    elseif ($disk -ge 95) { $verdict = "DISK maxed (loading stutter): check antivirus/updates"; $color = "Red" }
    elseif ($gpuUse -ge 98) { $verdict = "GPU maxed: lower graphics settings in the game"; $color = "Yellow" }

    Say ("{0}  CPU {1,3}%  RAM {2,3}%  GPU {3,3}%  DISK {4,3}%  | ping {5,3}ms jitter {6,3}ms loss {7}%  => {8}" -f (Get-Date -Format "HH:mm:ss"), $cpu, $ramUsed, $gpuUse, $disk, $avg, $jit, $loss, $verdict) $color
    Start-Sleep -Seconds 5
}
