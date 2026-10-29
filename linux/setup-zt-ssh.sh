#!/usr/bin/env bash
#
# setup-zt-ssh.sh - install ZeroTier + OpenSSH (password login) on Debian/Ubuntu, Fedora, Arch.
#
# Run straight from GitHub:
#   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/taxin-404/help/main/setup-zt-ssh.sh)"
#
# Different network ID:
#   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/taxin-404/help/main/setup-zt-ssh.sh)" _ <NETWORK_ID>
#
# Safe to re-run.

set -euo pipefail

NETWORK="${1:-${ZEROTIER_NETWORK:-633e31d8a2e3401d}}"

die() { echo "ERROR: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run as root (use sudo)"
[[ "$NETWORK" =~ ^[0-9a-f]{16}$ ]] || die "invalid ZeroTier network ID: $NETWORK"

# --- Distro -----------------------------------------------------------------
[[ -r /etc/os-release ]] || die "cannot read /etc/os-release"
# shellcheck disable=SC1091
. /etc/os-release
case " ${ID:-} ${ID_LIKE:-} " in
  *" arch "*)                DISTRO=arch;   SSH_SVC=sshd ;;
  *" debian "*|*" ubuntu "*) DISTRO=debian; SSH_SVC=ssh  ;;
  *" fedora "*|*" rhel "*)   DISTRO=fedora; SSH_SVC=sshd ;;
  *) die "unsupported distro: ${ID:-unknown}" ;;
esac

# --- Packages ---------------------------------------------------------------
case "$DISTRO" in
  arch)
    pacman -S --needed --noconfirm openssh curl zerotier-one
    ;;
  debian)
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y openssh-server curl gnupg
    ;;
  fedora)
    dnf install -y openssh-server curl
    ;;
esac

# --- ZeroTier ---------------------------------------------------------------
if ! command -v zerotier-cli >/dev/null 2>&1; then
  curl -fsSL https://install.zerotier.com | bash
fi
command -v zerotier-cli >/dev/null 2>&1 || die "ZeroTier installation failed"

systemctl enable --now zerotier-one

# wait until the ZeroTier service answers
for _ in $(seq 15); do
  zerotier-cli info >/dev/null 2>&1 && break
  sleep 1
done

zerotier-cli join "$NETWORK"

# --- SSH (plain, password login) --------------------------------------------
install -d -m 0755 /etc/ssh/sshd_config.d
if ! grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/' /etc/ssh/sshd_config; then
  cp -a /etc/ssh/sshd_config "/etc/ssh/sshd_config.bak.$(date +%s)"
  sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
fi

# "00-" so it is read first (sshd uses the first value it sees for each option)
DROPIN=/etc/ssh/sshd_config.d/00-zt-setup.conf
cat > "$DROPIN" <<CONF
PasswordAuthentication yes
PubkeyAuthentication yes
CONF

mkdir -p -m 0755 /run/sshd
ssh-keygen -A
sshd -t || { rm -f "$DROPIN"; die "sshd config test failed (drop-in removed)"; }

systemctl enable --now "$SSH_SVC"
systemctl reload "$SSH_SVC" 2>/dev/null || systemctl restart "$SSH_SVC"

# --- Firewall: allow SSH (port 22) ------------------------------------------
open_ssh_firewall() {
  local out

  # ufw
  if command -v ufw >/dev/null 2>&1; then
    out="$(ufw status 2>/dev/null || true)"
    if [[ "$out" == "Status: active"* ]]; then
      ufw allow 22/tcp
      return 0
    fi
  fi

  # firewalld
  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --permanent --add-service=ssh
    firewall-cmd --reload
    return 0
  fi

  # raw iptables / nftables: only warn if incoming traffic is dropped by default
  out=""
  if command -v iptables >/dev/null 2>&1; then out+="$(iptables -S INPUT 2>/dev/null || true)"; fi
  if command -v nft >/dev/null 2>&1; then out+="$(nft list ruleset 2>/dev/null || true)"; fi
  if [[ "$out" == *"-P INPUT DROP"* || "$out" == *"policy drop"* ]]; then
    echo "WARNING: iptables/nftables drops incoming traffic by default. Allow TCP port 22 manually."
  fi
}
open_ssh_firewall

# --- Show the result --------------------------------------------------------
zerotier-cli listnetworks
