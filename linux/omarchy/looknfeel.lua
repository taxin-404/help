-- Change the default Omarchy look'n'feel.

-- https://wiki.hypr.land/Configuring/Basics/Variables/#general
hl.config({
  plugin = {
    scrolloverview = {
      gesture_distance = 300, -- how far is the "max" for the gesture
      scale = 0.5, -- preferred overview scale
      workspace_gap = 100,
      layout = "vertical", -- vertical or horizontal
      wallpaper = 0, -- 0: global only, 1: per-workspace only, 2: both
      blur = true, -- blur only the main overview wallpaper

      shadow = {
        enabled = true,
        range = 50,
        -- render_power = 3,
        -- color = 0xee1a1a1a,
      },
    },
  },

  general = {
    -- No gaps between windows or borders.
    -- gaps_in = 0,
    -- gaps_out = 0,
    -- border_size = 0,

    -- Change to niri-like side-scrolling layout.
    layout = "scrolling",
  },
})

-- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
-- hl.config({
--   decoration = {
--     -- Use round window corners.
--     rounding = 8,
--
--     -- Dim unfocused windows (0.0 = no dim, 1.0 = fully dimmed).
--     dim_inactive = true,
--     dim_strength = 0.15,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#animations
-- hl.config({
--   animations = {
--     -- Disable all animations.
--     enabled = false,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#layout
-- hl.config({
--   layout = {
--     -- Avoid overly wide single-window layouts on wide screens.
--     single_window_aspect_ratio = { 1, 1 },
--   },
-- })

-- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/
-- hl.config({
--   scrolling = {
--     -- See only one column per screen instead of two.
--     column_width = 0.97,
--   },
-- })
