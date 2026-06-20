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
#   5. Opens the firewall for SSH (22) and ZeroTier (9993/udp) if a known
#      firewall manager is active (ufw / firewalld / iptables-via-nft skipped safely)
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

# ---------- arg parsing ----------
NETWORK_ID=""
JOIN=true
for arg in "$@"; do
  case "$arg" in
    --no-join) JOIN=false ;;
    *) NETWORK_ID="$arg" ;;
  esac
done

require_root "$@"

# ---------- distro detection ----------
detect_distro() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    ID_LIKE_LOWER="${ID_LIKE:-} ${ID:-}"
  else
    ID_LIKE_LOWER=""
  fi

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
      log "Updating package database (pacman -Sy)..."
      pacman -Sy --noconfirm
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
  # service unit name differs slightly across distros
  if systemctl list-unit-files | grep -q '^sshd.service'; then
    systemctl enable --now sshd.service
  elif systemctl list-unit-files | grep -q '^ssh.service'; then
    systemctl enable --now ssh.service
  else
    warn "Could not find sshd.service or ssh.service unit — check your openssh install."
  fi
  ok "Services enabled."
}

# ---------- firewall ----------
configure_firewall() {
  if command -v ufw &>/dev/null && ufw status | grep -qi active; then
    log "ufw detected and active — opening ports 22/tcp and 9993/udp..."
    ufw allow 22/tcp
    ufw allow 9993/udp
    ok "ufw rules added."
  elif command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
    log "firewalld detected and active — opening ports 22/tcp and 9993/udp..."
    firewall-cmd --permanent --add-service=ssh
    firewall-cmd --permanent --add-port=9993/udp
    firewall-cmd --reload
    ok "firewalld rules added."
  else
    warn "No active ufw/firewalld detected — skipping firewall changes."
    warn "If you use a custom iptables/nftables setup, manually allow tcp/22 and udp/9993."
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
    read -rp "Enter your ZeroTier Network ID to join (leave blank to skip): " NETWORK_ID
  fi

  if [[ -z "$NETWORK_ID" ]]; then
    warn "No network ID provided — skipping join. Join later with:"
    warn "  sudo zerotier-cli join <NETWORK_ID>"
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
