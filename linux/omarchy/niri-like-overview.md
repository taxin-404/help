# Niri-Like Overview in Hyprland

A setup combining Hyprland's **scrolling layout** with the **hyprland-scroll-overview** plugin to replicate a Niri-style tiling and overview experience.

---

## Components

| Component | Purpose |
|-----------|---------|
| `layout = scrolling` | Niri-style single-column scrolling tiling (replaces dwindle) |
| `scrolloverview` plugin | Zoomed-out overview of all workspaces |
| `SUPER + TAB` | Toggle overview on/off |

---

## 1. Install the Plugin

Before you continue:

```bash
sudo pacman -S cmake
hyprpm update
```
### main installation:

```bash
hyprpm add https://github.com/yayuuu/hyprland-scroll-overview.git
hyprpm update
hyprpm enable scrolloverview
```

Verify it's loaded:

```bash
hyprpm list
```

---

## 2. Load the Plugin

In `~/.config/hypr/hyprland.conf`, add before any config sources:

```lua
-- Load hyprpm plugins on Hyprland startup
hl.on("hyprland.start", function()
    hl.exec_cmd("hyprpm reload -n")
end)
```

---

## 3. Scrolling Layout

In `~/.config/hypr/looknfeel.conf`:

```conf
general {
    layout = scrolling
}

scrolling {
    # column_width = 0.97  # uncomment for near-fullscreen columns
}
```

Default `column_width` is `0.49` (half-screen columns). Comment it out or adjust as needed.

---

## 4. Plugin Configuration

In `~/.config/hypr/autostart.conf`:

```lua
-- .config/hypr/hyprland.lua
hl.config({
    plugin = {
        scrolloverview = {
            gesture_distance = 300, -- how far is the "max" for the gesture
            scale = 0.5, -- preferred overview scale
            workspace_gap = 100,
            layout = "vertical", -- vertical or horizontal
            wallpaper = 0, -- 0: global only, 1: per-workspace only, 2: both
            blur = false, -- blur only the main overview wallpaper

            shadow = {
                enabled = false,
                range = 50,
                render_power = 3,
                color = 0xee1a1a1a,
            },
        },
    },
})
```

---

## 5. Keybindings

In `~/.config/hypr/bindings.conf`:

```conf
# Toggle scroll overview
unbind = SUPER, TAB
bind = SUPER, TAB, scrolloverview:overview, toggle
```

> **Note:** `SUPER + TAB` was originally bound to "Next workspace" in Omarchy defaults.
> The `unbind` removes the default, and the new `bind` remaps it to overview toggle.

**Workspace navigation still works with:**

| Binding | Action |
|---------|--------|
| `SUPER + SHIFT + TAB` | Previous workspace |
| `SUPER + CTRL + TAB` | Former workspace |

---

## 6. Touchpad Gestures (Optional)

In `~/.config/hypr/input.conf`, uncomment for gesture support:

```conf
# 3-finger horizontal swipe to switch workspaces
gesture = 3, horizontal, workspace

# 3-finger swipe to move focus in scrolling layout
gesture = 3, left, dispatcher, movefocus, l
gesture = 3, right, dispatcher, movefocus, r
```

---

## Reload & Validate

```bash
hyprctl reload
hyprctl configerrors
```

If errors appear, fix the config and re-run until clean.

---

## File Reference

| File | What it configures |
|------|--------------------|
| `~/.config/hypr/hyprland.conf` | Plugin loading |
| `~/.config/hypr/looknfeel.conf` | Scrolling layout |
| `~/.config/hypr/autostart.conf` | Plugin settings block |
| `~/.config/hypr/bindings.conf` | SUPER+TAB overview toggle |
| `~/.config/hypr/input.conf` | Gestures & scroll speed |

---

## Troubleshooting

**Plugin not loading:**
```bash
hyprpm list                    # check plugin status
hyprpm enable hyprland-scroll-overview
hyprctl reload
```

**Overview not appearing:**
- Confirm `SUPER + TAB` binding has `unbind` before `bind`
- Check `hyprctl configerrors` for syntax issues

**Layout not scrolling:**
- Ensure `general { layout = scrolling }` is set in `looknfeel.conf`
- Verify it's sourced **after** the default `looknfeel.conf` in `hyprland.conf`

**Reset to defaults:**
```bash
omarchy refresh hyprland
```
