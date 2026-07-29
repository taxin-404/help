#!/usr/bin/env bash
#
# zerossh.sh
# Installs and configures ZeroTier + OpenSSH on the "big three" Linux families:
#   - Arch / Arch-based   (pacman)   -> Omarchy, Arch, Manjaro, CachyOS, EndeavourOS...
#   - Debian / Ubuntu     (apt)      -> Debian, Ubuntu, Mint, Raspberry Pi OS...
#   - Fedora / RHEL       (dnf/yum)  -> Fedora, RHEL, Rocky, AlmaLinux, CentOS Stream...
#
# What it does:
#   1. Detects the distro family
#   2. Installs zerotier-one + openssh
#   3. Enables + starts zerotier-one.service and sshd.service
#   4. Joins a ZeroTier network: uses $1 if given, otherwise falls back to the
#      built-in DEFAULT_NETWORK_ID below (pass --no-join to skip joining entirely)
#   5. Opens the firewall for SSH (22) and ZeroTier (9993/udp) via:
#        - ufw          (Ubuntu/Mint, if installed)
#        - firewalld    (Fedora/RHEL, if installed)
#   6. Prints the ZeroTier node ID + join status + local IP info at the end
#
# Usage:
#   sudo ./zerossh.sh                  # joins the built-in default network
#   sudo ./zerossh.sh <NETWORK_ID>      # joins a specific network instead
#   sudo ./zerossh.sh --no-join         # install/enable only, skip join
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
  warn "No Network ID given — defaulting to built-in network ${DEFAULT_NETWORK_ID}."
fi

require_root "$@"

# ---------- distro detection ----------
detect_distro() {
  if command -v pacman &>/dev/null; then
    echo "arch"
  elif command -v apt-get &>/dev/null; then
    echo "debian"
  elif command -v dnf &>/dev/null || command -v yum &>/dev/null; then
    echo "fedora"
  else
    echo "unknown"
  fi
}

DISTRO=$(detect_distro)
log "Detected distro family: ${c_yellow}${DISTRO}${c_reset}"

if [[ "$DISTRO" == "unknown" ]]; then
  err "Could not detect a supported package manager."
  exit 1
fi

# ---------- install ----------
install_packages() {
  case "$DISTRO" in
    arch)
      log "Installing zerotier-one and openssh via pacman..."
      pacman -Sy --needed --noconfirm zerotier-one openssh
      ;;
    debian)
      log "Updating apt cache and installing packages..."
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -y
      apt-get install -y openssh-server curl ufw
      if ! command -v zerotier-cli &>/dev/null; then
        log "Installing ZeroTier via official script..."
        curl -s https://install.zerotier.com | bash
      fi
      ;;
    fedora)
      PM="dnf"
      command -v dnf &>/dev/null || PM="yum"
      log "Installing openssh-server via ${PM}..."
      "$PM" install -y openssh-server curl
      if ! command -v zerotier-cli &>/dev/null; then
        curl -s https://install.zerotier.com | bash
      fi
      ;;
  esac
  ok "Package installation complete."
}

# ---------- enable services ----------
enable_services() {
  log "Enabling and starting ZeroTier..."
  systemctl enable --now zerotier-one.service

  log "Enabling and starting SSH service..."
  # Try sshd.service first (Arch/Fedora), then ssh.service (Debian/Ubuntu)
  if systemctl enable --now sshd.service 2>/dev/null; then
    ok "Enabled sshd.service"
  elif systemctl enable --now ssh.service 2>/dev/null; then
    ok "Enabled ssh.service"
  else
    warn "Could not automatically enable SSH service. Please check manually."
  fi
}

# ---------- firewall ----------
configure_firewall() {
  if command -v ufw &>/dev/null; then
    if ufw status | grep -qi "Status: active"; then
      log "ufw is active — allowing SSH and ZeroTier..."
      ufw allow 22/tcp comment 'SSH'
      ufw allow 9993/udp comment 'ZeroTier'
      ok "ufw rules added."
    fi
  fi

  if command -v firewall-cmd &>/dev/null; then
    if firewall-cmd --state &>/dev/null; then
      log "firewalld is active — opening SSH and ZeroTier..."
      firewall-cmd --permanent --add-service=ssh
      firewall-cmd --permanent --add-port=9993/udp
      firewall-cmd --reload
      ok "firewalld rules added."
    fi
  fi
}

# ---------- join network ----------
join_network() {
  if [[ "$JOIN" == false ]]; then
    warn "Skipping ZeroTier network join."
    return
  fi

  log "Waiting for ZeroTier daemon socket..."
  for i in {1..10}; do
    if zerotier-cli info &>/dev/null; then break; fi
    sleep 1
  done

  log "Joining ZeroTier network ${NETWORK_ID}..."
  zerotier-cli join "$NETWORK_ID"
  ok "Join request sent."
}

# ---------- summary ----------
print_summary() {
  echo
  echo "============================================================"
  echo " Setup Summary"
  echo "============================================================"
  echo " Distro family : $DISTRO"
  echo " ZeroTier node : $(zerotier-cli info 2>/dev/null || echo 'unavailable')"
  echo " SSH Status    : $(systemctl is-active sshd 2>/dev/null || systemctl is-active ssh 2>/dev/null || echo 'inactive')"
  echo "============================================================"
}

# ---------- main ----------
install_packages
enable_services
configure_firewall
join_network
print_summary
