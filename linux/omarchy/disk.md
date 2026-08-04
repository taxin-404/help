# Drive Lifespan Setup

A plain-language guide to keeping your drives alive longer. Two parts:

1. **The 4 existing protections** - things already in place that extend drive life
2. **The 4 setup items** - things worth setting up, with a way to check if each is already done

The check steps assume Arch Linux (systemd). Every command is read-only.

---

## Part 1: The 4 existing protections

These are the things that quietly save your drives. If they are in place, your system is already ahead of the curve.

### 1. Swap on zram (RAM compression)

When RAM runs out, most systems write "swap" to disk - meaning writes to your SSD, which wears it. `zram` instead compresses the RAM contents in RAM and uses that as swap space, so the disk is almost never touched by swapping.

**Why it matters:** the biggest single write-volume reducer for an SSD.

**Check if set:**
```
zramctl
cat /proc/swaps
```
Look for a `zram0` entry with higher priority than any `swapfile`. If only `/swap/swapfile` exists and no zram, swap is going to disk.

### 2. /tmp in RAM (tmpfs)

Temp files - browser downloads, unpacked archives, build caches - normally live on disk. On `tmpfs` they live in RAM: zero writes to the SSD, and they vanish on reboot for free.

**Check if set:**
```
findmnt /tmp -o TARGET,SOURCE,FSTYPE
```
`SOURCE` should read `tmpfs`. If it shows your disk (e.g. `/dev/sda1`), temp writes are hitting the drive.

### 3. Filesystem compression

Compressing data before writing it means fewer bytes stored and rewritten - less NAND wear. On btrfs this is done with `compress=zstd:3` (or similar).

**Check if set:**
```
findmnt / -o OPTIONS
```
Look for `compress=...` in the options. If absent, nothing is being compressed.

### 4. Free-space headroom

SSDs need free blocks to do wear leveling. A nearly-full SSD has to shuffle data constantly, causing extra writes and slower performance. Keeping at least 10% free is the simplest rule.

**Check if set:**
```
df -hT /
```
Keep the `Use%` under ~90%. On this machine root sits at ~13%, which is plenty of headroom.

---

## Part 2: The 4 setup items

These are the things worth enabling. Each one has a **check step** so you can tell whether it is already done on your machine.

### 1. TRIM / discard

When you delete a file, the filesystem knows it is gone but the SSD does not - it keeps carrying the dead pages around. Discard (TRIM) tells the SSD "these blocks are dead" so it can erase them lazily and write to clean pages. Result: faster writes and less wear.

Two ways to deliver discards on btrfs:
- `discard=async` mount option - continuous, automatic background trimming (the modern recommended way; no schedule to maintain)
- `fstrim.timer` - a weekly batch trim (older approach)

**Check if already set:**
```
findmnt -no OPTIONS /
```
Look for `discard=async` in the options. If absent, either mount with it (add to fstab) or use the weekly timer:
```
sudo systemctl enable --now fstrim.timer
```

**Encrypted root caveat:** if the root filesystem is behind LUKS, discards must be explicitly allowed at the LUKS layer or they are silently dropped and `fstrim` reports "discard operation is not supported":
- If root is set up in `/etc/crypttab`: add `allow-discards` to its options
- If root is set up via kernel cmdline (`cryptdevice=...:name`): append `:allow-discards` to that parameter (e.g. `cryptdevice=PARTUUID=...:root:allow-discards`) in the bootloader's kernel command line

**Tradeoff (accepted on this machine):** enabling discards through LUKS reveals which sectors are in use vs. free to anyone with the decryption key - it slightly weakens LUKS (a free/used-sector side channel), but does not leak file contents.

### 2. smartd (automatic drive monitoring)

`smartd` is the background daemon for `smartctl`. Enabled and configured, it silently watches all drives, runs periodic self-tests, and logs warnings - so a failing drive is noticed before it dies, not after.

**Check if already set:**
```
systemctl is-enabled smartd
```
Should print `enabled`. If `disabled`:
1. Edit `/etc/smartd.conf`, uncomment/define device lines, e.g.:
   ```
   /dev/sda -a -s (S/../.././02) -s (L/../../7/03) -m root
   /dev/sdb -a -s (S/../.././02) -s (L/../../7/03) -m root
   /dev/sdc -a -s (S/../.././02) -s (L/../../7/03) -m root
   ```
   (weekly short self-tests at 02:00, monthly long self-tests, mail root on problems)
2. Enable it:
   ```
   sudo systemctl enable --now smartd
   ```

### 3. Monthly btrfs scrub (bit-rot check)

btrfs keeps checksums of all data. A scrub re-reads every block and compares it against those checksums, catching silent data corruption early. The timer file ships with btrfs-progs but is off by default.

**Check if already set:**
```
systemctl list-timers | grep btrfs-scrub
systemctl list-unit-files --state=enabled | grep scrub
```
If nothing shows, enable it using the mount point of the btrfs filesystem. The unit argument is the mount point (with leading slash removed; `/` becomes `-`). Scrubbing `/` covers the whole filesystem, including all subvolumes:
```
sudo systemctl enable --now btrfs-scrub@-.timer
```

### 4. Mount extra drives with noatime

By default Linux stamps each file with a "last accessed" time on every read - a tiny pointless write per access, multiplied by thousands of files. `noatime` turns that off. It is a mount option, so it goes on any mount you create - fstab entries for auto-mount, or `mount -o noatime` for manual ones.

**Check if already set:**
```
grep -v '^#' /etc/fstab
```
Look for entries for your data drives containing `noatime` (e.g. `defaults,noatime,nodiratime`). If a data drive is not in fstab at all, it is not auto-mounted.

Example fstab entry for an ext4 drive (auto-mount at boot, at `/mnt/data`):
```
UUID=<drive-uuid>  /mnt/data  ext4  defaults,noatime,nodiratime  0 2
```
Example for an NTFS drive (needs `ntfs-3g` installed first, mounts at `/mnt/win`):
```
UUID=<drive-uuid>  /mnt/win  ntfs-3g  defaults,noatime,nodiratime  0 2
```
After editing fstab:
```
sudo mkdir -p /mnt/data /mnt/win
sudo mount -a        # mounts everything in fstab
```

---

## Current status on this machine

| Item | Status |
|---|---|
| zram swap | already set |
| /tmp on tmpfs | already set |
| btrfs compression (zstd) | already set |
| Free-space headroom | already set (~13% used) |
| TRIM | set - async discard active (kernel default since 6.2) + `allow-discards` in kernel cmdline (active after next reboot) |
| smartd | not set (deliberately skipped - health checks done on request) |
| btrfs scrub timer | set - monthly scrub on `/` enabled |
| noatime fstab mounts (sdc1 / sdb2) | not set (deliberately skipped - data drives stay unmounted; ntfs-3g not installed) |

**Note:** async discard is active on `/`, `/home`, `/var/cache/pacman/pkg`, `/var/log` as the kernel default (6.2+) - no fstab option needed. The `allow-discards` change to the kernel command line (in `/etc/kernel/cmdline` and `/boot/limine.conf`) takes effect at the next reboot - until then `fstrim /` still reports "discard operation is not supported". The weekly `trim.sh`/`trim.timer` were removed as redundant. `/boot` (vfat) no longer gets trimmed; its writes are rare so the impact is negligible.
