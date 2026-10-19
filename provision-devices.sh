#!/usr/bin/env bash
#
# provision-devices.sh
# Sets up on the target machine:
#   1. ZeroTier (install, join, wait for controller authorization)
#   2. SSH (key-only, default: reachable ONLY via the ZeroTier interface)
#
# The SSH service is what lets you tunnel in later (ssh -L 5901:... for VNC etc.).
# It never asks for or collects any password, username, or key.
# Run as root, on the machine being set up. Safe to re-run (idempotent).
#
# Optional config: /etc/provision-devices.conf  (see provision-devices.conf.example)

set -euo pipefail

CONFIG="${PROVISION_CONFIG:-/etc/provision-devices.conf}"
LOG="${PROVISION_LOG:-/var/log/provision-devices.log}"

log() { printf '[%s] %s\n' "$(date -Is)" "$*"; }
die() { log "ERROR: $*"; exit 1; }

[[ $EUID -eq 0 ]] || die "must run as root"
if [[ -r "$CONFIG" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG"
    log "loaded config: $CONFIG"
fi

# --- Settings (env or config file override) ---------------------------------
ZEROTIER_NETWORK="${ZEROTIER_NETWORK:?ZEROTIER_NETWORK must be set (env or config)}"
SSH_BIND="${SSH_BIND:-zt}"              # zt = only via ZeroTier | any | off
SSH_PASSWORD_AUTH="${SSH_PASSWORD_AUTH:-no}"
SSH_AUTHORIZED_KEYS_FILE="${SSH_AUTHORIZED_KEYS_FILE:-}"
PROVISION_USER="${PROVISION_USER:-${SUDO_USER:-}}"

log "starting provisioning"

# --- Distro -----------------------------------------------------------------
detect_distro() {
    local id="" like=""
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        id="${ID:-}"; like="${ID_LIKE:-}"
    fi
    case " ${id} ${like} " in
        *" arch "*)                echo arch ;;
        *" debian "*|*" ubuntu "*) echo debian ;;
        *" fedora "*)              echo fedora ;;
        *)                         echo unknown ;;
    esac
}
DISTRO="$(detect_distro)"
[[ "$DISTRO" != "unknown" ]] || die "unsupported distribution"
log "distro: $DISTRO"

TARGET_USER="${PROVISION_USER:-}"
if [[ -z "$TARGET_USER" ]]; then
    for u in taxin root; do id -u "$u" >/dev/null 2>&1 && TARGET_USER="$u" && break; done
fi
[[ -n "$TARGET_USER" ]] || die "no target user found (set PROVISION_USER)"
getent passwd "$TARGET_USER" >/dev/null || die "user not found: $TARGET_USER"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TARGET_GROUP="$(id -gn "$TARGET_USER")"
log "target user: $TARGET_USER ($TARGET_HOME)"

# --- Package helper ---------------------------------------------------------
APT_UPDATED=0
install_pkgs() {
    log "installing: $*"
    case "$DISTRO" in
        arch)
            pacman -S --needed --noconfirm "$@"
            ;;
        debian)
            if (( APT_UPDATED == 0 )); then
                DEBIAN_FRONTEND=noninteractive apt-get update -y
                APT_UPDATED=1
            fi
            DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
            ;;
        fedora)
            dnf install -y "$@"
            ;;
    esac
}

# --- 1. ZeroTier ------------------------------------------------------------
if ! command -v zerotier-one >/dev/null 2>&1; then
    case "$DISTRO" in
        arch) install_pkgs zerotier-one ;;
        *)    curl -fsSL https://install.zerotier.com | bash ;;
    esac
fi
command -v zerotier-one >/dev/null 2>&1 || die "ZeroTier installation failed"
systemctl enable --now zerotier-one

if ! zerotier-cli listnetworks 2>/dev/null | awk '{print $3}' | grep -qx "$ZEROTIER_NETWORK"; then
    log "joining network $ZEROTIER_NETWORK"
    zerotier-cli join "$ZEROTIER_NETWORK"
else
    log "already joined $ZEROTIER_NETWORK"
fi

ZT_STATUS=""
for _ in {1..45}; do
    ZT_STATUS="$(zerotier-cli listnetworks 2>/dev/null \
        | awk -v net="$ZEROTIER_NETWORK" '$3 == net {print $6; exit}')"
    [[ "$ZT_STATUS" == "OK" ]] && break
    sleep 2
