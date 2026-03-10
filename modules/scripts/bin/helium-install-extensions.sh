#!/usr/bin/env bash
# ==============================================================================
# Script: helium-install-extensions
# Description: Installs a standard set of extensions to a specific Helium profile.
# Usage: helium-install-extensions [profile_name]
# ==============================================================================

set -euo pipefail

# --- Configuration ---
PROFILE="${1:-}"

if [[ -z "$PROFILE" ]]; then
    echo "Usage: $0 [profile_name]"
    echo "Example: $0 Kenp"
    exit 1
fi

# Determine Helium User Data Directory (UDD)
ISOLATED_BASE="${HOME}/.helium/isolated/${PROFILE}"
STANDART_BASE="${HOME}/.config/net.imput.helium"

# Determine which UDD to use
if [[ -d "$ISOLATED_BASE" ]]; then
    UDD_ROOT="$ISOLATED_BASE"
elif [[ "$PROFILE" == "Default" && -d "$STANDART_BASE" ]]; then
    UDD_ROOT="$STANDART_BASE"
else
    # Fallback: Check if the provided name is a standard profile but not isolated
    if [[ -d "$STANDART_BASE/$PROFILE" ]]; then
        UDD_ROOT="$STANDART_BASE"
    else
        echo "Error: Could not find User Data Directory for profile '$PROFILE'."
        echo "Checked: $ISOLATED_BASE"
        exit 1
    fi
fi

# IMPORTANT: External Extensions must be in the ROOT of the User Data Directory
EXT_DIR="${UDD_ROOT}/External Extensions"

# --- Extension List (ID: Name) ---
declare -A EXTENSIONS=(
    ["oeopbcgkkoapgobdbedcemjljbihmemj"]="Checker Plus for Gmail"
    ["mbcjcnomlakhkechnbhmfjhnnllpbmlh"]="Copy Link Address"
    ["ponfpcnoihfmfllpaingbgckeeldkhle"]="Enhancer for YouTube"
    ["clngdbkpkpeebahjckkjfobafhncgmne"]="Stylus"
    ["gfbliohnnapiefjpjlpjnehglfpaknnc"]="Surfingkeys"
    ["lmjnegcaeklhafolokijcfjliaokphfk"]="Video DownloadHelper"
    ["oboonakemofpalcgghocfoadofidjkkk"]="KeePassXC-Browser"
    ["pkehgijcmpdhfbdbbnkijodmdjhbjlgp"]="Picture-in-Picture Viewer"
    ["dgbkppglifchfjpombkeaijnpppcfibf"]="Quick Startpage"
    ["mlloloooolpffjkjaclpfpeednngpjon"]="Tab Pinner"
    ["aapbdbdomjkkjkaonfhkkikfgjllcleb"]="Google Translate"
    ["clmclmadaocoboebeghnmocajglcompj"]="Ethereum Gas Prices"
)

# --- Logic ---
echo "=========================================================="
echo "Installing extensions to User Data Dir: ${UDD_ROOT}"
echo "=========================================================="

mkdir -p "$EXT_DIR"

for id in "${!EXTENSIONS[@]}"; do
    name="${EXTENSIONS[$id]}"
    echo "  -> Adding $name ($id)..."
    
    # Create the JSON file that tells Helium to download the extension
    echo '{
        "external_update_url": "https://clients2.google.com/service/update2/crx"
    }' > "${EXT_DIR}/${id,,}.json"
done

echo "=========================================================="
echo "SUCCESS: Extensions registered in $EXT_DIR"
echo "Please restart Helium profile '${PROFILE}'."
echo "Note: You may need to manually 'Enable' them in the browser menu."
echo "=========================================================="
