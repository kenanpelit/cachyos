# CachyOS Declarative Configuration

<div align="center">
  <img src="https://img.shields.io/badge/CachyOS-Arch_Linux-blue?style=for-the-badge&logo=archlinux&logoColor=white" alt="CachyOS">
  <img src="https://img.shields.io/badge/Catppuccin-Mocha-mauve?style=for-the-badge&logo=catppuccin&logoColor=white" alt="Catppuccin">
  <img src="https://img.shields.io/badge/Manager-dcli-green?style=for-the-badge&logo=yaml&logoColor=white" alt="dcli">
</div>

## Overview

Personal, declarative system configuration for **CachyOS** (Arch Linux) managed with **dcli**. The goal is a clean, modular, reproducible setup with minimal manual drift.

## Core Features

- **Modular Architecture:** Self-contained modules for system components, ensuring high maintainability and portability.
- **Declarative Package Management:** Centralized definitions for system and AUR packages.
- **Advanced Window Management:**
  - **Niri:** Optimized scrollable tiling Wayland compositor.
  - **Hyprland:** Performance-tuned dynamic tiling Wayland compositor.
- **Unified Theming:** Consistent application of the Catppuccin Mocha palette across GTK, Qt (Kvantum), and various terminal emulators.
- **System Automation:** Managed services, snapshots, and system-level configuration hooks.
- **System Hardening:** Optional firewall (ufw), fail2ban, and host blocking (hblock).
- **Kernel Tuning:** ThinkPad/Intel-specific modules and boot parameters via a dedicated kernel module.

## System Components

| Component | Implementation |
|-----------|----------------|
| **Operating System** | CachyOS (Arch Linux) |
| **Configuration Manager** | [dcli](https://gitlab.com/theblackdon/dcli) |
| **Compositors** | Niri, Hyprland |
| **Shell** | Zsh with Starship |
| **Theming** | Catppuccin Mocha |
| **File Management** | Yazi, Nemo |
| **Security** | ufw, fail2ban, hblock |
| **Kernel** | ThinkPad/Intel tuning (modules + GRUB params) |

## Directory Structure

```text
├── hosts/               # Host-specific configurations
├── modules/             # Modular system components
│   ├── admin/           # Administrative hooks (local only)
│   ├── grub/            # Bootloader configuration
│   ├── kernel/          # Kernel modules & GRUB parameters
│   ├── hyprland/        # Wayland compositor setup
│   ├── niri/            # Primary desktop environment
│   ├── firewall/        # ufw configuration
│   ├── fail2ban/        # fail2ban configuration
│   ├── hblock/          # hosts-based blocking
│   ├── gtk/qt/          # Toolkit consistent theming
│   └── ...
├── config.yaml          # Main entry point
└── .gitignore           # Version control exclusions
```

## Quick Start

```bash
git clone https://github.com/kenanpelit/cachyos.git ~/.cachy
mkdir -p ~/.config/arch-config
ln -s ~/.cachy/* ~/.config/arch-config/
sudo -E dcli sync
```

Restart your session (or reboot) to apply environment changes.

## Installation

### Prerequisites
- A functional CachyOS or Arch Linux installation.
- [dcli](https://gitlab.com/theblackdon/dcli) installed and available in system PATH.
- A valid AUR helper (paru recommended).

### Procedure

1.  **Clone the repository**
2.  **Link to dcli config root**
3.  **Run `dcli sync`**
4.  **Restart the session**

Commands are listed in **Quick Start**.

## Usage

- Enable/disable modules in `hosts/<hostname>.yaml`.
- Add/remove packages in `modules/*/packages.yaml`.
- Apply changes with `sudo -E dcli sync`.

## Notes

- This repo is tuned for personal hardware and workflows; review modules before applying on other machines.
  - Kernel tuning assumes a ThinkPad/Intel laptop; adjust `modules/kernel` if needed.

## Credits

- **[dcli](https://gitlab.com/theblackdon/dcli):** Declarative configuration manager for Arch Linux.
- **[CachyOS](https://cachyos.org/):** Performance-oriented Arch Linux derivative.
- **[Catppuccin](https://github.com/catppuccin/catppuccin):** Aesthetic color palette.

---
<div align="center">
  Managed by <b><a href="https://gitlab.com/theblackdon/dcli">dcli</a></b>
</div>