done

if [[ "$ZT_STATUS" == "OK" ]]; then
    ZT_IP="$(zerotier-cli listnetworks | awk -v net="$ZEROTIER_NETWORK" '$3 == net {print $4}' | cut -d/ -f1 | head -1)"
    log "ZeroTier network up - this node's ZT IP: ${ZT_IP:-unknown}"
else
    log "WARNING: network status '${ZT_STATUS:-none}'"
    log "authorize this node in my.zerotier.com (address: $(zerotier-cli info | awk '{print $3}')), then re-run"
fi

# --- 2. SSH -----------------------------------------------------------------
if [[ "$SSH_BIND" != "off" ]]; then
    case "$DISTRO" in
        arch)   install_pkgs openssh;         SSH_SERVICE="sshd" ;;
        debian) install_pkgs openssh-server;  SSH_SERVICE="ssh"  ;;
        fedora) install_pkgs openssh-server;  SSH_SERVICE="sshd" ;;
    esac
    systemctl enable --now "$SSH_SERVICE"

    install -d -m 0755 /etc/ssh/sshd_config.d
    if ! grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config; then
        cp -a /etc/ssh/sshd_config "/etc/ssh/sshd_config.bak.$(date +%s)"
        { printf 'Include /etc/ssh/sshd_config.d/*.conf\n'; cat /etc/ssh/sshd_config; } \
            > /etc/ssh/sshd_config.new
        mv /etc/ssh/sshd_config.new /etc/ssh/sshd_config
        chmod 0644 /etc/ssh/sshd_config
        log "added Include directive to sshd_config"
    fi

    SSHD_DROPIN=/etc/ssh/sshd_config.d/99-provision-devices.conf
    cat > "$SSHD_DROPIN" <<EOF
# Managed by provision-devices.sh
PubkeyAuthentication yes
PasswordAuthentication ${SSH_PASSWORD_AUTH}
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF

    sshd -t || die "sshd config test failed"
    systemctl reload "$SSH_SERVICE" 2>/dev/null || systemctl restart "$SSH_SERVICE"
    log "sshd configured (bind=$SSH_BIND password_auth=$SSH_PASSWORD_AUTH)"

    # Keys are PUBLIC - installing them collects nothing.
    if [[ -n "$SSH_AUTHORIZED_KEYS_FILE" ]]; then
        [[ -r "$SSH_AUTHORIZED_KEYS_FILE" ]] || die "cannot read $SSH_AUTHORIZED_KEYS_FILE"
        install -d -m 0700 -o "$TARGET_USER" -g "$TARGET_GROUP" "$TARGET_HOME/.ssh"
        while IFS= read -r key || [[ -n "$key" ]]; do
            [[ -z "$key" || "$key" == \#* ]] && continue
            if ! grep -qxF -- "$key" "$TARGET_HOME/.ssh/authorized_keys" 2>/dev/null; then
                printf '%s\n' "$key" >> "$TARGET_HOME/.ssh/authorized_keys"
                log "installed public key for $TARGET_USER"
            fi
        done < "$SSH_AUTHORIZED_KEYS_FILE"
        chown "$TARGET_USER:$TARGET_GROUP" "$TARGET_HOME/.ssh/authorized_keys"
        chmod 0600 "$TARGET_HOME/.ssh/authorized_keys"
    else
        log "SSH_AUTHORIZED_KEYS_FILE not set - make sure a key is installed"
    fi

    # Firewall: with SSH_BIND=zt, port 22 is reachable only through ZeroTier.
    if command -v ufw >/dev/null 2>&1 && ufw status | head -1 | grep -q "active"; then
        if [[ "$SSH_BIND" == "zt" ]]; then
            if ! ufw status | grep -q "zt+"; then
                ufw allow in on zt+ to any port 22 proto tcp comment 'provision ssh via zerotier'
            fi
            log "ufw: ssh allowed only on zt+ interfaces"
        else
            ufw allow openssh 2>/dev/null || ufw allow 22/tcp
            log "ufw: ssh allowed on all interfaces (SSH_BIND=any)"
        fi
    else
        log "ufw not active - SSH reachable on all interfaces; restrict manually if wanted"
    fi
fi

log "provisioning complete"
