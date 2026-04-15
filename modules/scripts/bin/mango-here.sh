#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: mango-here <tag> <monitor> <target>

Focus the target tag on the target monitor, then launch its mapped app only if
that tag is empty.
EOF
}

[[ $# -eq 3 ]] || {
  usage >&2
  exit 2
}

tag="$1"
monitor="$2"
target="$3"

[[ "${tag}" =~ ^[1-9]$ ]] || {
  echo "tag must be between 1 and 9" >&2
  exit 2
}

command -v mmsg >/dev/null 2>&1 || {
  echo "mmsg is required" >&2
  exit 1
}

browser_prefix="brave"
if [[ "${BROWSER:-}" == *"helium"* ]]; then
  browser_prefix="helium"
fi

launch_cmd=""
case "${target}" in
  Kenp)
    if command -v "start-${browser_prefix}-kenp" >/dev/null 2>&1; then
      launch_cmd="start-${browser_prefix}-kenp"
    elif command -v start-helium-kenp >/dev/null 2>&1; then
      launch_cmd="start-helium-kenp"
    elif command -v start-brave-kenp >/dev/null 2>&1; then
      launch_cmd="start-brave-kenp"
    fi
    ;;
  TmuxKenp)
    launch_cmd="start-kkenp"
    ;;
  Ai)
    if command -v "start-${browser_prefix}-ai" >/dev/null 2>&1; then
      launch_cmd="start-${browser_prefix}-ai"
    elif command -v start-brave-ai >/dev/null 2>&1; then
      launch_cmd="start-brave-ai"
    elif command -v start-helium-ai >/dev/null 2>&1; then
      launch_cmd="start-helium-ai"
    fi
    ;;
  CompecTA)
    if command -v "start-${browser_prefix}-compecta" >/dev/null 2>&1; then
      launch_cmd="start-${browser_prefix}-compecta"
    elif command -v start-brave-compecta >/dev/null 2>&1; then
      launch_cmd="start-brave-compecta"
    elif command -v start-helium-compecta >/dev/null 2>&1; then
      launch_cmd="start-helium-compecta"
    fi
    ;;
  WebCord)
    launch_cmd="start-webcord"
    ;;
  org.telegram.desktop)
    launch_cmd="telegram-desktop"
    ;;
  brave-youtube.com__-Default)
    if command -v "start-${browser_prefix}-youtube" >/dev/null 2>&1; then
      launch_cmd="start-${browser_prefix}-youtube"
    elif command -v start-brave-youtube >/dev/null 2>&1; then
      launch_cmd="start-brave-youtube"
    elif command -v start-helium-youtube >/dev/null 2>&1; then
      launch_cmd="start-helium-youtube"
    fi
    ;;
  spotify)
    launch_cmd="start-spotify"
    ;;
  ferdium)
    launch_cmd="start-ferdium"
    ;;
  discord)
    launch_cmd="start-discord"
    ;;
esac

mmsg -d "viewcrossmon,${tag},${monitor}"

if [[ -n "${launch_cmd}" ]]; then
  exec mmsg -d "spawn_on_empty,${launch_cmd},${tag}"
fi

exit 0
