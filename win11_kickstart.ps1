<#
.SYNOPSIS
    Windows 11 Power-User Kickstart Script for Proxmox/OpenClaw.
    Debloats system, installs SSH/PWSH, enables RDP/SSH, and optimizes performance.
#>

# 1. Self-Elevation to Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Elevating privileges..." -ForegroundColor Cyan
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$ErrorActionPreference = "SilentlyContinue"

# 2. Ensure WinGet is present and updated
Write-Host "[1/6] Initializing WinGet..." -ForegroundColor Yellow
if (!(Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "WinGet not found. Attempting to install/update App Installer..." -ForegroundColor Gray
    Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
}
winget settings --enable LocalManifestFiles

# 3. Perform Debloat (Preserving Essentials)
Write-Host "[2/6] Running Secure Debloat (Excluding Photos/Store/Snipping/Terminal)..." -ForegroundColor Yellow
$DebloatScript = {
    & ([scriptblock]::Create((irm "https://debloat.raphi.re/"))) -CLI -Silent `
        -RemoveApps -DisableTelemetry -DisableAds -DisablePrivacyDASH `
        -Exclude "Microsoft.WindowsStore", "Microsoft.WindowsCalculator", "Microsoft.Windows.Photos", "Microsoft.ScreenSketch", "Microsoft.WindowsTerminal"
}
Invoke-Command -ScriptBlock $DebloatScript

# 4. Install & Enable OpenSSH Server
Write-Host "[3/6] Installing OpenSSH Server..." -ForegroundColor Yellow
$Capability = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
if ($Capability.State -ne 'Installed') {
    Add-WindowsCapability -Online -Name $Capability.Name
}
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'
New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow

# 5. Install/Upgrade PowerShell 7 (pwsh)
Write-Host "[4/6] Upgrading to PowerShell 7..." -ForegroundColor Yellow
winget install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements

# 6. Enable Remote Desktop (RDP)
Write-Host "[5/6] Enabling Remote Desktop for all accounts..." -ForegroundColor Yellow
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 1

# 7. Tie SSH to PowerShell 7 (Default Shell)
Write-Host "[6/6] Setting PowerShell 7 as default SSH shell..." -ForegroundColor Yellow
$pwshPath = "C:\Program Files\PowerShell\7\pwsh.exe"
if (Test-Path $pwshPath) {
    if (!(Test-Path "HKLM:\SOFTWARE\OpenSSH")) { New-Item -Path "HKLM:\SOFTWARE\OpenSSH" -Force }
    New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name "DefaultShell" -Value $pwshPath -PropertyType String -Force
}

Write-Host "`nKICKSTART COMPLETE! Please reboot to finalize all changes." -ForegroundColor Green
Pause
