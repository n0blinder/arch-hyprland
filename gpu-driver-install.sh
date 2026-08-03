#!/usr/bin/env bash
#
# Arch Linux + Hyprland - NVIDIA dGPU driver (ThinkPad P16v Gen1, RTX A500).
# Run this AFTER ./install.sh (and its reboot). It installs the open NVIDIA
# kernel modules and enables DRM modeset so the dGPU works under Wayland.
# It does NOT do battery/power tuning - run ./battery-optimize.sh for that.
#
# The AMD iGPU userspace (mesa) is installed by install.sh already; the
# desktop runs on AMD with or without this script. This just makes the
# discrete NVIDIA GPU available (e.g. for prime-run offload).
#
# Run as your NORMAL user (NOT root); it sudo's where needed.

set -euo pipefail

if [[ ${EUID} -eq 0 ]]; then
    echo "ERROR: run this as your normal user, not root." >&2
    exit 1
fi

log() { printf '\n\033[1;32m==>\033[0m \033[1m%s\033[0m\n' "$*"; }

sudo -v
( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
trap 'kill %1 2>/dev/null || true' EXIT

# ---------------------------------------------------------------------------
# 1. Install the NVIDIA driver stack (open kernel modules; Ampere+ supported)
# ---------------------------------------------------------------------------
NVIDIA_PKGS=(
    nvidia-open-dkms   # open kernel modules (RTX A500 = Ampere, supported)
    nvidia-utils       # userspace libraries
    nvidia-prime       # prime-run wrapper for on-demand offload
    egl-wayland        # EGLStream / Wayland integration
    linux-headers      # needed to build the dkms module
    dkms
)
log "Installing NVIDIA driver packages"
sudo pacman -Syu --needed --noconfirm "${NVIDIA_PKGS[@]}"

# ---------------------------------------------------------------------------
# 2. Enable DRM modeset (required for Wayland/Hyprland on NVIDIA)
# ---------------------------------------------------------------------------
log "Enabling NVIDIA DRM modeset"
sudo tee /etc/modprobe.d/nvidia.conf >/dev/null <<'EOF'
options nvidia_drm modeset=1 fbdev=1
EOF

# Early-load the modules so KMS is available at boot.
if ! grep -q 'nvidia_drm' /etc/mkinitcpio.conf; then
    sudo cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.bak
    sudo sed -i 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' \
        /etc/mkinitcpio.conf
fi

# ---------------------------------------------------------------------------
# 3. Rebuild initramfs
# ---------------------------------------------------------------------------
log "Regenerating initramfs (embeds the nvidia modules + modprobe.d)"
sudo mkinitcpio -P

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
cat <<'EOF'

============================================================
 NVIDIA driver installed. A REBOOT is required for modeset.

 After reboot, verify:
   cat /sys/module/nvidia_drm/parameters/modeset   # expect: Y
   nvidia-smi                                       # lists the RTX A500
   lsmod | grep nvidia
   glxinfo -B | grep "OpenGL renderer"              # still AMD/Radeon (desktop)
   prime-run glxinfo -B | grep "OpenGL renderer"    # NVIDIA (on-demand)

 THEN run ./battery-optimize.sh to suspend the idle dGPU for battery life.
============================================================
EOF

read -rp "Reboot now? [y/N] " ans
if [[ "${ans}" =~ ^[Yy]$ ]]; then
    sudo reboot
else
    echo "Reboot manually before running ./battery-optimize.sh: sudo reboot"
fi
