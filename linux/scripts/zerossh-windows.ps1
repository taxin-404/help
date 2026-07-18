#requires -RunAsAdministrator
<#
.SYNOPSIS
  zerossh-windows.ps1
  Windows equivalent of the zerossh.sh idea: installs ZeroTier, enables Remote
  Desktop (RDP), opens the firewall for RDP + ZeroTier, and joins your
  ZeroTier network so you can remote-control this PC from anywhere.

.USAGE
  Run as Administrator:
    powershell -ExecutionPolicy Bypass -File .\zerossh-windows.ps1 -NetworkID <your16charID>

  Or just double-click setup-remote.bat after editing the NETWORK_ID inside it.

.NOTES
  - No network ID is hardcoded. You must supply your own — get one free at
    https://my.zerotier.com (click Create A Network).
  - After running, go to https://my.zerotier.com/network/<your-network-id>
    and authorize this device (checkbox next to its node ID) or it stays
    invisible on the network.
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{16}$')]
    [string]$NetworkID
)

$ErrorActionPreference = "Stop"

function Log  ($msg) { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Ok   ($msg) { Write-Host "[OK] $msg" -ForegroundColor Green }
function Warn ($msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Err  ($msg) { Write-Host "[X] $msg" -ForegroundColor Red }

# ---------- 1. Install ZeroTier ----------
function Install-ZeroTier {
    $zt = "C:\Program Files (x86)\ZeroTier\One\zerotier-cli.bat"
    $ztAlt = "C:\ProgramData\chocolatey\bin\zerotier-cli.exe"

    if (Get-Command zerotier-cli -ErrorAction SilentlyContinue) {
        Ok "ZeroTier already installed."
        return
    }

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Log "Installing ZeroTier via winget..."
        winget install --id ZeroTier.ZeroTierOne -e --accept-source-agreements --accept-package-agreements
    }
    else {
        Log "winget not found — downloading ZeroTier MSI directly..."
        $msi = "$env:TEMP\ZeroTierOne.msi"
        Invoke-WebRequest -Uri "https://download.zerotier.com/dist/ZeroTier%20One.msi" -OutFile $msi
        Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn" -Wait
    }

    # zerotier-cli lives in Program Files and isn't always on PATH immediately
    $ztPath = "C:\Program Files (x86)\ZeroTier\One"
    if (Test-Path $ztPath) {
        $env:Path += ";$ztPath"
    }
    Ok "ZeroTier install step complete."
}

# ---------- 2. Enable Remote Desktop ----------
function Enable-RDP {
    Log "Enabling Remote Desktop..."
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
        -Name "fDenyTSConnections" -Value 0

    Log "Requiring Network Level Authentication (more secure)..."
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' `
        -Name "UserAuthentication" -Value 1

    Log "Enabling firewall rule group 'Remote Desktop'..."
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue

    Ok "RDP enabled."
}

# ---------- 3. Firewall: ZeroTier UDP port ----------
function Configure-Firewall {
    Log "Opening UDP 9993 for ZeroTier..."
    $existing = Get-NetFirewallRule -DisplayName "ZeroTier" -ErrorAction SilentlyContinue
    if (-not $existing) {
        New-NetFirewallRule -DisplayName "ZeroTier" -Direction Inbound -Protocol UDP `
            -LocalPort 9993 -Action Allow | Out-Null
        Ok "Firewall rule for ZeroTier added."
    }
    else {
        Ok "Firewall rule for ZeroTier already exists."
    }
}

# ---------- 4. Enable + start the ZeroTier service ----------
function Start-ZeroTierService {
    Log "Making sure ZeroTier One service is running..."
    Set-Service -Name "ZeroTierOneService" -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name "ZeroTierOneService" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    Ok "ZeroTier service started."
}

# ---------- 5. Join the network ----------
function Join-Network {
    Log "Joining ZeroTier network $NetworkID ..."
    & zerotier-cli join $NetworkID
    Ok "Join request sent. Now go authorize this device at:"
    Ok "  https://my.zerotier.com/network/$NetworkID"
}

# ---------- 6. Summary ----------
function Print-Summary {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host " Setup summary"
    Write-Host "============================================================"
    Write-Host " Computer name  : $env:COMPUTERNAME"
    Write-Host " Windows user   : $env:USERNAME"
    try { $info = & zerotier-cli info } catch { $info = "unavailable" }
    Write-Host " ZeroTier node  : $info"
    Write-Host " ZeroTier nets  :"
    try { & zerotier-cli listnetworks | ForEach-Object { "   $_" } } catch { Write-Host "   (none yet / daemon still starting)" }
    Write-Host " RDP enabled    : Yes (port 3389)"
    Write-Host "============================================================"
    Write-Host ""
    Ok "Done. Once you've authorized the device in ZeroTier Central,"
    Ok "find its ZeroTier IP with: zerotier-cli listnetworks"
    Ok "Then from another device on the same ZeroTier network, open"
    Ok "Windows' Remote Desktop Connection app and connect to that IP."
    Warn "Tip: set a strong password on this Windows account if it doesn't have one --"
    Warn "RDP will refuse blank-password accounts, and you don't want a weak one exposed."
}

# ---------- main ----------
Install-ZeroTier
Enable-RDP
Configure-Firewall
Start-ZeroTierService
Join-Network
Print-Summary
