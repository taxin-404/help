-- Extra autostart processes.
-- o.launch_on_start("my-service")

hl.on("hyprland.start", function()
    hl.exec_cmd("hyprpm reload -n")
    hl.exec_cmd("lan-mouse daemon")
    hl.exec_cmd("rclone-manager")
end)
