#!/usr/bin/env bash
#
# setup-zt-ssh.sh - install ZeroTier + OpenSSH on Debian/Ubuntu, Fedora, Arch.
# SSH uses password login and is reachable ONLY through the ZeroTier interface
# (the firewall blocks port 22 on every other interface, including the LAN).
#
# Run straight from GitHub:
#   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/taxin-404/help/main/linux/setup-zt-ssh.sh)"
#
# Different network ID:
#   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/taxin-404/help/main/linux/setup-zt-ssh.sh)" _ <NETWORK_ID>
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

# name of the ZeroTier network interface (needed for the firewall rule)
ZT_DEV=""
for _ in $(seq 15); do
  ZT_DEV="$(zerotier-cli listnetworks | awk -v n="$NETWORK" '$3==n {print $(NF-1); exit}' || true)"
  [[ -n "$ZT_DEV" && "$ZT_DEV" != "-" ]] && break
  sleep 1
done
[[ -n "$ZT_DEV" && "$ZT_DEV" != "-" ]] || die "could not find the ZeroTier interface name"

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

# --- Firewall: SSH only on the ZeroTier interface ---------------------------
restrict_ssh_to_zerotier() {
  local use_firewalld=0 zones

  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    use_firewalld=1
  elif [[ "$DISTRO" == "fedora" ]]; then
    dnf install -y firewalld
    systemctl enable --now firewalld
    use_firewalld=1
  fi

  if (( use_firewalld )); then
    # firewalld: a dedicated zone for the ZeroTier interface that allows ssh,
    # and ssh removed from the default zone (LAN)
    zones="$(firewall-cmd --permanent --get-zones)"
    if [[ " $zones " != *" zerotier "* ]]; then
      firewall-cmd --permanent --new-zone=zerotier
    fi
    firewall-cmd --permanent --zone=zerotier --add-service=ssh
    firewall-cmd --permanent --zone=zerotier --change-interface="$ZT_DEV"
    firewall-cmd --permanent --remove-service=ssh || true
    firewall-cmd --permanent --add-port=9993/udp    # ZeroTier's own port
    firewall-cmd --reload
    return 0
  fi

  # ufw (Ubuntu/Debian/Arch)
  if ! command -v ufw >/dev/null 2>&1; then
    case "$DISTRO" in
      arch)   pacman -S --needed --noconfirm ufw ;;
      debian) apt-get install -y ufw ;;
    esac
  fi

  # remove any rule that opens SSH on all interfaces
  for r in 22/tcp 22 ssh OpenSSH; do
    ufw delete allow "$r" >/dev/null 2>&1 || true
  done

  ufw default deny incoming
  ufw allow in on "$ZT_DEV" to any port 22 proto tcp
  ufw allow 9993/udp    # ZeroTier's own port
  ufw --force enable
  systemctl enable ufw
}
restrict_ssh_to_zerotier

# --- Show the result --------------------------------------------------------
zerotier-cli listnetworks
