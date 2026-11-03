# Madwine input bugs + GE-Proton auto-updater — progress handoff

_Last updated: 2026-11-03 (late). Written so any AI/agent can resume with no prior context._

## TL;DR / current status

- **Goal A — auto-update the compatibility layer:** DONE. GE-Proton auto-updater lives in
  `github.com/taxin-404/madwine` (commit `305e8ec`), installed at
  `~/.local/bin/madwine-compat-update` with a daily `systemd --user` timer. Madwine is now on
  **GE-Proton11-12** (`config.json.proton`), with `GE-Proton11-5` kept as rollback.
- **Goal B — input bugs:**
  - **Keyboard (launcher + after launching Roblox): FIXED AND VERIFIED.** Root cause is Wine's
    X11 `WM_TAKE_FOCUS` handshake, not Proton. Fix = Wine registry
    `HKCU\Software\Wine\X11 Driver\UseTakeFocus = N` in the Madwine prefix. See
    **“THE INPUT FIX”** below.
  - **Mouse left-click dying after a purchase button in fullscreen: NOT yet tested/verified.**
    The keyboard fix may or may not affect it; needs an in-game test.

## THE INPUT FIX (verified 2026-11-03)

### Symptom
After launching Roblox from the Madwine launcher, the keyboard appears dead. Switching
workspaces makes it work again. Typing in the launcher itself also did nothing.

### Root cause (proven with a controlled experiment)
1. Wine creates its top-level windows with `WM_HINTS` `input = False` and offers the ICCCM
   `WM_TAKE_FOCUS` protocol (the “globally active” focus model).
   - Observed on **both** `madwine-madium` (launcher, `Madium.exe`) and `madwine-roblox`
     (`RobloxPlayerBeta.exe`).
2. Hyprland **does** implement the handshake: it sends the `WM_TAKE_FOCUS` ClientMessage
   (`message_type = WM_PROTOCOLS`, `data[0] = WM_TAKE_FOCUS` atom = 331, `data[1] = timestamp`)
   instead of calling `XSetInputFocus`.
   - Proven by a purpose-built test window (`inputtest2.c`) that logs the exact message.
