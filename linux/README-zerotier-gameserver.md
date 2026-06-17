# Hosting a Local Game Server Over a Shared IP — ZeroTier + SSH Setup (Arch & Debian)

If your ISP gives you a **shared / CGNAT IP** (very common with mobile broadband and many home connections in Bangladesh and elsewhere), you can't port-forward your way into hosting a game server — there's no public IP to forward from. **ZeroTier** solves this by creating a virtual private LAN over the internet: every member gets a private IP (e.g. `10.147.20.x`) and can reach every other member directly, peer-to-peer, with no port forwarding and no public IP required. This guide covers installing ZeroTier on Arch and Debian, hardening SSH access over it, and binding a game server to the virtual network so friends can join.

---

## 1. Why This Works

A shared IP only breaks **inbound** connections from the raw internet. ZeroTier sidesteps the whole problem: all members tunnel out to ZeroTier's coordination servers (UDP, outbound — something your ISP always allows), find each other, and then talk directly (or relayed, if direct fails). From the game server's point of view, every player is just another machine on the same LAN.

---

## 2. Install ZeroTier

### Arch / Arch-based (Omarchy, CachyOS, etc.)
```bash
sudo pacman -S zerotier-one
sudo systemctl enable --now zerotier-one
```

### Debian / Ubuntu
```bash
curl -s https://install.zerotier.com | sudo bash
sudo systemctl enable --now zerotier-one
```

Confirm the service is alive:
```bash
sudo zerotier-cli info
```
You should see something like `200 info <node-id> ONLINE`.

---

## 3. Create a Network

