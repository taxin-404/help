# qBittorrent-nox Systemd Service

![Platform](https://img.shields.io/badge/platform-Linux-blue?logo=linux)
![Init System](https://img.shields.io/badge/init-systemd-orange)
![Service](https://img.shields.io/badge/service-qBittorrent--nox-green?logo=qbittorrent)
![WebUI Port](https://img.shields.io/badge/WebUI-port%208080-lightgrey)

A systemd service configuration to run `qbittorrent-nox` (headless qBittorrent) automatically on boot, with dependency on two specific mount points.

---

## ⚠️ Drive Ownership Notice

> **This repository is maintained by [`taxin`](https://github.com/taxin-404).**
>
> The drives mounted at `/mnt/nos` and `/mnt/backup` are **privately owned** by the repository owner. If you are cloning or adapting this config for your own system:
>
> - Replace the mount paths with your own
> - Replace `User=taxin` with your own Linux username
> - Do **not** assume these paths exist on any other machine
>
> These drives are required dependencies of this service. The service **will not start** without them.

---

## Table of Contents

- [Overview](#overview)
- [Requirements](#requirements)
- [Installation](#installation)
- [Service Configuration](#service-configuration)
- [Managing the Service](#managing-the-service)
- [WebUI Access](#webui-access)

---

## Overview

`qbittorrent-nox` is the headless (no GUI) version of qBittorrent. This setup runs it as a systemd service so it:

- Starts **automatically on boot**
- Waits for the **network and required drives** to be ready before starting
- Restarts **automatically on failure**
- Is accessible via a **browser-based WebUI** at `http://localhost:8080`

---

## Requirements

| Requirement | Details |
|---|---|
| OS | Any Linux distro with `systemd` |
| Package | `qbittorrent-nox` installed |
| User | A non-root user (here: `taxin`) |
| Mounts | `/mnt/nos` and `/mnt/backup` must be configured in `/etc/fstab` |

Install qBittorrent-nox if not already installed:

```bash
# Arch / Omarchy
sudo pacman -S qbittorrent-nox

# Ubuntu / Debian
sudo apt install qbittorrent-nox
```

---

## Installation

### 1. Create the service file

```bash
sudo nvim /etc/systemd/system/qbittorrent-nox.service
```

Paste the contents from [Service Configuration](#service-configuration) below, then save and exit with `:wq`.

### 2. Reload systemd and enable the service

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now qbittorrent-nox
```

### 3. Verify it is running

```bash
systemctl status qbittorrent-nox
```

Expected output:

```
● qbittorrent-nox.service - qBittorrent-nox service
     Loaded: loaded (/etc/systemd/system/qbittorrent-nox.service; enabled)
     Active: active (running)
```

---

## Service Configuration

```ini
[Unit]
Description=qBittorrent-nox service
After=network.target mnt-nos.mount mnt-backup.mount
Requires=mnt-nos.mount mnt-backup.mount
RequiresMountsFor=/mnt/nos /mnt/backup

[Service]
Type=simple
User=taxin
ExecStart=/usr/bin/qbittorrent-nox --webui-port=8080
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

### Field Reference

| Field | Purpose |
|---|---|
| `After=` | Ensures service starts only after network and both drives are ready |
| `Requires=` | Declares hard dependency on both mount units — service fails without them |
| `RequiresMountsFor=` | Additional path-based mount check |
| `User=` | Runs the process as `taxin` instead of root |
| `ExecStart=` | The command used to launch qBittorrent-nox in daemon mode |
| `Restart=on-failure` | Automatically restarts the service if it crashes |

---

## Managing the Service

| Action | Command |
|---|---|
| Start | `sudo systemctl start qbittorrent-nox` |
| Stop | `sudo systemctl stop qbittorrent-nox` |
| Restart | `sudo systemctl restart qbittorrent-nox` |
| Check status | `systemctl status qbittorrent-nox` |
| View live logs | `journalctl -u qbittorrent-nox -f` |
| Disable auto-start | `sudo systemctl disable qbittorrent-nox` |

---

## WebUI Access

Once the service is running, open your browser and navigate to:

```
http://localhost:8080
```

| Field | Default |
|---|---|
| Username | `admin` |
| Password | `adminadmin` |

> **Security:** Change the default password immediately after first login via **Settings → WebUI → Password**.

---

*README written with the assistance of [Claude](https://claude.ai) by Anthropic.*
