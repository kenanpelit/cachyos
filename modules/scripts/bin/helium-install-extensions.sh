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
ISOLATED_BASE="${HOME}/.helium/isolated/${PROFILE}"
STANDART_BASE="${HOME}/.config/net.imput.helium/${PROFILE}"

# Search for valid profile directories (those containing a Preferences file)
VALID_PROFILES=()

if [[ -d "$ISOLATED_BASE" ]]; then
    while IFS= read -r pref_file; do
        VALID_PROFILES+=("$(dirname "$pref_file")")
    done < <(find "$ISOLATED_BASE" -maxdepth 3 -name "Preferences" 2>/dev/null)
fi

if [[ -d "$STANDART_BASE" ]]; then
    while IFS= read -r pref_file; do
        VALID_PROFILES+=("$(dirname "$pref_file")")
    done < <(find "$STANDART_BASE" -maxdepth 3 -name "Preferences" 2>/dev/null)
fi

if [[ ${#VALID_PROFILES[@]} -eq 0 ]]; then
    echo "Error: Profile '$PROFILE' not found or contains no valid Chromium profile data."
    echo "Checked in: $ISOLATED_BASE and $STANDART_BASE"
    exit 1
fi

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
for HELIUM_ROOT in "${VALID_PROFILES[@]}"; do
    EXT_DIR="${HELIUM_ROOT}/External Extensions"
    echo "=========================================================="
    echo "Installing extensions to: ${HELIUM_ROOT}"
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
done

echo "=========================================================="
echo "SUCCESS: Extensions registered."
echo "Please restart Helium profile '${PROFILE}' to complete installation."
echo "=========================================================="
