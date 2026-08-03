#!/usr/bin/env bash
#
# Arch Linux + Hyprland - BASE DESKTOP install (ThinkPad P16v Gen1).
# Packages, services, dotfiles and configuration. Includes the AMD iGPU
# userspace (mesa) because Hyprland needs it to render the desktop.
# Does NOT install the NVIDIA dGPU driver or any power tuning - those are
# separate scripts (see follow4.txt):
#     1. ./install.sh              <- you are here (reboot -> working desktop)
#     2. ./gpu-driver-install.sh   <- NVIDIA dGPU driver
#     3. ./battery-optimize.sh     <- dGPU suspend / battery tuning
#
# Run as your NORMAL user (NOT root) from inside the cloned repo:
#     sudo pacman -Sy --needed git
#     git clone https://github.com/n0blinder/arch-hyprland.git
#     cd arch-hyprland && ./install.sh
#
# Idempotent and safe to re-run. Offers a reboot at the end.

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
    hyprland xdg-desktop-portal-hyprland xdg-desktop-portal xdg-utils
    qt5-wayland qt6-wayland hyprpolkitagent hyprpaper hypridle hyprlock
    # wayland utilities
    wl-clipboard cliphist grim slurp
    # desktop apps (papirus-icon-theme = rofi launcher icons)
    rofi papirus-icon-theme mako alacritty nautilus swayimg firefox
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
    # bluetooth (blueberry is AUR - see AUR_PKGS)
    bluez bluez-utils
    # firewall
    ufw
    # login manager + tty colours
    greetd greetd-tuigreet kbd
    # AMD iGPU userspace - REQUIRED for Hyprland to render (drives the panel)
    mesa vulkan-radeon vulkan-tools libva-mesa-driver
    # auto-cpufreq dependency (CPU power mgmt; enabled below)
    python-typing_extensions
)

AUR_PKGS=(
    ashell brave-bin mullvad-vpn-bin blueberry
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
# 6. greetd + tty colours
# ---------------------------------------------------------------------------
# No custom launcher: greetd/tuigreet launches the distro's own Hyprland
# wayland-session directly (tuigreet --remember-session picks it up).
log "Installing greetd config and vtrgb service"

# disable any pre-existing display manager (ignore if absent)
for dm in sddm gdm lightdm lxdm; do
    sudo systemctl disable --now "${dm}.service" 2>/dev/null || true
done
sudo install -Dm644 "${REPO_DIR}/greetd/config.toml" /etc/greetd/config.toml

# vtrgb: colour palette -> /etc/vtrgb, unit -> /etc/systemd/system
sudo install -Dm644 "${REPO_DIR}/vtrgb"         /etc/vtrgb
sudo install -Dm644 "${REPO_DIR}/vtrgb.service" /etc/systemd/system/vtrgb.service

# ---------------------------------------------------------------------------
# 7. Services
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

sudo systemctl daemon-reload

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
cat <<'EOF'

============================================================
 Base desktop installed.

 After reboot: greetd -> tuigreet (pick "Hyprland", remembered) -> Hyprland
 (Runs on the AMD iGPU. No NVIDIA driver yet - that's the next script.)

 NEXT STEPS (from the repo dir):
   ./gpu-driver-install.sh   # install the NVIDIA dGPU driver, then reboot
   ./battery-optimize.sh     # suspend the idle dGPU for battery, then reboot
============================================================
EOF

read -rp "Reboot into the desktop now? [y/N] " ans
if [[ "${ans}" =~ ^[Yy]$ ]]; then
    sudo reboot
else
    echo "Reboot manually when ready: sudo reboot"
fi
