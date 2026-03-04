<h1 align="center">CachyOS Declarative Configuration</h1>

<div align="center">
  <img src="https://img.shields.io/badge/CachyOS-Arch_Linux-blue?style=for-the-badge&logo=archlinux&logoColor=white" alt="CachyOS">
  <img src="https://img.shields.io/badge/Manager-dcli-green?style=for-the-badge&logo=yaml&logoColor=white" alt="dcli">
  <img src="https://img.shields.io/badge/Host-hay-orange?style=for-the-badge" alt="hay">
  <img src="https://img.shields.io/badge/Wayland-Niri%20%2B%20Hyprland-1f6feb?style=for-the-badge" alt="Niri + Hyprland">
</div>

<p align="center">
  <strong>Declarative, modular, and operations-focused workstation configuration for CachyOS, powered by <a href="https://gitlab.com/theblackdon/dcli">dcli</a>.</strong>
</p>

## Overview

This repository is the source of truth for one production desktop host (`hay`).
It manages system packages, desktop sessions, user services, shell tooling, MIME/default apps, and day-2 operations through composable modules.

Core goals:

- reproducibility: minimize configuration drift
- modularity: small, focused, reusable modules
- operational discipline: explicit runbooks and service orchestration

## Architecture

The configuration model is intentionally simple:

- `config.yaml`: active host pointer
- `hosts/hay.yaml`: ordered module stack and host-level settings
- `modules/<name>/`: implementation units

Typical module contract:

- `module.yaml`: metadata and hook behavior
- `packages.yaml`: package sources (repo/AUR/flatpak depending on module)
- `dotfiles/`: managed files
- `scripts/`: install/post-install logic

## Repository Map

```text
.
├── config.yaml
├── hosts/
│   └── hay.yaml
├── modules/
│   ├── base, pacman, paru, packages, system-packages-hay
│   ├── admin, logind, tty, logs, kernel, firewall, fail2ban, blocky, tcp, oomd
│   ├── zsh, bash, git, nvim, tmux, yazi, fzf, fastfetch, btop, lazygit, ...
│   ├── niri, hyprland, sway, sessions, stasis, xdg-portal, dms, noctalia, ...
│   ├── mpv, mpd, rmpc, transmission, cava, ytdlp, radio, subliminal
│   └── xdg-mimes, user-services, scripts, flatpak, copyq, brave, webcord, ai
└── docs/
    └── OPERATIONS.md
```

## Active Host Profile (`hay`)

`hosts/hay.yaml` currently enables:

- bootstrap/core: `base`, `pacman`, `paru`, `scripts`, `packages`, `flatpak`, `system-packages-hay`
- system/security: `admin`, `logind`, `tty`, `logs`, `kernel`, `firewall`, `fail2ban`, `blocky`, `tcp`, `oomd`
- shell/cli: `zsh`, `bash`, `git`, `nvim`, `tmux`, `yazi`, `sesh`, `clipse`, `starship`, `command-not-found`
- desktop: `niri`, `hyprland`, `sway`, `sessions`, `stasis`, `xdg-portal`, `rofi`, `walker`, `dms`, `noctalia`, `gdm`, `fusuma`
- media/apps: `mpv`, `mpd`, `rmpc`, `transmission`, `cava`, `brave`, `webcord`, `copyq`, `ai`
- defaults/services: `xdg-mimes`, `user-services`

## Quick Start

### 1) Clone

```bash
git clone --recurse-submodules https://github.com/kenanpelit/cachyos.git ~/.cachy
```

### 2) Register as dcli root

```bash
mkdir -p ~/.config
ln -sfn ~/.cachy ~/.config/arch-config
```

### 3) Apply

```bash
cd ~/.cachy
sudo -E dcli sync
```

## Daily Operations

Update + apply:

```bash
cd ~/.cachy
git pull --rebase
git submodule update --init --recursive
sudo -E dcli sync
```

Capture unmanaged installs into a host module:

```bash
dcli merge
```

Operational checks:

- runbook: `docs/OPERATIONS.md`
- active host: `config.yaml`
- host stack: `hosts/hay.yaml`

## TTY and Session Routes

TTY routes are managed via `zsh/.zprofile` and helper scripts:

- `tty2`: Niri
- `tty3`: Hyprland
- `tty4`: GNOME
- `tty5`: Sway VM profile
- `tty6`: manual mode + launcher (`exec osc-tty-launcher`)

For VM routes from TTY, Sway `qemu_vm*` profiles are preferred.

## Submodules Policy

This repository uses git submodules for third-party/plugin code (for example under `modules/dms/.../plugins` and tmux plugin paths).

Use:

```bash
git submodule update --init --recursive
```

after clone, pull, and branch switches.

## Portability Checklist

Before applying on a different machine, review:

- `hosts/<new-host>.yaml`
- `modules/kernel/`
- `modules/firewall/`
- `modules/blocky/`
- `modules/sessions/`
- hardware-specific desktop/service modules (`niri`, `hyprland`, `stasis`, `fusuma`, `gdm` or `dms-greeter`)

## License

MIT (`LICENSE`).

## Credits

- [dcli](https://gitlab.com/theblackdon/dcli)
- [CachyOS](https://cachyos.org/)
