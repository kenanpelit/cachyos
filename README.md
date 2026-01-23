# CachyOS Declarative Configuration

<div align="center">
  <img src="https://img.shields.io/badge/CachyOS-Arch_Linux-blue?style=for-the-badge&logo=archlinux&logoColor=white" alt="CachyOS">
  <img src="https://img.shields.io/badge/Catppuccin-Mocha-mauve?style=for-the-badge&logo=catppuccin&logoColor=white" alt="Catppuccin">
  <img src="https://img.shields.io/badge/Manager-dcli-green?style=for-the-badge&logo=yaml&logoColor=white" alt="dcli">
</div>

## Overview

This repository contains a personal, declarative system configuration for **CachyOS** (Arch Linux), managed via the **dcli** tool. It provides a modular and reproducible environment, porting the declarative management philosophy of NixOS to the Arch Linux ecosystem.

## Core Features

- **Modular Architecture:** Self-contained modules for system components, ensuring high maintainability and portability.
- **Declarative Package Management:** Centralized definitions for system and AUR packages.
- **Advanced Window Management:**
  - **Niri:** Optimized scrollable tiling Wayland compositor.
  - **Hyprland:** Performance-tuned dynamic tiling Wayland compositor.
- **Unified Theming:** Consistent application of the Catppuccin Mocha palette across GTK, Qt (Kvantum), and various terminal emulators.
- **Automated Administration:** Integrated management for GRUB boot entries, Snapper snapshots, and system-level configurations.

## System Components

| Component | Implementation |
|-----------|----------------|
| **Operating System** | CachyOS (Arch Linux) |
| **Configuration Manager** | [dcli](https://gitlab.com/theblackdon/dcli) |
| **Compositors** | Niri, Hyprland |
| **Shell** | Zsh with Starship |
| **Theming** | Catppuccin Mocha |
| **File Management** | Yazi, Nemo |

## Directory Structure

```text
├── hosts/               # Host-specific configurations
├── modules/             # Modular system components
│   ├── admin/           # Administrative hooks (local only)
│   ├── grub/            # Bootloader configuration
│   ├── hyprland/        # Wayland compositor setup
│   ├── niri/            # Primary desktop environment
│   ├── gtk/qt/          # Toolkit consistent theming
│   └── ...
├── config.yaml          # Main entry point
└── .gitignore           # Version control exclusions
```

## Installation

### Prerequisites
- A functional CachyOS or Arch Linux installation.
- [dcli](https://gitlab.com/theblackdon/dcli) installed and available in system PATH.
- A valid AUR helper (paru recommended).

### Procedure

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/kenanpelit/cachyos.git ~/.cachy
    ```

2.  **Configure dcli path:**
    ```bash
    mkdir -p ~/.config/arch-config
    ln -s ~/.cachy/* ~/.config/arch-config/
    ```

3.  **Synchronize system state:**
    ```bash
    sudo -E dcli sync
    ```

4.  **Finalize:**
    Reboot or restart the user session to apply all environment variables and system changes.

## Credits

- **[dcli](https://gitlab.com/theblackdon/dcli):** Declarative configuration manager for Arch Linux.
- **[CachyOS](https://cachyos.org/):** Performance-oriented Arch Linux derivative.
- **[Catppuccin](https://github.com/catppuccin/catppuccin):** Aesthetic color palette.

---
<div align="center">
  Managed by <b><a href="https://gitlab.com/theblackdon/dcli">dcli</a></b>
</div>
