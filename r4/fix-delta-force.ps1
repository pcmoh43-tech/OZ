#Requires -RunAsAdministrator
# One-click fix for Delta Force stutter/lag. Run with the game CLOSED.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File fix-delta-force.ps1

$ErrorActionPreference = "SilentlyContinue"

function Say([string]$Msg, [string]$Color = "White") { Write-Host $Msg -ForegroundColor $Color }
function Ok([string]$Msg)   { Say "[OK]   $Msg" "Green" }
function Note([string]$Msg) { Say "[NOTE] $Msg" "Yellow" }

function Measure-Ping {
    $r = Test-Connection -ComputerName 1.1.1.1 -Count 10 -ErrorAction SilentlyContinue
    if (-not $r) { return $null }
    $t = @($r | ForEach-Object { if ($null -ne $_.ResponseTime) { [double]$_.ResponseTime } else { [double]$_.Latency } })
    [pscustomobject]@{
        Avg    = [math]::Round(($t | Measure-Object -Average).Average, 1)
        Max    = ($t | Measure-Object -Maximum).Maximum
        Loss   = [math]::Round(((10 - $t.Count) / 10) * 100, 0)
    }
}

Clear-Host
Say "============================================" "Cyan"
Say "   Delta Force - One-click Fix" "Cyan"
Say "============================================" "Cyan"

Say "`n[0/5] Latency BEFORE..." "Yellow"
$before = Measure-Ping
if ($before) { Say ("   avg {0} ms | max {1} ms | loss {2}%" -f $before.Avg, $before.Max, $before.Loss) } else { Note "No ping reply" }

Say "`n[1/5] Looking for the Delta Force install folder..." "Yellow"
$exeNames = 'DeltaForceClient-Win64-Shipping.exe','DeltaForce.exe','DeltaForceClient.exe'
$gameDir = $null; $gameExe = $null

$running = Get-Process | Where-Object { $_.ProcessName -match 'DeltaForce|Delta_?Force' } | Select-Object -First 1
if ($running -and $running.Path) { $gameExe = $running.Path; $gameDir = Split-Path $gameExe -Parent }

if (-not $gameDir) {
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    foreach ($k in $keys) {
        $hit = Get-ItemProperty $k | Where-Object { $_.DisplayName -match 'Delta Force' -and $_.InstallLocation } | Select-Object -First 1
        if ($hit) { $gameDir = $hit.InstallLocation.TrimEnd('\'); break }
    }
}

if (-not $gameDir) {
    $roots = @()
    foreach ($d in (Get-PSDrive -PSProvider FileSystem)) {
        foreach ($sub in 'Program Files','Program Files (x86)','Garena','Games','') {
            $p = if ($sub) { Join-Path $d.Root $sub } else { $d.Root }
            if (Test-Path $p) { $roots += $p }
        }
    }
    foreach ($r in ($roots | Select-Object -Unique)) {
        $f = Get-ChildItem -Path $r -Include $exeNames -Recurse -Depth 6 -File | Select-Object -First 1
        if ($f) { $gameExe = $f.FullName; $gameDir = Split-Path $f.FullName -Parent; break }
    }
}

if ($gameDir) {
    Ok "Game folder: $gameDir"
    Add-MpPreference -ExclusionPath $gameDir
    Ok "Defender will no longer scan the game folder (protection stays ON for everything else)"
    foreach ($n in $exeNames) { Add-MpPreference -ExclusionProcess $n }
    if (-not $gameExe) { $gameExe = (Get-ChildItem -Path $gameDir -Include $exeNames -Recurse -Depth 4 -File | Select-Object -First 1).FullName }
    if ($gameExe) {
        New-Item -Path "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences" -Force | Out-Null
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences" -Name $gameExe -Value "GpuPreference=2;" -Type String -Force
        Ok "Game set to use the high-performance GPU"
    }
} else {
    Note "Could not find the game folder. Start the game once, then run this script again."
}

Say "`n[2/5] Closing unneeded background apps..." "Yellow"
$closed = @()
Get-Process | Where-Object { $_.ProcessName -match 'omen|AnyDesk|Discord|AdobeCollabSync|OneDrive' } | ForEach-Object {
    $closed += $_.ProcessName
    Stop-Process -Id $_.Id -Force
}
if ($closed.Count) { Ok ("Closed: " + (($closed | Sort-Object -Unique) -join ', ')) } else { Ok "Nothing extra was running" }

Say "`n[3/5] Stopping Cloudflare WARP (VPN that adds delay)..." "Yellow"
$warp = Get-Service -Name CloudflareWARP
if ($warp) {
    Stop-Service -Name CloudflareWARP -Force
    Set-Service -Name CloudflareWARP -StartupType Manual
    Stop-Process -Name warp-svc -Force
    Ok "WARP stopped and set to Manual (start it from the WARP app when you need it)"
} else { Ok "WARP service not found" }

Say "`n[4/5] Graphics and power settings..." "Yellow"
New-Item -Path "HKCU:\System\GameConfigStore" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 0 -Type DWord -Force
New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value 0 -Type DWord -Force
New-Item -Path "HKCU:\Software\Microsoft\GameBar" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\Software\Microsoft\GameBar" -Name "AutoGameModeEnabled" -Value 1 -Type DWord -Force
Ok "Game Bar recording off, Game Mode on"
$plan = powershell -NoProfile -Command "powercfg -list" | Select-String "High performance|Ultimate Performance" | Select-Object -First 1
if ($plan -and $plan.Line -match '([0-9a-fA-F-]{36})') { powercfg -setactive $Matches[1] | Out-Null; Ok "High performance power plan active" }
ipconfig /flushdns | Out-Null
Ok "DNS cache flushed"

Say "`n[5/5] Latency AFTER..." "Yellow"
Start-Sleep -Seconds 5
$after = Measure-Ping
if ($after) { Say ("   avg {0} ms | max {1} ms | loss {2}%" -f $after.Avg, $after.Max, $after.Loss) } else { Note "No ping reply (wait a few seconds and run: Test-Connection 1.1.1.1)" }

Say "`n============================================" "Cyan"
if ($before -and $after) {
    Say ("   Before: {0} ms   After: {1} ms" -f $before.Avg, $after.Avg) "Green"
}
Say "   Now start Delta Force." "Green"
Say "============================================" "Cyan"
Say "`nStill worth doing: Ethernet cable if possible, and pick the nearest server inside the game." "Yellow"
Read-Host "`nPress Enter to exit"
