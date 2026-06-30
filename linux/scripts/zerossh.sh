#!/usr/bin/env bash
#
# setup-zerotier-ssh.sh
# Installs and configures ZeroTier + OpenSSH on the "big three" Linux families:
#   - Arch / Arch-based   (pacman)   -> Omarchy, Arch, Manjaro, CachyOS, EndeavourOS...
#   - Debian / Ubuntu     (apt)      -> Debian, Ubuntu, Mint, Raspberry Pi OS...
#   - Fedora / RHEL       (dnf/yum)  -> Fedora, RHEL, Rocky, AlmaLinux, CentOS Stream...
#
# What it does:
#   1. Detects the distro family
#   2. Installs zerotier-one + openssh
#   3. Enables + starts zerotier-one.service and sshd.service
#   4. Optionally joins a ZeroTier network (pass network ID as $1, or it'll prompt)
#   5. Opens the firewall for SSH (22) and ZeroTier (9993/udp) via:
#        - ufw          (Ubuntu/Mint, if installed)
#        - firewalld    (Fedora/RHEL, if installed)
#   6. Prints the ZeroTier node ID + join status + local IP info at the end
#
# Usage:
#   sudo ./setup-zerotier-ssh.sh                  # interactive, will ask for network ID
#   sudo ./setup-zerotier-ssh.sh <NETWORK_ID>      # non-interactive join
#   sudo ./setup-zerotier-ssh.sh --no-join         # install/enable only, skip join
#
set -euo pipefail

# ---------- helpers ----------
c_reset='\033[0m'; c_green='\033[1;32m'; c_yellow='\033[1;33m'; c_red='\033[1;31m'; c_cyan='\033[1;36m'
log()  { echo -e "${c_cyan}[*]${c_reset} $*"; }
ok()   { echo -e "${c_green}[OK]${c_reset} $*"; }
warn() { echo -e "${c_yellow}[!]${c_reset} $*"; }
err()  { echo -e "${c_red}[X]${c_reset} $*" >&2; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "This script needs root privileges. Re-run with: sudo $0 $*"
    exit 1
  fi
}

# ---------- defaults ----------
DEFAULT_NETWORK_ID="633e31d8a2e3401d"

# ---------- arg parsing ----------
NETWORK_ID=""
JOIN=true
for arg in "$@"; do
  case "$arg" in
    --no-join) JOIN=false ;;
    *) NETWORK_ID="$arg" ;;
  esac
done

if [[ -z "$NETWORK_ID" && "$JOIN" == true ]]; then
  NETWORK_ID="$DEFAULT_NETWORK_ID"
fi

require_root "$@"

# ---------- distro detection ----------
detect_distro() {
  if command -v pacman &>/dev/null; then
    echo "arch"
  elif command -v apt-get &>/dev/null; then
    echo "debian"
  elif command -v dnf &>/dev/null; then
    echo "fedora"
  elif command -v yum &>/dev/null; then
    echo "fedora"
  else
    echo "unknown"
  fi
}

DISTRO=$(detect_distro)
log "Detected distro family: ${c_yellow}${DISTRO}${c_reset}"

if [[ "$DISTRO" == "unknown" ]]; then
  err "Could not detect a supported package manager (pacman / apt / dnf / yum)."
  err "Supported: Arch-based, Debian/Ubuntu-based, Fedora/RHEL-based."
  exit 1
fi

# ---------- install ----------
install_packages() {
  case "$DISTRO" in
    arch)
      # IMPORTANT: plain `pacman -Sy` followed by a later `pacman -S` is the
      # classic "partial upgrade" foot-gun on Arch — it can pull in a package
      # built against newer libs than what's currently installed, breaking
      # the system. Always sync AND upgrade together (-Syu) before installing
      # anything new.
      log "Syncing and upgrading package database (pacman -Syu)..."
      pacman -Syu --noconfirm
      log "Installing zerotier-one and openssh..."
      pacman -S --needed --noconfirm zerotier-one openssh
      ;;
    debian)
      log "Updating apt cache..."
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -y
      log "Installing openssh-server..."
      apt-get install -y openssh-server curl
      if ! command -v zerotier-cli &>/dev/null; then
        log "Installing ZeroTier via official install script (not in default apt repos)..."
        curl -s https://install.zerotier.com | bash
      else
        ok "zerotier-cli already present."
      fi
      ;;
    fedora)
      PM="dnf"
      command -v dnf &>/dev/null || PM="yum"
      log "Installing openssh-server via ${PM}..."
      "$PM" install -y openssh-server curl
      if ! command -v zerotier-cli &>/dev/null; then
        log "Installing ZeroTier via official install script (not in default dnf/yum repos)..."
        curl -s https://install.zerotier.com | bash
      else
        ok "zerotier-cli already present."
      fi
      ;;
  esac
  ok "Package installation step complete."
}

