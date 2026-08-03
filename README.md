# arch-hyprland

Post-install setup for a fully-configured **Hyprland** desktop on Arch Linux.

Takes a clean Arch install (everything **except** the GUI) and brings it up to a
ready-to-go Hyprland environment via **three focused scripts** — base desktop,
NVIDIA driver, and battery/GPU-power tuning — so each part can be run and
debugged on its own.

**Target hardware:** ThinkPad P16v Gen1 — AMD Ryzen 7 PRO 7840HS (Radeon 780M
iGPU) + NVIDIA RTX A500 (Ampere) dGPU. It will work on similar AMD-primary /
NVIDIA-secondary laptops, but the GPU handling is tuned for this machine.

---

## Prerequisites

A clean Arch install performed with `archinstall`, configured with **everything
except the GUI**:

- locale, partitions, swap, timezone, users + passwords
- **NetworkManager** (networking must already work)
- **No** desktop/Hyprland profile, **no** GPU-driver profile

Then reboot into the base system and log in on the TTY as your normal user.

---

## Usage

Run as your **normal user** (not root — the scripts `sudo` where needed).
Run them in order; each offers a reboot at the end and is idempotent (safe to
re-run):

```sh
sudo pacman -Sy --needed git
git clone https://github.com/n0blinder/arch-hyprland.git
cd arch-hyprland
chmod +x install.sh gpu-driver-install.sh battery-optimize.sh

./install.sh            # base desktop -> reboot -> greetd -> Hyprland (AMD iGPU)
./gpu-driver-install.sh # NVIDIA dGPU driver + modeset -> reboot
./battery-optimize.sh   # suspend the idle dGPU for battery -> reboot
```

You can stop after `install.sh` and have a **complete working desktop** on the
AMD iGPU; the other two scripts are additive. Full walkthrough: **`follow4.txt`**.

---

## The three scripts

**1. `install.sh` — base desktop.** All packages (official + AUR via `yay`),
dotfiles (`.zshrc`/`.bashrc`/`starship.toml`, `zsh` as default shell), app
configs to `~/.config` (**hypr** Lua config, ashell, rofi, mako, alacritty),
wallpaper, the greetd + tuigreet login (`--remember-session`, no custom
launcher), and `vtrgb` TTY colours. Enables bluetooth, `auto-cpufreq` (CPU
power), `ufw` (deny incoming), and `hyprpolkitagent`. Includes the **AMD iGPU
userspace** (`mesa`, `vulkan-radeon`, `libva-mesa-driver`) — required for
Hyprland to render — so this alone boots into a working desktop.

**2. `gpu-driver-install.sh` — NVIDIA dGPU.** Installs `nvidia-open-dkms`,
`nvidia-utils`, `nvidia-prime`, `egl-wayland`, `linux-headers`, `dkms`, enables
DRM `modeset`, rebuilds the initramfs. Reboot to activate.

**3. `battery-optimize.sh` — power tuning.** NVIDIA RTD3 runtime power-off
(`NVreg_DynamicPowerManagement` + a `power/control=auto` udev rule) so the idle
dGPU stays **suspended**, waking only on demand (`prime-run`). The desktop keeps
running on the AMD iGPU. Optionally prints how to pin `AQ_DRM_DEVICES` if the
dGPU still won't sleep.

## Boot flow

```
greetd → tuigreet (pick "Hyprland", remembered) → Hyprland
    → hyprpaper · hypridle · hyprpolkitagent · ashell · cliphist
```

---

## Post-reboot verification

```sh
cat /sys/module/nvidia_drm/parameters/modeset    # expect: Y
glxinfo -B | grep "OpenGL renderer"              # expect: AMD/Radeon
prime-run glxinfo -B | grep "OpenGL renderer"    # expect: NVIDIA

# idle dGPU should read "suspended":
lspci | grep -i nvidia                            # note the PCI address
cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status
```

---

## Notes

- **Battery:** `auto-cpufreq` manages the **CPU** (governor + turbo, AC-aware);
  the idle **dGPU** is powered off by the NVIDIA RTD3 config. The AMD iGPU scales
  with the APU power budget automatically (faster when plugged in).
- **External displays** on the P16v may be wired through the NVIDIA dGPU, so
  connecting one can wake it — expected behaviour.
- **Firewall:** ufw defaults to deny-incoming / allow-outgoing. `sshd` is
  installed but **not** enabled.
- **`follow4.txt`** is the step-by-step walkthrough of the three-script workflow;
  **`follow3.txt`** is the annotated rationale for every package/step. `*.orig`
  files are backups of configs adjusted for this setup.
