hl.unbind("SUPER + TAB")
hl.bind("SUPER + TAB", function()
    hl.plugin.scrolloverview.overview("toggle")
end)

o.bind("SUPER + Q", "Open note", "omawrite ~/note.md")
hl.window_rule({
  name = "note-window",
  match = { class = "omawrite" },
  float = true,
  pin = true,
  size = "600 400",
  move = "63 400",
})

hl.unbind("SUPER + RETURN")
o.bind("SUPER + RETURN", "Tmux", "uwsm-app -- xdg-terminal-exec tmux new-session -A -s main")