# ---------- enable services ----------
enable_services() {
  log "Enabling and starting ZeroTier..."
  systemctl enable --now zerotier-one.service

  log "Enabling and starting SSH..."
  local units
  units="$(systemctl list-unit-files --no-legend --no-pager 2>/dev/null || true)"

  if echo "$units" | grep -q '^sshd\.service'; then
    systemctl enable --now sshd.service
  elif echo "$units" | grep -q '^ssh\.service'; then
    systemctl enable --now ssh.service
  else
    if systemctl enable --now ssh.service 2>/dev/null; then
      :
    elif systemctl enable --now sshd.service 2>/dev/null; then
      :
    else
      warn "Could not find sshd.service or ssh.service unit — check your openssh install."
    fi
  fi
  ok "Services enabled."
}

# ---------- firewall ----------
# Handles the two managed firewalls relevant to our "big three" distros:
#   - ufw        -> default on Ubuntu/Mint (often installed but inactive)
#   - firewalld  -> default + active out-of-the-box on Fedora/RHEL
configure_firewall() {
  local handled=false

  if command -v ufw &>/dev/null; then
    if ufw status | head -n1 | grep -qi "Status: active"; then
      log "ufw is active — opening ports 22/tcp and 9993/udp..."
      ufw allow 22/tcp comment 'SSH'
      ufw allow 9993/udp comment 'ZeroTier'
      ok "ufw rules added (idempotent — safe to re-run)."
    else
      ok "ufw is installed but inactive — no rules needed, traffic isn't being filtered."
    fi
    handled=true
  fi

  if command -v firewall-cmd &>/dev/null; then
    if [[ "$(firewall-cmd --state 2>/dev/null)" == "running" ]]; then
      log "firewalld is active — opening ports 22/tcp and 9993/udp..."
      firewall-cmd --permanent --add-service=ssh
      firewall-cmd --permanent --add-port=9993/udp
      if firewall-cmd --reload; then
        ok "firewalld rules added and reloaded."
      else
        err "firewalld reload failed — rules were staged but not applied. Check 'firewall-cmd --get-active-zones'."
      fi
    else
      ok "firewalld is installed but not running — no rules needed, traffic isn't being filtered."
    fi
    handled=true
  fi

  if [[ "$handled" == false ]]; then
    warn "Neither ufw nor firewalld is installed — nothing to configure."
    warn "Ports should already be reachable unless something else is filtering traffic."
  fi
}

# ---------- join network ----------
join_network() {
  if [[ "$JOIN" == false ]]; then
    warn "Skipping ZeroTier network join (--no-join given)."
    return
  fi

  if [[ -z "$NETWORK_ID" ]]; then
    echo
    if [[ -r /dev/tty ]]; then
      read -rp "Enter your ZeroTier Network ID to join (leave blank to skip): " NETWORK_ID < /dev/tty
    else
      warn "No interactive terminal available to prompt for a Network ID."
      warn "Re-run with the ID as an argument instead, e.g.:"
      warn "  curl -fsSL <script-url> | sudo bash -s -- <NETWORK_ID>"
    fi
  fi

  if [[ -z "$NETWORK_ID" ]]; then
    warn "No network ID provided — skipping join. Join later with:"
    warn "  sudo zerotier-cli join <NETWORK_ID>"
    return
  fi

  if ! [[ "$NETWORK_ID" =~ ^[0-9a-fA-F]{16}$ ]]; then
    err "'$NETWORK_ID' doesn't look like a valid ZeroTier Network ID (should be 16 hex characters)."
    err "Skipping join — run later with: sudo zerotier-cli join <NETWORK_ID>"
    return
  fi

  log "Joining ZeroTier network ${NETWORK_ID}..."
  zerotier-cli join "$NETWORK_ID"
  ok "Join request sent. Remember to authorize this device in ZeroTier Central:"
  ok "  https://my.zerotier.com/network/${NETWORK_ID}"
}

# ---------- summary ----------
print_summary() {
  echo
  echo "============================================================"
  echo " Setup summary"
  echo "============================================================"
  echo " Distro family : $DISTRO"
  echo " ZeroTier node : $(zerotier-cli info 2>/dev/null || echo 'unavailable')"
  echo " ZeroTier nets :"
  zerotier-cli listnetworks 2>/dev/null | sed 's/^/   /' || echo "   (none yet / daemon still starting)"
  echo " SSH service   : $(systemctl is-active sshd.service 2>/dev/null || systemctl is-active ssh.service 2>/dev/null || echo 'unknown')"
  echo " SSH listening : $(ss -tlnp 2>/dev/null | grep ':22 ' || echo 'check manually with: ss -tlnp | grep 22')"
  echo "============================================================"
  echo
  ok "Done. If you just joined a network, authorize the device at:"
  echo "    https://my.zerotier.com/network/<your-network-id>"
  ok "Then test SSH from another ZeroTier-connected machine with:"
  echo "    ssh $(logname 2>/dev/null || echo '<user>')@<zerotier-ip>"
}

# ---------- main ----------
install_packages
enable_services
configure_firewall
join_network
print_summary
