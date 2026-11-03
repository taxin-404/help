# Madwine input bugs + GE-Proton auto-updater — progress handoff

_Last updated: 2026-11-03. Written so any AI/agent can resume with no prior context._

## TL;DR / current status

- **Goal A:** Make Madwine's compatibility layer (GE-Proton) always run the latest release, via a
  tool living in `github.com/taxin-404/madwine`. **DONE + pushed** (commit `305e8ec`).
- **Goal B:** Fix live input bugs (mouse left-click dying after a purchase button in fullscreen;
  keyboard dropping — now reported **in the Madwine launcher**). **NOT yet verified fixed.**
- **Blocker:** Madwine is still running **GE-Proton11-5**. The attempted switch via
  `"reuseSteamProton": true` was **inert**. The real fix (repoint `config.json.proton`) is ready
  but needs Madwine fully closed to apply.

## Root causes established (with evidence)

| # | Finding | Evidence |
|---|---------|----------|
| 1 | Madwine selects its layer from **`config.json` `"proton"`**, exported to umu as `PROTONPATH`. `"reuseSteamProton"` is **not** honoured for layer selection. | Settings `reuseSteamProton:true` had no effect; live env `PROTONPATH=.../madwine/proton/GE-Proton11-5-x86_64`; binary strings `using the copy from Steam`, `proton reused path=`. |
| 2 | The input bugs match GE-Proton11-12 fixes: *"X11: games no longer hang waiting for a pointer grab on focus changes"* (#920) and *"Fixed IME input (Fcitx5) freezing games"* (#798). Installed layer is 11-5. | User symptom cluster: left-click dies after a purchase modal in fullscreen; refocus restores keyboard but **not** mouse; disabling fullscreen restores mouse. `grabprobe` saw `pointer active grab: HELD BY ANOTHER CLIENT` in fullscreen, `FREE` when windowed. |
| 3 | This episode's keyboard drop is **not** Bongo and **not** a stuck key grab. | Active IM = `keyboard-us` (pass-through). `grabprobe`: `keyboard active grab: FREE`. |
| 4 | Launcher keyboard: `madwine-madium` window has `WM_HINTS Client accepts input or input focus: False` and offers `WM_TAKE_FOCUS` — the Wine focus handshake that can drop keyboard on refocus. It *can* take focus (verified: after activation X focus = `madium`; it selects `KeyPress`/`KeyRelease`). | `xprop -id <madium>`; `xdotool windowactivate`. Still unconfirmed whether 11-12 fixes it — must test. |

## Whats installed / where things live

### Madwine
- App version **0.1.22**; launcher binary `~/.local/share/madwine/Madwine.AppImage`.
- Config: `~/.config/madwine/config.json`
  - currently `"reuseSteamProton": true` (inert), `"proton": "~/.local/share/madwine/proton/GE-Proton11-5-x86_64"`.
- Layers dir: `~/.local/share/madwine/proton/` (contains `GE-Proton11-5-x86_64`).
- Launcher UI app is **`Madium.exe`** (Edge WebView2); window class `madwine-madium`; title `madium`.
- Game window class `madwine-roblox`; runs `RobloxPlayerBeta.exe`.
- Logs: `~/.local/state/madwine/madwine.log` (events: `win:`, `lock:`, `upd:`, `proton reused path=`),
  `~/.local/state/madwine/wine.log` (Wine/`PROTONPATH` output).

### GE-Proton11-12 (latest, released 2026-11-03)
- SHA-512 `2e37447902529c9fc39138dc0b3f24aed3513b59a190b825e6b4a668e49e2033bdf6b8a7998e8686e067bbb3f61f3a6633e2408f0cc96f6dad983bd18e2db31e`.
- Cached tarball (verified): `~/.cache/madwine-compat-update/GE-Proton11-12-x86_64.tar.gz` (566,859,228 bytes).
- **Installed but UNUSED** at `~/.local/share/Steam/compatibilitytools.d/GE-Proton11-12-x86_64`
  (left there by an earlier, wrong attempt). Needs moving into `~/.local/share/madwine/proton/`.

### The auto-updater tool
- Repo (pushed): **`github.com/taxin-404/madwine`** — branch `main`, commit `305e8ec`.
- Local clone: **`/tmp/opencode/madwine-repo`**.
- Files: `bin/madwine-compat-update`, `install.sh`, `uninstall.sh`,
  `systemd/madwine-compat-update.{service,timer}`, `README.md`, `LICENSE` (Unlicense).
- Behaviour: fetch latest GE-Proton → SHA-512 verify → install into
  `~/.local/share/madwine/proton/<tag>-x86_64/` → **set `config.json.proton`** (and clear
  `reuseSteamProton`) with a timestamped backup → prune older GE-Proton copies keeping the previous
  one as rollback (never touches non-GE-Proton layers). Refuses to run while Madwine/Wine/Roblox is
  live. Options: `--check`, `--dry-run`, `--force`, `--version <tag>`.
- Tested offline against a fake release: fresh install, no-op, checksum rejection, prune/rollback,
  dry-run — all pass. `shellcheck` clean.

### Diagnostics helpers
- `~/.local/bin/grabprobe` + source `~/.local/share/madwine-diag/grabprobe.c` — prints X
  keyboard/pointer grab state (`FREE` / `HELD BY ANOTHER CLIENT`) and current X focus.
- Extracted Madwine binary (for string archaeology):
  `/tmp/opencode/madwine-extract/squashfs-root/usr/bin/madwine`.
- fcitx5 Bongo addon is **patched** at `/usr/lib/fcitx5/libbongo.so`
  (sha256 `785994968236a6b278d12ec1cb5b1ecb942574e117380123bd88a2d91aee4590`).
  fcitx5 `DefaultIM=bongo` but **active IM is `keyboard-us`**. Not implicated this episode.

### Backups
- `~/.config/madwine/config.json.bak.20261103204543` (written when `reuseSteamProton` was set).
- `~/.config/madwine/config.json.preupdate-20261103204441` (manual pre-change copy).
- The tool writes `config.json.bak.<timestamp>` on each edit.

## Remaining steps (exact commands)

1. **Close Madwine fully.** Confirm nothing matches:
   ```bash
   pgrep -af 'Madwine\.AppImage|/madwine/umu/|wineserver|RobloxPlayerBeta\.exe|Madium\.exe'
   ```
   (An idle launcher with no window still counts — it overwrites `config.json` on exit.)
2. **Move the verified 11-12 into Madwine's own proton dir** (avoids a re-download):
   ```bash
   mv ~/.local/share/Steam/compatibilitytools.d/GE-Proton11-12-x86_64 \
      ~/.local/share/madwine/proton/
   ```
3. **Apply** (repoints `config.proton`, keeps 11-5 as rollback):
   ```bash
   ~/.local/bin/madwine-compat-update --version GE-Proton11-12
   # or just: madwine-compat-update            (uses latest release)
   ```
   Verify: `madwine-compat-update --check` → `status: UP TO DATE`.
4. **Relaunch Madwine.** Confirm the live layer:
   ```bash
   tr '\0' '\n' < /proc/$(pgrep -f 'proton waitforexitandrun' | head -1)/environ | grep PROTONPATH
   # expect: PROTONPATH=/home/taxin/.local/share/madwine/proton/GE-Proton11-12-x86_64
   ```
   First launch on a newer Proton may upgrade the Wine prefix (slower start).
5. **Test the bugs:** (a) launcher keyboard — click/type in `madium`; (b) mouse left-click after a
   purchase button in **fullscreen** Roblox; (c) keyboard after alt-tab.
6. **Enable the daily timer** (also installs the script to `~/.local/bin`):
   ```bash
   cd /tmp/opencode/madwine-repo && ./install.sh
   systemctl --user list-timers madwine-compat-update.timer
   ```
   (Safe to run any time — it defers while Madwine is live.)

## If the launcher keyboard is still broken after 11-12

Investigate, in order:
1. **`WM_TAKE_FOCUS` / focus handshake** — the `madium` window has
   `WM_HINTS input=False` + `WM_TAKE_FOCUS`. Check whether Hyprland delivers focus on click
   (compare with a normal window). Test: `xdotool windowactivate <madium>` then type.
2. **fcitx5/XIM** — temporarily test with the IME out of the picture:
   `XMODIFIERS= pkill -x Madwine.AppImage` then relaunch (or `fcitx5-remote -c` / stop fcitx5).
   If the keyboard returns, the culprit is XIM/IME handling, not Proton.
3. Re-run `~/.local/bin/grabprobe` while focused on the launcher to check for a rogue grab.

## Key gotchas

- **`reuseSteamProton` does nothing** for layer selection. Always set `config.json.proton`.
- Madwine **rewrites `config.json` on exit**; never edit it while the launcher is alive.
- `menuShortcut:true` in config rewrites Madwine's `*.desktop` on every launch.
- `madwine.log` line to watch for the chosen layer: `proton reused path=` / `using the copy from Steam`.
- Madwine **auto-updates the app** (`upd:` lines) but never the compatibility layer — that's the gap
  this tool fills.

## Continuation prompt for another agent

> Read `/home/taxin/Work/madwine-input-handoff.md`. Madwine (v0.1.22) is on GE-Proton11-5; the goal
> is to move it to GE-Proton11-12 by repointing `~/.config/madwine/config.json`'s `"proton"` field
> (never rely on `"reuseSteamProton"`), using the tool in `github.com/taxin-404/madwine`
> (`~/.local/bin/madwine-compat-update`). GE-Proton11-12 is already downloaded/verified in
> `~/.cache/madwine-compat-update/` and extracted (unused) at
> `~/.local/share/Steam/compatibilitytools.d/GE-Proton11-12-x86_64`. Close Madwine fully, move that
> dir into `~/.local/share/madwine/proton/`, run the updater, relaunch, then verify `PROTONPATH` and
> test the launcher keyboard + in-fullscreen mouse click.