3. **The launcher (`Madium.exe`) does not honour `WM_TAKE_FOCUS`** → Hyprland marks the window
   focused (`_NET_WM_STATE_FOCUSED`) but the **X input focus stays on the Roblox window**
   (`XGetInputFocus` = Roblox's window). Keystrokes therefore go to the game, not the launcher.
   - The Roblox window *does* honour the handshake; the launcher does not. That asymmetry is the bug.

### Hyprland window rules do NOT fix this (tested, do not retry)
- `allows_input = true` and `focus_on_activate = true` were tried on `^madwine`.
  - Controlled test: a fresh `input=False` window with a matching rule still got **no** X focus;
    Hyprland still sent `WM_TAKE_FOCUS`. Window rules themselves were proven to work in the same
    test using `float = true`.
  - Also, Wine windows are created with `initialClass = steam_app_default`, so a `^madwine` class
    rule only matches after the class is renamed (too late for map-time effects).
- The rule was **removed** from `~/.config/hypr/hyprland.lua`; it is not part of the fix.

### The fix
In the Madwine Wine prefix, set:

```
HKCU\Software\Wine\X11 Driver
    UseTakeFocus = "N"
```

Wine then declares `Client accepts input or input focus: True` and **stops advertising
`WM_TAKE_FOCUS`**, so the compositor calls `XSetInputFocus` directly. Upstream reference: KDE bug
525590 documents exactly this `xprop` change.

**Applied to the real prefix:**
- File: `~/.local/share/madwine/prefix/pfx/user.reg`
- Added under the `[Software\\Wine\\X11 Driver]` section (after its `#time=` line):
  `"UseTakeFocus"="N"`
- Backup: `~/.local/share/madwine/prefix/pfx/user.reg.bak.20261103220437`

**Important:** Madwine must be **fully closed** when editing `user.reg` — `wineserver` rewrites the
file from memory on exit, which would discard the edit. Wait for all of
`Madwine.AppImage`, `umu-run`, `*.exe`, `msedgewebview2`, and `wineserver` to exit.

### Verification evidence (all observed live)
- `xprop -id <madium|roblox> WM_HINTS` → `Client accepts input or input focus: True`
- `xprop ... WM_PROTOCOLS` → only `WM_DELETE_WINDOW, _NET_WM_PING` (no `WM_TAKE_FOCUS`)
- Focusing each window sets `XGetInputFocus` to that window (`~/.local/bin/grabprobe`):
  - `madwine-roblox` → `focus=0x5200003`
  - `madwine-madium` → `focus=0x2800005`
- Typed `hello` into the launcher's “Search accounts” box → text appeared and the list filtered.
- **Reproduced the original scenario:** launched Roblox from the Madwine menu, then focused the
  launcher and typed `after` → text appeared in the launcher (while Roblox ran alongside).

### How to re-apply / check
A helper is installed at `~/.local/bin/madwine-fix-input` (repo: `bin/madwine-fix-input` in
`github.com/taxin-404/madwine`). It is idempotent, backs up `user.reg`, and refuses to run while
Madwine is live:

```bash
madwine-fix-input --check     # is UseTakeFocus=N set?
madwine-fix-input --apply     # set it (Madwine must be fully closed)
```

Manual equivalent:
```bash
# CHECK (Madwine running):
xprop -id "$(xdotool search --class madwine-madium | head -1)" WM_HINTS | grep -i 'accepts input'
# expect: Client accepts input or input focus: True

# APPLY (Madwine fully closed):
P=~/.local/share/madwine/prefix/pfx
cp -p "$P/user.reg" "$P/user.reg.bak.$(date +%Y%m%d%H%M%S)"
# insert `"UseTakeFocus"="N"` under [Software\\Wine\\X11 Driver] (after its #time= line)
# then relaunch Madwine.
```

## Remaining work

1. **Mouse left-click after a purchase button in fullscreen Roblox — verify.**
   - Earlier evidence: `grabprobe` showed `pointer active grab: HELD BY ANOTHER CLIENT` while
     fullscreen and `FREE` when windowed; disabling fullscreen restored the mouse.
   - Not reproduced/tested since the `UseTakeFocus=N` change. Needs a real in-game purchase flow.
   - If it persists, it is likely a separate pointer-grab issue (candidate: Wine/Proton X11 pointer
     grab handling; GE-Proton11-12 already includes the “X11: games no longer hang waiting for a
     pointer grab on focus changes” fix — if it still happens on 11-12, investigate further).
2. **Persistence across a full Madwine restart** should be confirmed once: close Madwine, then
   `grep -n UseTakeFocus ~/.local/share/madwine/prefix/pfx/user.reg` (wineserver should write it
   back). Then relaunch and re-run the CHECK above.

## Whats installed / where things live

### Madwine
- App version **0.1.22**; launcher binary `~/.local/share/madwine/Madwine.AppImage`.
- Config: `~/.config/madwine/config.json`
  - `"proton": "/home/taxin/.local/share/madwine/proton/GE-Proton11-12-x86_64"`
  - `"reuseSteamProton": false`
- Layers dir: `~/.local/share/madwine/proton/` (`GE-Proton11-12-x86_64` active,
  `GE-Proton11-5-x86_64` rollback).
- Prefix: `~/.local/share/madwine/prefix/pfx/` (`user.reg`, `system.reg`, `userdef.reg`).
- Launcher UI app is **`Madium.exe`** (Edge WebView2); window class `madwine-madium`; title `madium`.
- Game window class `madwine-roblox`; runs `RobloxPlayerBeta.exe`.
- Both Wine windows had `initialClass = steam_app_default` at map time, then rename to `madwine-*`.
- Logs: `~/.local/state/madwine/madwine.log` (`win:`, `lock:`, `upd:`, `proton reused path=`),
  `~/.local/state/madwine/wine.log` (Wine output / `PROTONPATH`).

### The auto-updater tool
- Repo (pushed): **`github.com/taxin-404/madwine`** — branch `main`, commit `305e8ec`.
- Local clone: **`/tmp/opencode/madwine-repo`**.
- Files: `bin/madwine-compat-update`, `install.sh`, `uninstall.sh`,
  `systemd/madwine-compat-update.{service,timer}`, `README.md`, `LICENSE` (Unlicense).
- Behaviour: fetch latest GE-Proton → SHA-512 verify → install into
  `~/.local/share/madwine/proton/<tag>-x86_64/` → set `config.json.proton` (and clear
  `reuseSteamProton`) with a timestamped backup → prune older GE-Proton copies keeping the previous
  one as rollback (never touches non-GE-Proton layers). Refuses to run while Madwine/Wine/Roblox is
  live. Options: `--check`, `--dry-run`, `--force`, `--version <tag>`.
- Installed: `~/.local/bin/madwine-compat-update`; daily timer
  `madwine-compat-update.timer`; `--check` → `status: UP TO DATE`.

### Diagnostics helpers (built during this investigation)
- `~/.local/bin/grabprobe` + source `~/.local/share/madwine-diag/grabprobe.c` — prints X keyboard/
  pointer grab state and the current X input focus (`focus=0x...`). `focus=0x0` means “no X window
  has focus”.
- `~/.local/bin/keywatch` + source `~/.local/share/madwine-diag/keywatch.c` — logs `KeyPress`/
  `KeyRelease` delivered to a given window id.
- `/tmp/opencode/inputtest.c`, `/tmp/opencode/inputtest2.c` — minimal “Wine-like” X11 test windows
  (`WM_HINTS input=False` + `WM_TAKE_FOCUS`). `inputtest2` also logs `FocusIn`/`FocusOut`/`KeyPress`
  and ClientMessages, and was used to prove Hyprland sends `WM_TAKE_FOCUS` but does not set X focus.
- `/tmp/opencode/probefocus.sh <selector...>` — focus a window via Hyprland and print
  `activewindow` + X focus.
- `/tmp/opencode/pollfocus.sh <class>` — focus a class and poll X focus for ~3 s.

### Backups
- Prefix registry: `~/.local/share/madwine/prefix/pfx/user.reg.bak.20261103220437`
- Madwine config: `~/.config/madwine/config.json.bak.20261103210917`,
  `config.json.preupdate-20261103204441`, `config.json.bak.20261103204543`
- Hyprland config: `~/.config/hypr/hyprland.lua.bak.1793720531` (and earlier `.bak.*`).

## Corrections to earlier notes in this file (important)
- GE-Proton11-12 was **not** the keyboard fix. The keyboard bug is the Wine `WM_TAKE_FOCUS`/
  `input=False` issue above. (The layer switch is still valid and desirable.)
- `allows_input`/`focus_on_activate` Hyprland rules were a dead end (tested) and have been removed.
- `madwine-madium` **can** take X focus if something calls `XSetInputFocus` directly (e.g.
  `xdotool windowactivate`), which is why earlier “keywatch saw events” tests were misleading.

## Key gotchas
- **`reuseSteamProton` does nothing** for layer selection. Always set `config.json.proton`.
- Madwine **rewrites `config.json` on exit**; never edit it while the launcher is alive.
- Madwine/Wine **rewrites `user.reg` on exit**; edit the prefix registry only when fully closed.
- `menuShortcut:true` in config rewrites Madwine's `*.desktop` on every launch.
- `madwine.log` line to watch for the chosen layer: `proton reused path=` / `using the copy from Steam`.
- Purely diagnostic Hyprland changes (e.g. `input:follow_mouse`) should be set at runtime with
  `hyprctl eval 'hl.config({...})'` and restored — 0.56 uses the Lua parser, so `hyprctl keyword`
  does not work.

## Continuation prompt for another agent

> Read `/home/taxin/Work/madwine-input-handoff.md`. The keyboard bug is **fixed and verified**
> by setting Wine's `HKCU\Software\Wine\X11 Driver\UseTakeFocus = N` in
> `~/.local/share/madwine/prefix/pfx/user.reg` (see “THE INPUT FIX”). Do not re-try Hyprland
> `allows_input` rules — they were tested and do not work. Remaining work: (1) verify the
> fullscreen mouse left-click bug in Roblox; (2) confirm `UseTakeFocus` persists across a Madwine
> restart (`grep UseTakeFocus` in `user.reg` after closing, then re-check `WM_HINTS` after relaunch).
> Madwine is on GE-Proton11-12 with the auto-updater installed; rollback layer is GE-Proton11-5.