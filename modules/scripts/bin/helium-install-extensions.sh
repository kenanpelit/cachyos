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

# Determine Helium root paths
ISOLATED_PATH="${HOME}/.helium/isolated/${PROFILE}/Default"
STANDART_PATH="${HOME}/.config/net.imput.helium/${PROFILE}"

# Find which one exists
if [[ -d "$ISOLATED_PATH" ]]; then
    HELIUM_ROOT="$ISOLATED_PATH"
elif [[ -d "$STANDART_PATH" ]]; then
    HELIUM_ROOT="$STANDART_PATH"
else
    echo "Error: Profile '$PROFILE' not found in isolated or standard paths."
    exit 1
fi

EXT_DIR="${HELIUM_ROOT}/External Extensions"

# --- Extension List (ID: Name) ---
# Extracted from Kenp profile on 2026-03-10
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
echo "Installing extensions to Helium profile: ${PROFILE}"
echo "Path: ${HELIUM_ROOT}"
echo "=========================================================="

mkdir -p "$EXT_DIR"

for id in "${!EXTENSIONS[@]}"; do
    name="${EXTENSIONS[$id]}"
    echo "  -> Adding $name ($id)..."
    
    # Create the JSON file that tells Helium to download the extension
    echo '{
        "external_update_url": "https://clients2.google.com/service/update2/crx"
    }' > "${EXT_DIR}/${id}.json"
done

echo "=========================================================="
echo "SUCCESS: Extensions registered."
echo "Please restart Helium profile '${PROFILE}' to complete installation."
echo "=========================================================="
