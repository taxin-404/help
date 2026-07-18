#requires -RunAsAdministrator
<#
.SYNOPSIS
  zerossh-windows.ps1  (v2 — Home edition support)
  Installs ZeroTier, opens the firewall, joins your ZeroTier network, and sets
  up remote-control access:
    - Windows Pro/Enterprise/Education -> enables built-in Remote Desktop (RDP)
    - Windows Home                     -> installs TightVNC server instead,
                                           since Home has no RDP server

.USAGE
  powershell -ExecutionPolicy Bypass -File .\zerossh-windows.ps1 `
      -NetworkID <your16charID> [-VncPassword <password>]

  -VncPassword is only required if this PC is running Windows Home.
  (TightVNC passwords are capped at 8 characters — anything longer gets
  truncated by the VNC protocol itself, not by this script.)

  Easiest: just double-click setup-remote.bat after editing the two
  variables inside it.
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{16}$')]
    [string]$NetworkID,

    [string]$VncPassword = ""
)

$ErrorActionPreference = "Stop"

function Log  ($msg) { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Ok   ($msg) { Write-Host "[OK] $msg" -ForegroundColor Green }
function Warn ($msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Err  ($msg) { Write-Host "[X] $msg" -ForegroundColor Red }

# ---------- 0. Detect edition ----------
$osCaption = (Get-CimInstance Win32_OperatingSystem).Caption
$IsHome = $osCaption -match "Home"

Log "Detected Windows edition: $osCaption"
if ($IsHome) {
    Warn "Home edition detected -> will use TightVNC (no built-in RDP server on Home)."
    if ([string]::IsNullOrWhiteSpace($VncPassword)) {
        Err "This is Windows Home, so you must supply -VncPassword <password>."
        Err "Re-run: powershell -ExecutionPolicy Bypass -File .\zerossh-windows.ps1 -NetworkID $NetworkID -VncPassword yourpassword"
        exit 1
    }
}
else {
    Ok "Pro/Enterprise/Education detected -> will use built-in Remote Desktop (RDP)."
}

# ---------- 1. Install ZeroTier ----------
function Install-ZeroTier {
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

    $ztPath = "C:\Program Files (x86)\ZeroTier\One"
    if (Test-Path $ztPath) {
        $env:Path += ";$ztPath"
    }
    Ok "ZeroTier install step complete."
}

# ---------- 2a. Enable RDP (Pro/Enterprise/Education) ----------
function Enable-RDP {
    Log "Enabling Remote Desktop..."
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
        -Name "fDenyTSConnections" -Value 0

    Log "Requiring Network Level Authentication (more secure)..."
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' `
        -Name "UserAuthentication" -Value 1

    Log "Enabling firewall rule group 'Remote Desktop'..."
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue

    Ok "RDP enabled (port 3389)."
}

# ---------- 2b. Install + configure TightVNC (Home) ----------
function Install-TightVNC {
    $vncExisting = Get-Service -Name "tvnserver" -ErrorAction SilentlyContinue
    $msi = "$env:TEMP\tightvnc.msi"

    if (-not $vncExisting) {
        Log "Downloading TightVNC server..."
        Invoke-WebRequest -Uri "https://www.tightvnc.com/download/2.8.88/tightvnc-2.8.88-gpl-setup-64bit.msi" -OutFile $msi

        Log "Installing TightVNC silently with your password set..."
        $msiArgs = @(
            "/i", "`"$msi`"", "/quiet", "/norestart",
            "ADDLOCAL=Server",
            "SERVER_REGISTER_AS_SERVICE=1",
            "SERVER_START_ON_INSTALL=1",
            "SERVER_ADD_FIREWALL_EXCEPTION=1",
            "SET_USEVNCAUTHENTICATION=1", "VALUE_OF_USEVNCAUTHENTICATION=1",
            "SET_PASSWORD=1", "VALUE_OF_PASSWORD=$VncPassword"
        )
        Start-Process msiexec.exe -ArgumentList $msiArgs -Wait
        Ok "TightVNC installed."
    }
    else {
        Ok "TightVNC already installed — updating password..."
        Warn "TightVNC service already exists. If you need to change the password,"
        Warn "open 'TightVNC Server' from the Start Menu -> right-click tray icon -> Configuration."
    }

    Log "Opening firewall for VNC (port 5900)..."
    $existing = Get-NetFirewallRule -DisplayName "TightVNC" -ErrorAction SilentlyContinue
    if (-not $existing) {
        New-NetFirewallRule -DisplayName "TightVNC" -Direction Inbound -Protocol TCP `
            -LocalPort 5900 -Action Allow | Out-Null
    }
    Ok "TightVNC ready on port 5900."
}

# ---------- 3. Firewall: ZeroTier UDP port ----------
function Configure-ZTFirewall {
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
    Write-Host " Windows edition: $osCaption"
    try { $info = & zerotier-cli info } catch { $info = "unavailable" }
    Write-Host " ZeroTier node  : $info"
    Write-Host " ZeroTier nets  :"
    try { & zerotier-cli listnetworks | ForEach-Object { "   $_" } } catch { Write-Host "   (none yet / daemon still starting)" }
    if ($IsHome) {
        Write-Host " Remote access  : TightVNC on port 5900"
    } else {
        Write-Host " Remote access  : RDP on port 3389"
    }
    Write-Host "============================================================"
    Write-Host ""
    Ok "Done. Once you've authorized the device in ZeroTier Central,"
    Ok "find its ZeroTier IP with: zerotier-cli listnetworks"
    if ($IsHome) {
        Ok "Connect from another device using any VNC viewer app (e.g. TightVNC Viewer,"
        Ok "RealVNC Viewer) pointed at that ZeroTier IP, port 5900, with the password you set."
    } else {
        Ok "Connect from another device using Windows' Remote Desktop Connection app,"
        Ok "pointed at that ZeroTier IP."
    }
    Warn "Make sure your Windows account has a real (non-blank) password."
}

# ---------- main ----------
Install-ZeroTier
if ($IsHome) { Install-TightVNC } else { Enable-RDP }
Configure-ZTFirewall
Start-ZeroTierService
Join-Network
Print-Summary
