#!/usr/bin/env bash
#
# Arch Linux + Hyprland post-install setup (ThinkPad P16v Gen1).
# See follow3.txt for the annotated rationale behind every step.
#
# Run as your NORMAL user (NOT root) from inside the cloned repo:
#     sudo pacman -Sy --needed git
#     git clone <repo-url> && cd <repo-dir>
#     ./install.sh
#
# The script sudo's for privileged steps itself. It is idempotent and
# safe to re-run. A single reboot is offered at the end.

set -euo pipefail

# ---------------------------------------------------------------------------
# Preconditions + helpers
# ---------------------------------------------------------------------------
if [[ ${EUID} -eq 0 ]]; then
    echo "ERROR: run this as your normal user, not root (makepkg/yay refuse root)." >&2
    exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '\n\033[1;32m==>\033[0m \033[1m%s\033[0m\n' "$*"; }

# Cache sudo credentials and keep them alive for long AUR builds.
sudo -v
( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE_PID=$!
trap 'kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true' EXIT

# ---------------------------------------------------------------------------
# Package sets
# ---------------------------------------------------------------------------
OFFICIAL_PKGS=(
    # build tools
    base-devel git
    # hyprland core + session
    hyprland uwsm xdg-desktop-portal-hyprland xdg-desktop-portal xdg-utils
    qt5-wayland qt6-wayland hyprpolkitagent hyprpaper hypridle hyprlock
    # wayland utilities
    wl-clipboard cliphist grim slurp
    # desktop apps
    rofi mako alacritty nautilus swayimg firefox
    brightnessctl playerctl mousepad
    # audio
    wireplumber pipewire pipewire-pulse pavucontrol
    # nautilus extension (official)
    nautilus-image-converter
    # cli environment + helpers
    eza zoxide zsh starship fzf bat pacman-contrib mesa-utils nm-connection-editor
    vim nano wget openssh
    # fonts
    ttf-nerd-fonts-symbols ttf-jetbrains-mono-nerd
    # bluetooth
    bluez bluez-utils blueberry
    # firewall
    ufw
    # login manager + tty colours
    greetd greetd-tuigreet kbd
    # gpu: amd (primary)
    mesa vulkan-radeon vulkan-tools libva-mesa-driver mesa-vdpau
    # gpu: nvidia (secondary / offload)
    nvidia-open-dkms nvidia-utils nvidia-prime egl-wayland linux-headers dkms
    # auto-cpufreq dependency
    python-typing_extensions
)

AUR_PKGS=(
    ashell brave-bin mullvad-vpn-bin
    nautilus-admin-gtk4 nautilus-open-any-terminal
    auto-cpufreq
)

# ---------------------------------------------------------------------------
# 1. System update + official packages
# ---------------------------------------------------------------------------
log "Updating system and installing official packages"
sudo pacman -Syu --needed --noconfirm "${OFFICIAL_PKGS[@]}"

# ---------------------------------------------------------------------------
# 2. yay (AUR helper) + AUR packages
# ---------------------------------------------------------------------------
if ! command -v yay >/dev/null 2>&1; then
    log "Building yay (AUR helper)"
    tmp="$(mktemp -d)"
    git clone https://aur.archlinux.org/yay.git "${tmp}/yay"
    ( cd "${tmp}/yay" && makepkg -si --noconfirm )
    rm -rf "${tmp}"
fi

log "Installing AUR packages"
yay -S --needed --noconfirm "${AUR_PKGS[@]}"

# ---------------------------------------------------------------------------
# 3. Shell: dotfiles + default shell
# ---------------------------------------------------------------------------
log "Deploying shell dotfiles and setting zsh as default shell"
install -Dm644 "${REPO_DIR}/.bashrc"       "${HOME}/.bashrc"
install -Dm644 "${REPO_DIR}/.zshrc"        "${HOME}/.zshrc"
install -Dm644 "${REPO_DIR}/starship.toml" "${HOME}/.config/starship.toml"
if [[ "${SHELL:-}" != *zsh ]]; then
    sudo chsh -s "$(command -v zsh)" "${USER}"
fi

# ---------------------------------------------------------------------------
# 4. Application configs (~/.config)
# ---------------------------------------------------------------------------
log "Deploying application configs"
mkdir -p "${HOME}/.config"
for d in hypr ashell rofi mako alacritty; do
    rm -rf "${HOME}/.config/${d}"
    cp -r "${REPO_DIR}/.config/${d}" "${HOME}/.config/${d}"
done
# drop leftovers that must not be deployed
rm -f "${HOME}/.config/hypr/hyprland-default.bak" \
      "${HOME}/.config/hypr/.bashrc" \
      "${HOME}/.config/hypr/.zshrc"
# ashell ships a hardcoded /home/tony path -> retarget to this user
sed -i "s#/home/tony#${HOME}#g" "${HOME}/.config/ashell/config.toml"
# rofi launcher/applet scripts must be executable
chmod +x "${HOME}"/.config/rofi/launchers/*/launcher.sh 2>/dev/null || true
chmod +x "${HOME}"/.config/rofi/applets/bin/*.sh        2>/dev/null || true

# ---------------------------------------------------------------------------
# 5. Wallpaper
# ---------------------------------------------------------------------------
log "Installing wallpaper"
mkdir -p "${HOME}/Pictures/Wallpapers"
cp "${REPO_DIR}"/wallpaper/* "${HOME}/Pictures/Wallpapers/" 2>/dev/null || \
    echo "  (no image found in ${REPO_DIR}/wallpaper/ - skipping)"

# ---------------------------------------------------------------------------
# 6. Session launcher (uwsm) + greetd + tty colours
# ---------------------------------------------------------------------------
log "Installing session launcher, greetd config and vtrgb service"
sudo install -Dm755 "${REPO_DIR}/start-hyprland-session" /usr/local/bin/start-hyprland-session

# disable any pre-existing display manager (ignore if absent)
for dm in sddm gdm lightdm lxdm; do
    sudo systemctl disable --now "${dm}.service" 2>/dev/null || true
done
sudo install -Dm644 "${REPO_DIR}/greetd/config.toml" /etc/greetd/config.toml

# vtrgb: colour palette -> /etc/vtrgb, unit -> /etc/systemd/system
sudo install -Dm644 "${REPO_DIR}/vtrgb"         /etc/vtrgb
sudo install -Dm644 "${REPO_DIR}/vtrgb.service" /etc/systemd/system/vtrgb.service

# ---------------------------------------------------------------------------
# 7. NVIDIA module options + early KMS load
# ---------------------------------------------------------------------------
log "Configuring NVIDIA modeset + RTD3 power management"
sudo tee /etc/modprobe.d/nvidia.conf >/dev/null <<'EOF'
options nvidia_drm modeset=1 fbdev=1
options nvidia NVreg_DynamicPowerManagement=0x02
EOF

if ! grep -q 'nvidia_drm' /etc/mkinitcpio.conf; then
    sudo cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.bak
    sudo sed -i 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' \
        /etc/mkinitcpio.conf
fi

# ---------------------------------------------------------------------------
# 8. Hybrid GPU: make the AMD iGPU the primary render device
# ---------------------------------------------------------------------------
log "Setting AMD as primary render device (AQ_DRM_DEVICES)"
amd_link=""
others=""
for link in /dev/dri/by-path/*-card; do
    [[ -e "${link}" ]] || continue
    card="$(basename "$(readlink -f "${link}")")"          # e.g. card0
    drv="$(basename "$(readlink -f "/sys/class/drm/${card}/device/driver" 2>/dev/null)")"
    if [[ "${drv}" == "amdgpu" ]]; then
        amd_link="${link}"
    else
        others="${others:+${others}:}${link}"
    fi
done
mkdir -p "${HOME}/.config/uwsm"
if [[ -n "${amd_link}" ]]; then
    # by-path names are stable across boots (card numbering is not).
    echo "export AQ_DRM_DEVICES=${amd_link}${others:+:${others}}" > "${HOME}/.config/uwsm/env"
    echo "  AQ_DRM_DEVICES=${amd_link}${others:+:${others}}"
else
    echo "  WARNING: amdgpu DRM node not found; NOT writing AQ_DRM_DEVICES." >&2
    echo "  Set it manually in ~/.config/uwsm/env after checking /sys/class/drm." >&2
fi

# ---------------------------------------------------------------------------
# 9. Services
# ---------------------------------------------------------------------------
log "Enabling services"
sudo systemctl enable bluetooth.service
sudo systemctl enable auto-cpufreq.service
sudo systemctl enable greetd.service
sudo systemctl enable vtrgb.service

# firewall: deny incoming, allow outgoing (no port 4444)
sudo ufw --force default deny incoming
sudo ufw --force default allow outgoing
sudo ufw --force enable
sudo systemctl enable ufw.service

# nautilus "Open Terminal Here" -> alacritty
gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal 'alacritty' 2>/dev/null || true

# user service (also launched by autostart.lua; enabling is belt-and-suspenders)
systemctl --user enable hyprpolkitagent.service 2>/dev/null || true

# ---------------------------------------------------------------------------
# 10. Regenerate initramfs (picks up MODULES + modprobe.d) + reload
# ---------------------------------------------------------------------------
log "Regenerating initramfs"
sudo mkinitcpio -P
sudo systemctl daemon-reload

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
cat <<'EOF'

============================================================
 Setup complete.

 After reboot the flow is:
   greetd -> tuigreet -> uwsm start hyprland.desktop -> Hyprland

 Post-reboot verification:
   cat /sys/module/nvidia_drm/parameters/modeset   # expect: Y
   glxinfo -B | grep "OpenGL renderer"             # expect: AMD/Radeon
   prime-run glxinfo -B | grep "OpenGL renderer"   # expect: NVIDIA
   # idle dGPU should read "suspended":
   #   lspci | grep -i nvidia   (get PCI addr, e.g. 01:00.0)
   #   cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status
============================================================
EOF

read -rp "Reboot now? [y/N] " ans
if [[ "${ans}" =~ ^[Yy]$ ]]; then
    sudo reboot
else
    echo "Reboot manually when ready: sudo reboot"
fi