1. Go to [my.zerotier.com](https://my.zerotier.com) and sign up (free tier supports up to 25-50 devices depending on plan).
2. Create a network and copy the **16-character Network ID**.
3. In the network's settings:
   - Enable **"Auto-Assign from Range"** (default `10.147.x.x/24` is fine).
   - Leave it **private** (not public) so devices need manual authorization.

---

## 4. Join the Network (host + every player)

On the server and on every client that wants to connect:
```bash
sudo zerotier-cli join <network-id>
```

Then go back to the ZeroTier Central dashboard → your network → **Members** tab, and tick the checkbox to **authorize** each device as it appears. Optionally give the host a fixed IP here so it doesn't change later.

Verify on each machine:
```bash
sudo zerotier-cli listnetworks
ip addr show zt0
```
You should see a `10.147.x.x` address on the `zt0` interface.

Test connectivity between two members:
```bash
ping 10.147.20.5
```

---

## 5. Set Up SSH on the Host

### Arch
```bash
sudo pacman -S openssh
sudo systemctl enable --now sshd
```

### Debian
```bash
sudo apt update && sudo apt install openssh-server -y
sudo systemctl enable --now ssh
```

### Lock it down
On the client:
```bash
ssh-keygen -t ed25519 -C "your-label"
ssh-copy-id user@10.147.20.5      # use the host's ZeroTier IP, not its WAN IP
```

On the host, edit `/etc/ssh/sshd_config`:
```
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
```
Restart:
```bash
sudo systemctl restart sshd
```

### Scope SSH to the ZeroTier interface only (recommended for a shared-IP box)
Even though a shared IP already blocks unsolicited inbound traffic, it's good practice to make sure SSH is never exposed if your network situation ever changes (e.g. you switch ISPs and get a real public IP later):
```
ListenAddress 10.147.20.5
```
in `sshd_config`, or restrict via firewall:
```bash
# nftables / ufw example (Debian)
sudo ufw allow in on zt0 to any port 22 proto tcp
sudo ufw deny 22/tcp
```

---

## 6. Bind the Game Server to the ZeroTier IP

This is the key step. Most game servers default to listening on `0.0.0.0` (all interfaces). You want it to listen specifically on the ZeroTier interface's address so it's reachable only through the virtual LAN:

```bash
# generic example — check your specific game's docs for the exact flag/config key
./gameserver --bind 10.147.20.5 --port 27015
```

For servers configured via a `server.cfg` or `.ini` file, look for a `bind_address`, `host_ip`, or `listen_ip` field and set it to the ZeroTier address instead of leaving it blank or `0.0.0.0`.

Players then:
1. Join the same ZeroTier network ID (`zerotier-cli join <id>`) and get authorized on Central.
2. Connect in-game using the host's ZeroTier IP and the game's port, e.g. `10.147.20.5:27015`.

No router config, no port forwarding, no dynamic DNS needed — it works identically whether the host is on a shared IP, CGNAT, or behind a strict NAT.

---

## 7. Firewall & NAT Issues

Firewalls are the #1 cause of ZeroTier "it doesn't connect" reports. There are three separate layers that can each block it independently — check all three.

### A. Outbound UDP 9993 blocked
ZeroTier needs outbound UDP 9993 to reach its root servers for peer discovery. Strict corporate/campus networks, some public Wi-Fi, and a few ISPs block or throttle arbitrary UDP. Check peer status:
```bash
sudo zerotier-cli peers
```
Look at the `PATH` column:
- `DIRECT` — peer-to-peer, fast, working as intended.
- `RELAY` — traffic is bouncing through ZeroTier's relay servers. Still works, just higher latency.
- Peer missing entirely from the list — likely fully blocked; see fallback below.

ZeroTier automatically falls back to TCP over port 443 if UDP 9993 is blocked outright, so it should still work, just slower and relayed.

### B. Local firewall on the Linux box itself
ufw/nftables/iptables can block ZeroTier's own interface even when the network path is fine:
```bash
# ufw
sudo ufw allow in on zt0
sudo ufw allow out on zt0

# nftables (add to your ruleset)
sudo nft add rule inet filter input iif zt0 accept
sudo nft add rule inet filter output oif zt0 accept
```
Also double check there's no explicit rule dropping outbound UDP 9993.

### C. Symmetric NAT / router-level UDP filtering
Some routers — especially carrier-grade NAT on mobile broadband — use symmetric NAT, which prevents direct UDP hole-punching even when UDP isn't blocked outright. ZeroTier just relays through its root servers in this case. This is normal and usually fine for SSH and most game traffic; it only matters if latency becomes a real problem.

If you control the router, also check that it isn't restricting UDP to specific ports — ZeroTier doesn't need port forwarding, but some locked-down enterprise gear blocks "unsolicited" UDP by default.

### D. Self-hosted Moon (if stuck on RELAY and latency hurts)
If peers are permanently on `RELAY` and it's noticeably affecting gameplay, you can run your own ZeroTier "moon" — a dedicated root server on a VPS with a public IP, geographically closer than ZeroTier's public roots. This is more setup work and only worth it if relay latency is actually a problem; skip it otherwise.

### Diagnostic script
Quick check for UDP 9993 reachability and per-peer connection type:
```bash
#!/usr/bin/env bash
# zt-diag.sh — quick ZeroTier connectivity check

echo "== ZeroTier service status =="
systemctl is-active zerotier-one

echo -e "\n== Node info =="
sudo zerotier-cli info

echo -e "\n== Joined networks =="
sudo zerotier-cli listnetworks

echo -e "\n== Peer connection types =="
sudo zerotier-cli peers | awk 'NR==1 || $0 !~ /^200/ {next} {print}'
sudo zerotier-cli peers

echo -e "\n== UDP 9993 outbound test (to a ZeroTier root) =="
timeout 3 bash -c "echo > /dev/udp/2.tier.zerotier.com/9993" \
  && echo "UDP 9993 outbound: appears open" \
  || echo "UDP 9993 outbound: blocked or filtered (ZeroTier will fall back to TCP/443)"
```
Save as `zt-diag.sh`, `chmod +x zt-diag.sh`, run with `./zt-diag.sh`. If the peers list shows `RELAY` for everyone and the UDP test fails, the network path is blocking UDP — TCP fallback is doing the work instead.

---

## 8. Keep a Laptop Host Running with the Lid Closed

If the host is a laptop, closing the lid will suspend it by default — which kills the game server and your SSH session. Tell `systemd-logind` to ignore the lid switch so it keeps running headless.

Edit `/etc/systemd/logind.conf` (same file/path on both Arch and Debian):
```
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
```
`HandleLidSwitch` covers running on battery, `HandleLidSwitchExternalPower` covers plugged in — set both to `ignore` since a server should usually stay on AC power anyway, but it's safer to cover both cases.

Apply it:
```bash
sudo systemctl restart systemd-logind
```
Note: restarting `logind` can drop active graphical sessions — fine for a headless server, but do this from SSH/TTY rather than from the laptop's own desktop session if it still has a display manager running.

### Optional: also disable display sleep/lock screen interference
If a display manager (SDDM, GDM, etc.) is still installed and tries to lock or suspend on lid close independently of `logind`, either disable it or set it to never sleep:
```bash
sudo systemctl disable sddm   # or gdm, lightdm — only if you're running fully headless
```
Skip this if you still want occasional local desktop access to the machine.

### Verify
Close the lid and confirm from another machine that SSH and the game server are still reachable over the ZeroTier IP:
```bash
ssh user@10.147.20.5
```

---

## 9. Troubleshooting

| Symptom | Likely Cause |
|---|---|
| Device shows in Central but has no IP | Not authorized yet — check the Members tab |
| `zt0` interface missing | `sudo systemctl restart zerotier-one` |
| Members can ping but can't reach the game | Game server bound to wrong interface, or its own internal firewall blocking |
| High latency between players | Peer is on `RELAY` instead of `DIRECT` — see Section 7 |
| SSH connection refused over ZT IP | `sshd` not listening on `zt0`, or `ListenAddress` set to the wrong IP |
| Peer never appears at all | Outbound UDP 9993 fully blocked and TCP/443 fallback also blocked — likely a very locked-down network (corporate/campus) |
| Laptop host drops offline when lid is closed | Lid-close suspend not disabled — see Section 8 |

---

## 10. Quick Reference

```bash
zerotier-cli info                  # node status
zerotier-cli listnetworks          # joined networks + assigned IP
zerotier-cli join <network-id>     # join a network
zerotier-cli leave <network-id>    # leave a network
ip addr show zt0                   # confirm interface + IP
ssh user@<zerotier-ip>             # connect to host over the virtual LAN
```

---

### Notes
- Static IPs assigned per-device in ZeroTier Central are worth setting for the host so the connect address never changes.
- For larger groups, ZeroTier's free tier networking limits may apply — check current limits on their pricing page if you exceed ~25 members.
- This setup is host-agnostic: the "host" can be any machine on the network (a spare laptop, a small server, even another player's PC) — whichever one is running the game server process.
