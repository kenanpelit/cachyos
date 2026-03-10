#!/usr/bin/env bash
# ==============================================================================
# Script: helium-install-extensions
# Description: Helper to open all standard extensions in Helium tabs for manual install.
# Usage: helium-install-extensions
# ==============================================================================

set -euo pipefail

# --- Extension List (Name: WebStore URL) ---
declare -A EXTENSIONS=(
    ["Checker Plus for Gmail"]="https://chromewebstore.google.com/detail/oeopbcgkkoapgobdbedcemjljbihmemj"
    ["Copy Link Address"]="https://chromewebstore.google.com/detail/mbcjcnomlakhkechnbhmfjhnnllpbmlh"
    ["Enhancer for YouTube"]="https://chromewebstore.google.com/detail/ponfpcnoihfmfllpaingbgckeeldkhle"
    ["Stylus"]="https://chromewebstore.google.com/detail/clngdbkpkpeebahjckkjfobafhncgmne"
    ["Surfingkeys"]="https://chromewebstore.google.com/detail/gfbliohnnapiefjpjlpjnehglfpaknnc"
    ["Video DownloadHelper"]="https://chromewebstore.google.com/detail/lmjnegcaeklhafolokijcfjliaokphfk"
    ["KeePassXC-Browser"]="https://chromewebstore.google.com/detail/oboonakemofpalcgghocfoadofidjkkk"
    ["Picture-in-Picture Viewer"]="https://chromewebstore.google.com/detail/pkehgijcmpdhfbdbbnkijodmdjhbjlgp"
    ["Quick Startpage"]="https://chromewebstore.google.com/detail/dgbkppglifchfjpombkeaijnpppcfibf"
    ["Tab Pinner"]="https://chromewebstore.google.com/detail/mlloloooolpffjkjaclpfpeednngpjon"
    ["Google Translate"]="https://chromewebstore.google.com/detail/aapbdbdomjkkjkaonfhkkikfgjllcleb"
    ["Ethereum Gas Prices"]="https://chromewebstore.google.com/detail/clmclmadaocoboebeghnmocajglcompj"
)

# --- Logic ---
echo "This script will open all standard extensions in your browser for manual installation."
echo "Choose your Helium profile when prompted (if multiple instances are running)."
echo "=========================================================="

for name in "${!EXTENSIONS[@]}"; do
    url="${EXTENSIONS[$name]}"
    echo "  -> Opening $name..."
    # Helium binary'sini kullanarak sekmeleri açıyoruz
    helium-browser "$url" >/dev/null 2>&1 &
    sleep 0.2
done

echo "=========================================================="
echo "Done! Please click 'Add to Chrome' for each extension."
echo "=========================================================="
