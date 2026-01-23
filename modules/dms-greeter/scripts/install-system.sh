#!/usr/bin/env bash
set -euo pipefail

# Resolve the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The dotfiles are in the parallel directory 'dotfiles'
CONFIG_DIR="$SCRIPT_DIR/../dotfiles"

echo "=========================================================="
echo " DMS Greeter Setup (System Level) "
echo "=========================================================="
echo "Using source directory: $CONFIG_DIR"
echo ""
echo "To enable the greeter, you must perform the following system-level steps:"
echo ""
echo "1. Ensure the 'greeter' user exists and has a valid home directory:"
echo "   sudo useradd -M -G video,input -d /var/lib/dms-greeter -s /bin/bash greeter || true"
echo "   sudo mkdir -p /var/lib/dms-greeter"
echo "   sudo chown -R greeter:greeter /var/lib/dms-greeter"
echo "   sudo chmod 755 /var/lib/dms-greeter"
echo ""
echo "2. Install the wrapper script:"
echo "   sudo install -m 755 $CONFIG_DIR/dms-greeter-wrapper /usr/local/bin/dms-greeter-wrapper"
echo ""
echo "3. Copy system configurations:"
echo "   sudo mkdir -p /etc/dms-greeter"
echo "   sudo cp $CONFIG_DIR/hyprland.conf /etc/dms-greeter/"
echo "   sudo cp $CONFIG_DIR/config.toml /etc/greetd/config.toml"
echo ""
echo "4. Enable greetd:"
echo "   sudo systemctl enable greetd"
echo ""
echo "Would you like to try running these commands with sudo now? (y/N)"
read -r response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    # Ensure configs exist
    if [ ! -f "$CONFIG_DIR/dms-greeter-wrapper" ]; then
        echo "Error: Config files not found in $CONFIG_DIR."
        exit 1
    fi

    # Check if greeter user exists and is a normal user (UID >= 1000)
    if id "greeter" &>/dev/null; then
        GREETER_UID=$(id -u greeter)
        if [ "$GREETER_UID" -ge 1000 ]; then
            echo "Removing existing normal user 'greeter' (UID $GREETER_UID) to recreate as system user..."
            sudo userdel greeter || true
        fi
    fi

    sudo useradd -r -M -G video,input -d /var/lib/dms-greeter -s /bin/bash greeter 2>/dev/null || echo "System user 'greeter' already exists."
    
    sudo mkdir -p /var/lib/dms-greeter
    sudo chown -R greeter:greeter /var/lib/dms-greeter
    sudo chmod 755 /var/lib/dms-greeter
    
    sudo install -m 755 "$CONFIG_DIR/dms-greeter-wrapper" /usr/local/bin/dms-greeter-wrapper
    
    sudo mkdir -p /etc/dms-greeter
    sudo mkdir -p /etc/greetd
    sudo cp "$CONFIG_DIR/hyprland.conf" /etc/dms-greeter/
    
    # Backup existing greetd config
    if [ -f /etc/greetd/config.toml ]; then
        sudo cp /etc/greetd/config.toml /etc/greetd/config.toml.bak
    fi
    sudo cp "$CONFIG_DIR/config.toml" /etc/greetd/config.toml
    
    echo "Configuration files installed."
    
    echo "Adding delay to greetd service to prevent race conditions..."
    sudo mkdir -p /etc/systemd/system/greetd.service.d
    echo "[Service]" | sudo tee /etc/systemd/system/greetd.service.d/override.conf
    echo "ExecStartPre=/usr/bin/sleep 3" | sudo tee -a /etc/systemd/system/greetd.service.d/override.conf
    sudo systemctl daemon-reload
    
    echo "Disabling other display managers (sddm, gdm, lightdm)..."
    sudo systemctl disable --now sddm 2>/dev/null || true
    sudo systemctl disable --now gdm 2>/dev/null || true
    sudo systemctl disable --now lightdm 2>/dev/null || true
    
    echo "Enabling greetd..."
    sudo systemctl enable greetd
    echo "Note: You may need to reboot or stop the current display manager manually if it's still running."
else
    echo "Skipping system-level installation."
fi
