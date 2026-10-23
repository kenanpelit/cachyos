#!/usr/bin/env bash
# ==============================================================================
# Script: osc-ytplay.sh
# Description: Play a geo-restricted YouTube URL (arg or clipboard) with mpv,
#              bypassing Mullvad VPN and forcing a PO-token-free client.
# ==============================================================================
set -euo pipefail

# `mshellctl play play` plays through the Mullvad tunnel with the web/web_safari
# client, which some region-locked videos reject with LOGIN_REQUIRED even with
# valid cookies — the block is tied to the VPN exit country, not the cookies.
# Bypassing the tunnel (mullvad-exclude) and forcing tv_simply/android_vr (the
# only clients that return formats without a GVS PO Token) fixes that case.
# Diagnosed 2026-10-23: see memory ytdlp-vpn-client-chain.

COOKIE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/yt-dlp/cookies-youtube.txt"

url="${1:-}"
if [[ -z "$url" ]]; then
  url="$(wl-paste -n 2>/dev/null || true)"
fi
[[ -n "$url" ]] || {
  echo "osc-ytplay: no URL given and clipboard is empty" >&2
  exit 1
}

exec mullvad-exclude mpv \
  --script-opts=ytdl_hook-ytdl_path=yt-dlp \
  --ytdl-raw-options=extractor-args="youtube:player_client=tv_simply",cookies="${COOKIE_FILE}",js-runtimes="deno",remote-components="ejs:github" \
  "$url"
