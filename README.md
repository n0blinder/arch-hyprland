# arch-hyprland

Post-install setup for a fully-configured **Hyprland** desktop on Arch Linux.

Takes a clean Arch install (everything **except** the GUI) and brings it up to a
ready-to-go Hyprland environment: packages, GPU drivers (AMD + NVIDIA hybrid),
services, dotfiles, and app configs.

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

Run as your **normal user** (not root — the script `sudo`s where needed):

```sh
sudo pacman -Sy --needed git
git clone https://github.com/n0blinder/arch-hyprland.git
cd arch-hyprland
./install.sh
```

The script is **idempotent** — if a step fails, fix it and just run it again.
It offers a single reboot at the end.

---

## What it does

- Installs all official + AUR packages (bootstraps `yay`).
- Deploys dotfiles (`.zshrc`, `.bashrc`, `starship.toml`) and sets `zsh` as the
  default shell.
- Deploys app configs to `~/.config`: **hypr** (Hyprland, Lua config), ashell,
  rofi, mako, alacritty.
- Installs GPU drivers:
  - **AMD (primary):** mesa, vulkan-radeon, VA-API/VDPAU video decode.
  - **NVIDIA (secondary):** `nvidia-open` (Ampere), modeset + RTD3 runtime
    power-off so the dGPU idles **suspended**; `prime-run` for on-demand use.
  - AMD is set as the primary render device (`AQ_DRM_DEVICES`, auto-detected).
- Sets up the login stack: **greetd + tuigreet**, launching Hyprland through
  **uwsm** as a managed systemd session; custom TTY colours via `vtrgb`.
- Enables services: bluetooth, auto-cpufreq (CPU power), ufw (deny incoming),
  hyprpolkitagent (user).

## Boot flow

```
greetd → tuigreet → uwsm start hyprland.desktop → Hyprland
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
- `follow3.txt` is the annotated, step-by-step reference that `install.sh`
  automates. `*.orig` files are backups of configs adjusted for this setup.
