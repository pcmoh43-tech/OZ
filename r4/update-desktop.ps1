# Copy and paste in PowerShell (Admin) to update Desktop\r4

$dest = "$env:USERPROFILE\Desktop\r4"
New-Item -ItemType Directory -Force -Path $dest | Out-Null

# --- HOST: waits for client ---
@'
#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
$Port = 9876
function Get-MyIP { (Get-NetIPAddress -AddressFamily IPv4 | ? { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.*" } | select -First 1).IPAddress }
function Enable-Sharing { Set-NetConnectionProfile -NetworkCategory Private -EA SilentlyContinue; netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes | Out-Null; New-NetFirewallRule -DisplayName "R4-Wait" -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow -EA SilentlyContinue | Out-Null }
function Get-UsbPrinters { Get-CimInstance Win32_Printer | ? { $_.Local -and $_.Name -notmatch "OneNote|PDF|XPS|Fax|AnyDesk" } }
function Start-WaitServer($ShareName,$PrinterName,$IP) {
  $info = (@{ip=$IP;hostname=$env:COMPUTERNAME;shareName=$ShareName;printerName=$PrinterName;path="\\$IP\$ShareName"} | ConvertTo-Json -Compress)
  $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any,$Port); $listener.Start()
  Write-Host "`n=== HOST READY - Waiting for Client ===" -ForegroundColor Green
  Write-Host "IP: $IP  Share: $ShareName  Path: \\$IP\$ShareName`nRun RUN-CLIENT.bat on PC 2`n" -ForegroundColor White
  $done=$false
  while($true){ if($listener.Pending()){ $c=$listener.AcceptTcpClient(); $s=$c.GetStream(); $r=New-Object IO.StreamReader($s); $w=New-Object IO.StreamWriter($s); $w.AutoFlush=$true; $req=$r.ReadLine(); $rem=$c.Client.RemoteEndPoint.Address
    switch($req){"DISCOVER"{$w.WriteLine($info)}"INSTALL"{Write-Host "Client installing..." -ForegroundColor Yellow;$w.WriteLine("OK")}"CONNECTED"{Write-Host "Client connected!" -ForegroundColor Green;$w.WriteLine("OK")}"TEST_PRINT"{Write-Host "Test print done!" -ForegroundColor Green;$done=$true;$w.WriteLine("OK")}"PING"{$w.WriteLine("PONG|$info")}default{$w.WriteLine("UNKNOWN")}}; $c.Close(); if($done){Read-Host "Press Enter";break}}; Start-Sleep -Milliseconds 300}; $listener.Stop()
}
Clear-Host; Write-Host "=== HOST - USB Printer ===" -ForegroundColor Cyan
$printers=@(Get-UsbPrinters); if(!$printers.Count){Write-Host "No printers!";Read-Host;exit 1}
for($i=0;$i -lt $printers.Count;$i++){Write-Host "  $($i+1). $($printers[$i].Name)"}
$sel=[int](Read-Host "Select printer")-1; $p=$printers[$sel]
$share=($p.Name -replace '[^a-zA-Z0-9]',''); $c=Read-Host "Share name (Enter=$share)"; if($c){$share=($c -replace '[^a-zA-Z0-9]','')}
Enable-Sharing; Set-Printer -Name $p.Name -Shared $true -ShareName $share
$ip=Get-MyIP; @{ip=$ip;shareName=$share;printerName=$p.Name} | ConvertTo-Json | Set-Content "$PSScriptRoot\host-config.json"
Start-WaitServer $share $p.Name $ip
'@ | Set-Content "$dest\host-wait.ps1" -Encoding UTF8

# --- CLIENT: connect, install, test print ---
@'
#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
$Port = 9876
function Send-Req($HostIP,$Cmd){ $c=New-Object Net.Sockets.TcpClient; $c.ReceiveTimeout=3000; $c.Connect($HostIP,$Port); $s=$c.GetStream(); $w=New-Object IO.StreamWriter($s); $r=New-Object IO.StreamReader($s); $w.AutoFlush=$true; $w.WriteLine($Cmd); $resp=$r.ReadLine(); $c.Close(); return $resp }
function Find-Host{ $myIp=(Get-NetIPAddress -AddressFamily IPv4|?{$_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.*"}|select -First 1).IPAddress; $sub=($myIp.Split("."))[0..2]-join"."; Write-Host "Scanning $sub.0/24..." -ForegroundColor Yellow; for($i=1;$i -le 254;$i++){ $t="$sub.$i"; Write-Host "`r  Trying $t...  " -NoNewline; try{$resp=Send-Req $t "PING"; if($resp -match "PONG\|"){Write-Host "`nFound Host: $t" -ForegroundColor Green; return ($resp-replace "^PONG\|","")|ConvertFrom-Json}}catch{}}; Write-Host ""; return $null }
Clear-Host; Write-Host "=== CLIENT - Connect Printer ===" -ForegroundColor Cyan
Write-Host "Make sure HOST script is running on PC 1!`n" -ForegroundColor Yellow
$info=$null; if(Test-Path "$PSScriptRoot\host-config.json"){ $s=Get-Content "$PSScriptRoot\host-config.json"|ConvertFrom-Json; if((Read-Host "Use saved IP $($s.ip)? [Y/n]") -notmatch "^[Nn]"){$info=$s}}
if(!$info){ if((Read-Host "Auto-scan? [Y/n]") -notmatch "^[Nn]"){$info=Find-Host}; if(!$info){ $ip=Read-Host "Enter Host IP"; $info=(Send-Req $ip "DISCOVER")|ConvertFrom-Json }}
Write-Host "`nHost: $($info.ip)  Share: $($info.shareName)" -ForegroundColor Green
Send-Req $info.ip "INSTALL"|Out-Null
$path="\\$($info.ip)\$($info.shareName)"; Write-Host "Installing $path..." -ForegroundColor Yellow
try{Add-Printer -ConnectionName $path}catch{rundll32 printui.dll,PrintUIEntry /in /n $path}
Send-Req $info.ip "CONNECTED"|Out-Null
$pr=Get-Printer|select -Last 1; Set-Printer -Name $pr.Name -Default
$f="$env:TEMP\r4-test.txt"; "Printer Test - $(Get-Date)"|Set-Content $f; Start-Process $f -Verb Print -EA SilentlyContinue
Send-Req $info.ip "TEST_PRINT"|Out-Null
Write-Host "`n=== DONE! Test page sent ===" -ForegroundColor Green; Read-Host "Press Enter"
'@ | Set-Content "$dest\client-connect.ps1" -Encoding UTF8

@'
@echo off
title HOST - Wait for Client
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0host-wait.ps1"
pause
'@ | Set-Content "$dest\RUN-HOST.bat" -Encoding ASCII

@'
@echo off
title CLIENT - Connect Printer
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0client-connect.ps1"
pause
'@ | Set-Content "$dest\RUN-CLIENT.bat" -Encoding ASCII

@'
@echo off
echo [1] PC1 HOST  [2] PC2 CLIENT  [3] Exit
set /p c="Choose: "
if "%c%"=="1" call "%~dp0RUN-HOST.bat"
if "%c%"=="2" call "%~dp0RUN-CLIENT.bat"
'@ | Set-Content "$dest\START.bat" -Encoding ASCII

Write-Host "Done! Open: $dest" -ForegroundColor Green
explorer $dest
