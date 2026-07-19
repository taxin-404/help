# Alt+Tab Fullscreen Fix

## Problem

Hyprland's `cyclenext` dispatcher silently fails when a window is in `fullscreen:2` state (e.g., FreeTube or a browser playing video fullscreen). It always refocuses the same window instead of cycling.

## Solution

Replace `cyclenext` with a custom script that queries all windows on the current workspace via `hyprctl clients -j`, calculates the next/previous index, and focuses using `hyprctl dispatch focuswindow address:...`.

## Files Changed

### 1. `~/.local/bin/alt-tab-fullscreen-fix.sh` (rewritten)

```bash
#!/usr/bin/env bash

CURRENT_WORKSPACE=$(hyprctl activeworkspace -j | jq '.id')
FOCUSED_ADDR=$(hyprctl activewindow -j | jq -r '.address')

WINDOWS=($(hyprctl clients -j | jq -r --argjson ws "$CURRENT_WORKSPACE" '
  [.[] | select(.workspace.id == $ws)] | sort_by(.address) | .[].address
'))

if [ ${#WINDOWS[@]} -le 1 ]; then
  exit 0
fi

CURRENT_IDX=-1
for i in "${!WINDOWS[@]}"; do
  if [ "${WINDOWS[$i]}" = "$FOCUSED_ADDR" ]; then
    CURRENT_IDX=$i
    break
  fi
done

if [ "$CURRENT_IDX" -eq -1 ]; then
  exit 0
fi

if [ "$1" = "prev" ]; then
  NEXT_IDX=$(( (CURRENT_IDX - 1 + ${#WINDOWS[@]}) % ${#WINDOWS[@]} ))
else
  NEXT_IDX=$(( (CURRENT_IDX + 1) % ${#WINDOWS[@]} ))
fi

hyprctl dispatch focuswindow "address:${WINDOWS[$NEXT_IDX]}"
```

### 2. `~/.config/hypr/bindings.conf` (added ALT+SHIFT+TAB)

```conf
unbind = ALT, TAB
bind = ALT, TAB, exec, ~/.local/bin/alt-tab-fullscreen-fix.sh prev
unbind = ALT SHIFT, TAB
bind = ALT SHIFT, TAB, exec, ~/.local/bin/alt-tab-fullscreen-fix.sh
```

## Keybindings

| Binding       | Action                        |
|---------------|-------------------------------|
| ALT+TAB       | Cycle windows right to left   |
| ALT+SHIFT+TAB | Cycle windows left to right   |

## Dependencies

- `jq` — JSON parsing for hyprctl output
- `hyprctl` — Hyprland control utility

## Apply

```bash
chmod +x ~/.local/bin/alt-tab-fullscreen-fix.sh
hyprctl reload
hyprctl configerrors
```
