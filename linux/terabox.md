# Mounting TeraBox with rclone (no stuck uploads + auto-mount)

Notes for mounting TeraBox via `rclone mount` on Arch Linux (Hyprland / Omarchy), fixing uploads that get stuck in the local cache, and mounting automatically at login.

> **bclone** is a fork of rclone that adds support for unofficial services like TeraBox. All commands are the same as rclone. On this system the binary is installed as `rclone` (there is no `bclone` command), so every command below uses `rclone`.
> Check which binary you have with `which rclone`. If it isn't `/usr/bin/rclone`, change the path in the systemd service's `ExecStart` to match.

---

## The problem

With this command, files sometimes land in the local cache and never upload to TeraBox:

```bash
rclone mount terabox: /mnt/terabox --vfs-cache-mode full --daemon
```

`--vfs-cache-mode full` caches reads **and** writes locally. With the default write-back delay (5s), uploads can sit in the queue or fail quietly after retries run out.

---

## The fix

Cache only while writing, and start uploading after 1 second:

```bash
rclone mount terabox: /mnt/terabox \
  --vfs-cache-mode writes \
  --vfs-write-back 1s \
  --rc \
  --daemon
```

| Flag | What it does |
|------|--------------|
| `--vfs-cache-mode writes` | Caches files only while they are being written |
| `--vfs-write-back 1s` | Starts uploading 1s after a file is closed (default is 5s) |
| `--rc` | Enables the remote control API so you can inspect the upload queue |

### Truly no caching

```bash
rclone mount terabox: /mnt/terabox --vfs-cache-mode off
```

Caveats:
- Files can only be written sequentially (no in-place editing or read+write opens).
- Some backends need the file size up front. If TeraBox rejects uploads in this mode, go back to `writes`.

Test with a small file first.

### Most reliable for big or important files

Skip the mount and copy directly. You get progress and an immediate error if it fails:

```bash
rclone copy ~/file terabox:folder/ -P
```

---

## Checking for stuck uploads

Needs `--rc` on the mount:

```bash
rclone rc vfs/queue
```

Files not yet uploaded are in the cache folder:

```
~/.cache/rclone/vfs/terabox/
```

**Before unmounting**, copy anything still there and upload it with `rclone copy`.

To see why uploads fail, run the mount in the foreground with verbose logging (no `--daemon`):

```bash
rclone mount terabox: /mnt/terabox --vfs-cache-mode writes --vfs-write-back 1s -vv
```

---

## Auto-mount at login (systemd user service)

Recommended: it restarts if the mount drops, logs to the journal, and flushes pending uploads cleanly on stop. It works under Hyprland/Omarchy because user services belong to the login session, not the desktop.

### 1. Prepare the mount point

```bash
sudo mkdir -p /mnt/terabox
sudo chown $USER:$USER /mnt/terabox
fusermount3 -u /mnt/terabox   # unmount any existing --daemon mount first
```

### 2. Create `~/.config/systemd/user/rclone-terabox.service`

```ini
[Unit]
Description=Rclone mount for TeraBox

[Service]
Type=notify
ExecStart=/usr/bin/rclone mount terabox: /mnt/terabox \
  --vfs-cache-mode writes \
  --vfs-write-back 1s \
  --rc
ExecStop=/usr/bin/fusermount3 -u /mnt/terabox
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
```

Do **not** use `--daemon` here. `Type=notify` needs rclone in the foreground so systemd knows when the mount is ready.

Check the binary path with `which rclone` and adjust `ExecStart` if it isn't `/usr/bin/rclone`.

### 3. Enable and start

```bash
systemctl --user daemon-reload
systemctl --user enable --now rclone-terabox.service
```

### 4. Check status and logs

```bash
systemctl --user status rclone-terabox.service
journalctl --user -u rclone-terabox -f
```

### Manual control

```bash
systemctl --user stop rclone-terabox      # clean stop, flushes pending uploads
systemctl --user restart rclone-terabox
```

If the network isn't up at login, the first attempt may fail, but `Restart=on-failure` retries every 10 seconds until it connects.

---

## Alternative: start with Hyprland (`exec-once`)

Simpler, but nothing retries if the network isn't ready. **Don't combine this with the systemd service**, or the two will fight over the mount point.

In `~/.config/hypr/autostart.conf` (Omarchy) or `hyprland.conf`:

```ini
exec-once = rclone mount terabox: /mnt/terabox --vfs-cache-mode writes --vfs-write-back 1s --rc --daemon
```

With a wait-for-network wrapper:

```ini
exec-once = sh -c 'until ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; do sleep 3; done; rclone mount terabox: /mnt/terabox --vfs-cache-mode writes --vfs-write-back 1s --rc --daemon'
```

---

## Troubleshooting quick reference

| Symptom | Try |
|---------|-----|
| Files stuck, never reach TeraBox | `rclone rc vfs/queue`, check `~/.cache/rclone/vfs/terabox/`, run with `-vv` |
| `--vfs-cache-mode off` upload errors | Switch back to `writes` |
| Mount point busy / won't remount | `fusermount3 -u /mnt/terabox` (add `-z` for a lazy unmount) |
| Service won't start | `journalctl --user -u rclone-terabox -e` and verify the `rclone` path |
| Important file must arrive | Use `rclone copy file terabox:folder/ -P` instead of the mount |
