-- hymission.lua — Mission Control setup for the hymission Hyprland plugin
-- https://github.com/gfhdhytghd/hymission
--
-- Install:
--   hyprpm update && hyprpm add https://github.com/gfhdhytghd/hymission
--   hyprpm enable hymission && hyprpm reload
--
-- Usage: put this file next to hyprland.lua (usually ~/.config/hypr/) and
-- add this line near the top of hyprland.lua:
--   require("hymission")
-- Needs Hyprland >= 0.55 (native Lua config). If you're still on the
-- hyprlang .conf format, the same keys work inside a
-- `plugin { hymission { ... } }` block instead.
--
-- From the plugin's own README: it runs inside the compositor process,
-- is largely AI-generated (author-audited), and may misbehave on Nvidia.

hl.config({
    plugin = {
        hymission = {
            -- Scope: show only the current Space per display, never every
            -- Space tiled together. only_active_monitor = 0 gives each
            -- connected display its own overview at once, matching macOS's
            -- default "Displays have Separate Spaces".
            only_active_workspace = 1,
            only_active_monitor   = 0,

            -- Spacing & Padding
            outer_padding_top = 50,
            outer_padding_bottom = 50,
            -- outer_padding_left = 32,
            -- outer_padding_right = 32,
            -- row_spacing = 24,
            -- column_spacing = 24,

            -- The Apple-style solver: keeps windows near where they already
            -- were and only nudges them apart to remove overlap.
            layout_engine = "mission-control",

            -- Plain open/close on repeated presses, not an Alt-Tab-style
            -- hold-and-cycle switcher.
            toggle_switch_mode = 0,

            -- Real Mission Control doesn't balloon the window under your
            -- cursor. Set this to 1 if you want that hycov/hyprexpo-style
            -- hover-expand effect instead.
            expand_selected_window = 1,

            -- backdrop_color/backdrop_blur default to fully transparent/off
            -- in this plugin, so they need setting for any dim at all. This
            -- gives a blurred, darkened desktop like Mission Control; tune
            -- the trailing alpha byte (99 of ff) to taste.
            backdrop_color = "rgba(00000099)",
            backdrop_blur  = 1,

            -- Hovering reveals a small "x" to close a window without
            -- switching to it, like real Mission Control. Off by default.
            close_button_enabled = 1,

            -- Spaces strip along the top, like macOS. It only appears while
            -- the overview is scoped to one workspace, which is our default now.
            workspace_strip_anchor = "top",
        },
    },
})

hl.unbind("SUPER + TAB")
hl.bind("SUPER + TAB", function()
    hl.plugin.hymission.toggle("forceall")
end)

hl.unbind("SUPER + SHIFT + TAB")
hl.bind("SUPER + SHIFT + TAB", function()
    hl.plugin.hymission.toggle("onlycurrentworkspace")
end)

-- 4-finger swipe up opens, swiping again (either direction) closes — the
-- classic macOS trackpad gesture.
hl.plugin.hymission.gesture({
    fingers   = 4,
    direction = "vertical",
    action    = "toggle",
})

-- Optional alternative to the gesture above: swipe up for the normal
-- current-Space view, swipe down for the "forceall" bonus view.
-- hl.plugin.hymission.gesture({
--     fingers   = 4,
--     direction = "vertical",
--     action    = "toggle",
--     recommand = true,
-- })

-- Only needed if you use Hyprland's permission system:
-- hl.permission("/usr/(bin|local/bin)/hyprpm", "plugin", "allow")
