#Requires -RunAsAdministrator
# Run after a reboot, BEFORE starting Delta Force.
# Frees RAM/CPU/network by closing and pausing everything the game does not need.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File pre-game-clean.ps1
# Add -CloseBrowsers to also close Chrome/Edge/Firefox (unsaved tabs are lost).

param([switch]$CloseBrowsers)

$ErrorActionPreference = "SilentlyContinue"

function Say([string]$Msg, [string]$Color = "White") { Write-Host $Msg -ForegroundColor $Color }
function Ok([string]$Msg)   { Say "[OK]   $Msg" "Green" }
function Note([string]$Msg) { Say "[NOTE] $Msg" "Yellow" }

function Get-FreeRamGB {
    $os = Get-CimInstance Win32_OperatingSystem
    [math]::Round($os.FreePhysicalMemory / 1MB, 2)
}

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class MemTrim {
    [DllImport("psapi.dll")] public static extern bool EmptyWorkingSet(IntPtr hProcess);
}
"@

Clear-Host
Say "============================================" "Cyan"
Say "   Pre-game clean for Delta Force" "Cyan"
Say "============================================" "Cyan"

$totalGB  = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
$freeBefore = Get-FreeRamGB
Say "`nRAM: $totalGB GB total, $freeBefore GB free (before)" "Yellow"

Say "`n[1/6] Closing apps the game does not need..." "Yellow"
$patterns = @(
    'omen','HPOmen','Discord','AnyDesk','AdobeCollabSync','AdobeIPCBroker','Adobe Desktop Service','CCXProcess','CoreSync','AdobeUpdateService','node',
    'OneDrive','Teams','ms-teams','Spotify','Skype','Dropbox','GoogleDriveFS','YourPhone','PhoneExperienceHost','Widgets','WidgetService',
    'EpicWebHelper','EpicGamesLauncher','Steamwebhelper','Telegram','WhatsApp','Zoom','Slack'
)
if ($CloseBrowsers) { $patterns += 'chrome','msedge','firefox','opera','brave' }

$protect = 'Cursor','cursor','powershell','pwsh','WindowsTerminal','explorer','DeltaForce'
$closed = New-Object System.Collections.Generic.List[string]
Get-Process | ForEach-Object {
    $name = $_.ProcessName
    if ($protect | Where-Object { $name -like "$_*" }) { return }
    foreach ($p in $patterns) {
        if ($name -like "*$p*") {
            if ($name -eq 'node' -and $_.Path -notmatch 'Adobe') { break }
            Stop-Process -Id $_.Id -Force
            $closed.Add($name)
            break
        }
    }
}
if ($closed.Count) { Ok ("Closed: " + (($closed | Sort-Object -Unique) -join ', ')) } else { Ok "Nothing extra was running" }

Say "`n[2/6] Pausing background services until next reboot..." "Yellow"
$services = @{
    'CloudflareWARP' = 'Cloudflare WARP VPN'
    'DiagTrack'      = 'Telemetry'
    'WSearch'        = 'Search indexer'
    'DoSvc'          = 'Delivery Optimization (uploads updates)'
    'BITS'           = 'Background transfer'
    'wuauserv'       = 'Windows Update'
    'SysMain'        = 'Superfetch'
    'AnyDesk'        = 'AnyDesk'
    'AdobeUpdateService' = 'Adobe updater'
    'AGMService'     = 'Adobe Genuine'
    'AGSService'     = 'Adobe Genuine'
}
foreach ($s in $services.GetEnumerator()) {
    $svc = Get-Service -Name $s.Key
    if ($svc -and $svc.Status -eq 'Running') {
        Stop-Service -Name $s.Key -Force
        if ($?) { Ok "Stopped $($s.Value)" }
    }
}
Get-Service | Where-Object { $_.DisplayName -match 'OMEN|HP (Analytics|Diagnostics|System Info|Network)' -and $_.Status -eq 'Running' } | ForEach-Object {
    Stop-Service -Name $_.Name -Force
    Ok "Stopped $($_.DisplayName)"
}
Set-Service -Name CloudflareWARP -StartupType Manual

Say "`n[3/6] Removing heavy apps from Windows startup..." "Yellow"
$runKeys = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
$startPat = 'Discord|AnyDesk|Adobe|OneDrive|OMEN|HPOmen|Teams|Spotify|Skype|Dropbox|Epic|Steam'
$backup = Join-Path $PSScriptRoot "startup-backup.txt"
foreach ($k in $runKeys) {
    $props = Get-ItemProperty $k
    if (-not $props) { continue }
    foreach ($prop in $props.PSObject.Properties) {
        if ($prop.Name -match '^PS' ) { continue }
        if ($prop.Name -match $startPat -or "$($prop.Value)" -match $startPat) {
            "$k | $($prop.Name) | $($prop.Value)" | Add-Content $backup
            Remove-ItemProperty -Path $k -Name $prop.Name
            Ok "Removed from startup: $($prop.Name)"
        }
    }
}
Note "Backup of removed entries: $backup"

Say "`n[4/6] Making Defender lighter while you play..." "Yellow"
Set-MpPreference -ScanAvgCPULoadFactor 10
Set-MpPreference -DisableCatchupFullScan $true
Set-MpPreference -DisableCatchupQuickScan $true
Set-MpPreference -ScanOnlyIfIdleEnabled $true
Ok "Scans limited to 10% CPU and only when idle (real-time protection stays ON)"

Say "`n[5/6] Releasing memory held by background programs..." "Yellow"
$trimmed = 0
Get-Process | Where-Object { $_.ProcessName -notmatch '^(DeltaForce|System|Idle|Registry|MemCompression)' } | ForEach-Object {
    if ([MemTrim]::EmptyWorkingSet($_.Handle)) { $trimmed++ }
}
Ok "Trimmed $trimmed processes"
$plan = powercfg -list | Select-String "High performance|Ultimate Performance" | Select-Object -First 1
if ($plan -and $plan.Line -match '([0-9a-fA-F-]{36})') { powercfg -setactive $Matches[1] | Out-Null; Ok "High performance power plan active" }
ipconfig /flushdns | Out-Null
Ok "DNS cache flushed"

Say "`n[6/6] Result" "Yellow"
Start-Sleep -Seconds 2
$freeAfter = Get-FreeRamGB
Say ("   Free RAM: {0} GB -> {1} GB" -f $freeBefore, $freeAfter) "Green"

Say "`nTop 8 processes still using RAM:" "Yellow"
Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 8 |
    ForEach-Object { Say ("   {0,-28} {1,7} MB" -f $_.ProcessName, [math]::Round($_.WorkingSet64 / 1MB)) }

Say "`n============================================" "Cyan"
Say "   Ready. Start Delta Force now." "Green"
Say "   If a program you need was closed, just reopen it." "Green"
Say "============================================" "Cyan"
Read-Host "`nPress Enter to exit"
