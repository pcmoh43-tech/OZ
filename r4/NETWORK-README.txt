============================================
 Network Diagnostic for Gaming
============================================

WHAT IT CHECKS
--------------
1) WiFi signal % / band / speed
2) Router gateway latency
3) Internet latency + packet loss
4) Programs using network (Steam, torrents, sync...)
5) Servers listening on your PC
6) Windows Update / Delivery Optimization downloads
7) Applies safe fixes (DNS, flush, throttling, DO)

HOW TO RUN ON YOUR PC
---------------------
PowerShell (Admin):

  Invoke-WebRequest "https://raw.githubusercontent.com/pcmoh43-tech/OZ/cursor/network-diagnostic-3595/r4/network-fix-gaming.ps1" -OutFile "$env:USERPROFILE\Desktop\network-fix-gaming.ps1"
  powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\Desktop\network-fix-gaming.ps1"

Or double-click RUN-NETWORK-FIX.bat after copying both files to Desktop\r4

REPORT
------
Saved to: Desktop\network-report\report-....txt

BEST FIX FOR GAMES
------------------
Use Ethernet cable if possible.
============================================
