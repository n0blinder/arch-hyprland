: 1785751524:0;sudo pacman -S greetd greetd-tuigreet\
sudo systemctl disable --now sddm\
sudo systemctl enable --now greetd


: 1785752636:0;sudo pacman -S kbd

copy vtrgb file to /etc/

: 1785752673:0;sudo nano /etc/systemd/system/vtrgb.service

   1 │ [Unit]
   2 │ Description=Load custom virtual terminal colours
   3 │ Before=greetd.service
   4 │
   5 │ [Service]
   6 │ Type=oneshot
   7 │ ExecStart=/usr/bin/setvtrgb /etc/vtrgb
   8 │ RemainAfterExit=yes
   9 │
  10 │ [Install]
  11 │ WantedBy=multi-user.target

: 1785752701:0;sudo systemctl enable vtrgb.service
: 1785752741:0;sudo nano /usr/local/bin/start-hyprland-session

   1 │ #!/bin/sh
   2 │
   3 │ exec Hyprland

: 1785752756:0;sudo chmod +x /usr/local/bin/start-hyprland-session

: 1785752784:0;cd /run/media/tony/Storage/alacrity-backup/greetd

config.toml is 

[terminal]
vt = 1

[default_session]
command = "tuigreet --remember --asterisks --width 60 --theme 'border=magenta;text=cyan;prompt=green;time=red;action=blue;button=yellow;container=black;input=red' --cmd /usr/local/bin/start-hyprland-session"
user = "greeter"

then copy config.toml to /etc/greetd

reboot