## tmux setup

```bash
git clone https://github.com/tmux-plugins/tpm ~/.config/tmux/plugins/tpm
```

 - then just put the `tmux.conf` to `~/.config/tmux/`  
 - to apply the changes, go to `prefix` then press `shift + i`
 - to save a session go to `prefix` and press `ctrl + s`

## basic needs
cleanup:
```bash
sudo rm -rf /var/cache/pacman/pkg/*
```
```bash
yay -Sc
```

install:
```bash
yay -S --needed \
ab-download-manager-bin \
obsidian \
opentabletdriver \
stacer-bin \
qbittorrent \
cmake \
proton-vpn-gtk-app \
terabox-bin \
anydesk-bin \
bclone \
rclone \
googledot-cursor-theme \
apple_cursor \
hyprmod \
aether \
rclone-manager \
nodejs \
npm \
morphe-desktop 
```

## avro setup
```bash
bash -c "$(wget -q https://raw.githubusercontent.com/asifakonjee/openbangla-script/master/fcitx5.sh -O -)"
```

## `sn /etc/fstab`
```conf
# /dev/sdb1
UUID=3cb7e966-2a00-40b4-87f8-d8e62e710b07  /mnt/backup  btrfs  defaults,nofail,compress=zstd  0  0
```
