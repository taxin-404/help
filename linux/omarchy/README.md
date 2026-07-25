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
yay -S --needed ab-download-manager-bin brave-origin-bin cliamp obsidian opentabletdriver stacer-bin qbittorrent cmake npm nodejs proton-vpn-gtk-app terabox-bin anydesk-bin
```
## avro setup

```bash
bash -c "$(wget -q https://raw.githubusercontent.com/asifakonjee/openbangla-script/master/fcitx5.sh -O -)"
```
