# TeraBox Live-Sync Setup (rclone + systemd) — Omarchy

TeraBox has no native Linux sync client. This setup uses `rclone bisync` +
a systemd user timer to approximate live sync, plus a wrapper script for
failure tracking.

- **Local sync folder:** `~/oma`
- **Remote:** `oma:/omacom` (rclone remote name `oma`, TeraBox folder `omacom`)
- **Sync interval:** every 5 minutes
- **Compare method:** `--size-only` (TeraBox doesn't reliably support modtime or checksum comparison)

---

## 1. Install rclone

```bash
sudo pacman -S rclone
```

## 2. Configure the TeraBox remote

```bash
rclone config
```
- `n` → new remote → name it `oma` → select TeraBox from provider list
- Follow prompts for TeraBox login/cookie auth

Test it:
```bash
rclone lsd oma:
```

## 3. Local folder

```bash
mkdir -p ~/oma
```

## 4. First-time sync (baseline)

**Do NOT interrupt this (no Ctrl+C) — let it finish, especially with large files.**

```bash
rclone bisync ~/oma oma:/omacom --resync --size-only
```

> Note: `--checksum` doesn't work here — TeraBox doesn't expose file hashes,
> so rclone falls back to size/modtime anyway. Stick to `--size-only`.

Verify after it finishes:
```bash
rclone check ~/oma oma:/omacom --size-only
```

## 5. Regular sync (after baseline exists)

```bash
rclone bisync ~/oma oma:/omacom --size-only
```
(no `--resync` needed after the first run)

## 6. Failure-tracking wrapper script

Scripts live in `~/oma-scripts/`:

- `terabox-sync.sh` — runs bisync, logs everything to
  `~/.local/share/terabox-sync/sync.log`, and extracts ERROR lines into
  `~/.local/share/terabox-sync/failed.log`
- `terabox-retry.sh` — shows recent failures; `--retry` flag re-runs sync

Setup:
```bash
mkdir -p ~/oma-scripts
# place terabox-sync.sh and terabox-retry.sh here
chmod +x ~/oma-scripts/*.sh
```

Check failures anytime:
```bash
~/oma-scripts/terabox-retry.sh          # just show
~/oma-scripts/terabox-retry.sh --retry  # show + resync
```

## 7. systemd user service + timer (auto-sync every 5 min)

`~/.config/systemd/user/terabox-sync.service`:
```ini
[Unit]
Description=TeraBox bisync

[Service]
Type=oneshot
ExecStart=%h/oma-scripts/terabox-sync.sh
```

`~/.config/systemd/user/terabox-sync.timer`:
```ini
[Unit]
Description=Run TeraBox sync every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
```

Enable:
```bash
systemctl --user daemon-reload
systemctl --user enable --now terabox-sync.timer
```

## 8. Monitoring

```bash
# live systemd status
journalctl --user -u terabox-sync.service -f

# timer status
systemctl --user status terabox-sync.timer

# custom logs
tail -f ~/.local/share/terabox-sync/sync.log
cat ~/.local/share/terabox-sync/failed.log
```

---

## Known issues / gotchas

- **Not true instant sync.** This is polling every 5 min, not inotify-based
  real-time sync like Dropbox.
- **Never Ctrl+C a bisync run**, especially with large files mid-transfer —
  it can leave partial/corrupt files on the remote. If it happens, delete
  the broken file on remote (`rclone deletefile "oma:/path/to/file"`) and
  resync.
- **`--checksum` is a no-op for TeraBox** — no shared hash support, falls
  back to modtime/size. Use `--size-only` instead.
- To sync only a subfolder instead of everything, point both sides at that
  subfolder, e.g.:
  ```bash
  rclone bisync ~/oma-mern oma:/mern --resync --size-only
  ```
