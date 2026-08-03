-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
    -- Import the Hyprland environment into systemd/D-Bus services
    hl.exec_cmd(
        "dbus-update-activation-environment --systemd " ..
        "WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE"
    )

    hl.exec_cmd("hyprpaper")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("systemctl --user start hyprpolkitagent.service")
    hl.exec_cmd("ashell")

    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")

    -- Work around xdg-desktop-portal-hyprland CPU spike after login
    hl.exec_cmd([[sh -c '
        sleep 3
        systemctl --user restart xdg-desktop-portal-hyprland.service
        systemctl --user restart xdg-desktop-portal.service
    ']])
end)
