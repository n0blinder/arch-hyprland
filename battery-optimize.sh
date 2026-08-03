#!/usr/bin/env bash
#
# Arch Linux + Hyprland - BATTERY / GPU power tuning (ThinkPad P16v Gen1).
# Run this LAST, AFTER ./install.sh and ./gpu-driver-install.sh (+ reboots).
#
# Goal: run the desktop on the AMD iGPU and keep the NVIDIA dGPU SUSPENDED
# while idle, waking it only on demand (prime-run). CPU power management is
# already handled by auto-cpufreq (installed + enabled by install.sh).
#
# What it configures:
#   - NVIDIA RTD3 fine-grained runtime power management (NVreg_Dynamic...)
#   - udev rule setting power/control=auto so the idle dGPU can suspend
#   - (optional, printed only) pin AMD as the sole render device if the
#     dGPU still refuses to suspend
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

# Sanity: the NVIDIA driver must be installed first (gpu-driver-install.sh).
if ! command -v nvidia-smi >/dev/null 2>&1; then
    echo "ERROR: nvidia-smi not found. Run ./gpu-driver-install.sh (and reboot) first." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 1. NVIDIA RTD3 fine-grained runtime power management
# ---------------------------------------------------------------------------
log "Enabling NVIDIA RTD3 dynamic power management"
sudo tee /etc/modprobe.d/nvidia-pm.conf >/dev/null <<'EOF'
options nvidia NVreg_DynamicPowerManagement=0x02
EOF

# ---------------------------------------------------------------------------
# 2. udev rule: flip power/control to "auto" so the idle dGPU suspends
#    (nvidia-utils does not reliably ship this)
# ---------------------------------------------------------------------------
log "Installing RTD3 udev rule (power/control=auto)"
sudo tee /etc/udev/rules.d/80-nvidia-pm.rules >/dev/null <<'EOF'
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", TEST=="power/control", ATTR{power/control}="auto"
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="auto"
ACTION=="remove", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", TEST=="power/control", ATTR{power/control}="on"
ACTION=="remove", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="on"
EOF

# ---------------------------------------------------------------------------
# 3. Rebuild initramfs so the pm modprobe option is applied at early load
# ---------------------------------------------------------------------------
log "Regenerating initramfs"
sudo mkinitcpio -P

# ---------------------------------------------------------------------------
# 4. AMD-primary pin (OPTIONAL - printed, NOT applied automatically)
# ---------------------------------------------------------------------------
# Hyprland auto-selects the AMD iGPU (it drives the panel), so normally the
# dGPU is only woken on demand and suspends on its own via steps 1-2. If it
# stays active because Hyprland ALSO opened it, pin AMD as the sole render
# device. This is NOT applied automatically: forcing a wrong node black-
# screens the login, so apply + test it yourself only if needed.
log "AMD render node (for optional AMD-primary pin - only if dGPU won't sleep)"
amd_link=""
for link in /dev/dri/by-path/*-card; do
    [[ -e "${link}" ]] || continue
    card="$(basename "$(readlink -f "${link}")")"
    drv="$(basename "$(readlink -f "/sys/class/drm/${card}/device/driver" 2>/dev/null)")"
    [[ "${drv}" == "amdgpu" ]] && amd_link="${link}"
done
if [[ -n "${amd_link}" ]]; then
    echo "  amdgpu node: ${amd_link}"
    echo "  If the dGPU won't suspend, pin AMD-primary (then re-log & TEST):"
    echo "    echo 'AQ_DRM_DEVICES=${amd_link}' | sudo tee -a /etc/environment"
    echo "  If the desktop fails to start after that, remove the line again."
else
    echo "  No amdgpu node found (unexpected on the P16v)."
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
cat <<'EOF'

============================================================
 Battery / GPU power tuning applied. A REBOOT is required.

 After reboot, idle a few seconds, then verify the dGPU sleeps:
   for d in /sys/bus/pci/devices/*/; do \
     [ "$(cat $d/vendor 2>/dev/null)" = "0x10de" ] && \
     echo "ctrl=$(cat $d/power/control) status=$(cat $d/power/runtime_status)"; \
   done
   # want:  ctrl=auto  status=suspended

   glxinfo -B | grep "OpenGL renderer"            # AMD/Radeon (desktop)
   prime-run glxinfo -B | grep "OpenGL renderer"  # NVIDIA (wakes, then sleeps)

 CPU side: auto-cpufreq (from install.sh) manages governor + turbo:
   auto-cpufreq --stats
============================================================
EOF

read -rp "Reboot now? [y/N] " ans
if [[ "${ans}" =~ ^[Yy]$ ]]; then
    sudo reboot
else
    echo "Reboot manually when ready: sudo reboot"
fi
