#!/usr/bin/env bash
# ==============================================================================
# Script: osc-keyboard-layout.sh
# Description: Inspect or update the shared keyboard layout for TTY, Niri, and Hyprland.
# Usage: osc-keyboard-layout.sh status | set [preset|--layout L --variant V --tty-keymap K]
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
VCONSOLE_DST="/etc/vconsole.conf"

LAYOUT=""
VARIANT=""
OPTIONS="ctrl:nocaps"
TTY_KEYMAP=""
SCOPE="both"
SUDO=""

if [[ "$(id -u)" -ne 0 ]] && command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
fi

die() {
  echo "ERROR: $*" >&2
  exit 1
}

log() {
  echo "==> $*"
}

run_root() {
  if [[ -n "$SUDO" ]]; then
    "$SUDO" "$@"
  else
    "$@"
  fi
}

is_repo_root() {
  local candidate="$1"
  [[ -n "$candidate" ]] || return 1
  [[ -d "$candidate/modules" ]] || return 1
  [[ -d "$candidate/hosts" ]] || return 1
  [[ -f "$candidate/config.yaml" || -f "$candidate/hosts/hay.yaml" ]] || return 1
}

find_repo_root() {
  local candidate git_root
  local -a candidates=()

  [[ -n "${DCLI_REPO_ROOT:-}" ]] && candidates+=("${DCLI_REPO_ROOT}")
  [[ -n "${ARCH_CONFIG_ROOT:-}" ]] && candidates+=("${ARCH_CONFIG_ROOT}")
  candidates+=("${SCRIPT_DIR}" "$(pwd -P)" "${HOME}/.cachy" "${HOME}/.config/arch-config")

  for candidate in "${candidates[@]}"; do
    [[ -n "$candidate" ]] || continue
    candidate="$(cd -- "$candidate" 2>/dev/null && pwd -P || true)"
    [[ -n "$candidate" ]] || continue

    git_root="$(git -C "$candidate" rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -n "$git_root" ]] && is_repo_root "$git_root"; then
      printf '%s\n' "$git_root"
      return 0
    fi

    if is_repo_root "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

REPO_ROOT="$(find_repo_root)" || die "Unable to locate repo root. Set DCLI_REPO_ROOT or install the repo under ~/.cachy."
readonly REPO_ROOT
readonly NIRI_CFG="${REPO_ROOT}/modules/niri/dotfiles/niri/config.kdl"
readonly HYPR_CFG="${REPO_ROOT}/modules/hyprland/dotfiles/hypr/conf.d/30-input.conf"

usage() {
  cat <<'EOF'
Usage:
  osc-keyboard-layout status
  osc-keyboard-layout set trf
  osc-keyboard-layout set trq
  osc-keyboard-layout set us
  osc-keyboard-layout set --layout tr --variant f --tty-keymap trf
  osc-keyboard-layout set --layout us --variant '' --tty-keymap us
  osc-keyboard-layout set trf --repo-only
  osc-keyboard-layout set trf --live-only

Notes:
  - Repo scope updates:
      modules/niri/dotfiles/niri/config.kdl
      modules/hyprland/dotfiles/hypr/conf.d/30-input.conf
  - Live scope updates:
      /etc/vconsole.conf
  - If neither --repo-only nor --live-only is provided, both are updated.
  - Niri/Hyprland changes apply on next login or after reloading the compositor config.
  - TTY/login-manager changes apply immediately best-effort and definitely on next login.
EOF
}

require_repo_files() {
  [[ -f "$NIRI_CFG" ]] || die "Niri config not found: $NIRI_CFG"
  [[ -f "$HYPR_CFG" ]] || die "Hyprland input config not found: $HYPR_CFG"
}

infer_default_keymap() {
  case "${LAYOUT}:${VARIANT}" in
    tr:f)
      printf 'trf\n'
      ;;
    tr:q | tr:)
      printf 'trq\n'
      ;;
    *)
      printf '%s\n' "$LAYOUT"
      ;;
  esac
}

set_preset() {
  local preset="$1"
  case "$preset" in
    trf)
      LAYOUT="tr"
      VARIANT="f"
      TTY_KEYMAP="trf"
      ;;
    trq)
      LAYOUT="tr"
      VARIANT="q"
      TTY_KEYMAP="trq"
      ;;
    *)
      LAYOUT="$preset"
      VARIANT=""
      TTY_KEYMAP="$preset"
      ;;
  esac
}

show_status() {
  local niri_layout="" niri_variant="" niri_options=""
  local hypr_layout="" hypr_variant="" hypr_options=""
  local vc_layout="" vc_variant="" vc_keymap=""

  require_repo_files

  niri_layout="$(awk '/^[[:space:]]*layout "/ {gsub(/.*layout "|".*/,""); print; exit}' "$NIRI_CFG" 2>/dev/null || true)"
  niri_variant="$(awk '/^[[:space:]]*variant "/ {gsub(/.*variant "|".*/,""); print; exit}' "$NIRI_CFG" 2>/dev/null || true)"
  niri_options="$(awk '/^[[:space:]]*options "/ {gsub(/.*options "|".*/,""); print; exit}' "$NIRI_CFG" 2>/dev/null || true)"

  hypr_layout="$(awk -F= '/^[[:space:]]*kb_layout=/{print $2; exit}' "$HYPR_CFG" 2>/dev/null || true)"
  hypr_variant="$(awk -F= '/^[[:space:]]*kb_variant=/{print $2; exit}' "$HYPR_CFG" 2>/dev/null || true)"
  hypr_options="$(awk -F= '/^[[:space:]]*kb_options=/{print $2; exit}' "$HYPR_CFG" 2>/dev/null || true)"

  if [[ -r "$VCONSOLE_DST" ]]; then
    vc_layout="$(awk -F= '/^XKBLAYOUT=/{print $2; exit}' "$VCONSOLE_DST" 2>/dev/null || true)"
    vc_variant="$(awk -F= '/^XKBVARIANT=/{print $2; exit}' "$VCONSOLE_DST" 2>/dev/null || true)"
    vc_keymap="$(awk -F= '/^KEYMAP=/{print $2; exit}' "$VCONSOLE_DST" 2>/dev/null || true)"
  fi

  cat <<EOF
Repo-managed layout
  Niri:      layout=${niri_layout:-<unset>} variant=${niri_variant:-<unset>} options=${niri_options:-<unset>}
  Hyprland:  layout=${hypr_layout:-<unset>} variant=${hypr_variant:-<unset>} options=${hypr_options:-<unset>}

Live TTY/login-manager layout
  vconsole:  layout=${vc_layout:-<unset>} variant=${vc_variant:-<unset>} keymap=${vc_keymap:-<unset>}
EOF
}

write_if_changed() {
  local src="$1"
  local dst="$2"
  local mode="${3:-644}"

  if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
    rm -f "$src"
    return 0
  fi

  install -m "$mode" "$src" "$dst"
  rm -f "$src"
}

update_repo_niri() {
  local tmp
  tmp="$(mktemp)"

  LAYOUT="$LAYOUT" VARIANT="$VARIANT" OPTIONS="$OPTIONS" perl -0pe '
    my $layout = $ENV{LAYOUT};
    my $variant = $ENV{VARIANT};
    my $options = $ENV{OPTIONS};
    my $count = 0;
    $count += s/(keyboard\s*\{\s*xkb\s*\{.*?\blayout\s+")([^"]*)(")/$1.$layout.$3/se;
    $count += s/(keyboard\s*\{\s*xkb\s*\{.*?\bvariant\s+")([^"]*)(")/$1.$variant.$3/se;
    $count += s/(keyboard\s*\{\s*xkb\s*\{.*?\boptions\s+")([^"]*)(")/$1.$options.$3/se;
    END { exit($count >= 3 ? 0 : 1) }
  ' "$NIRI_CFG" >"$tmp" || die "Failed to update Niri keyboard block"

  write_if_changed "$tmp" "$NIRI_CFG" 644
}

update_repo_hyprland() {
  local tmp
  tmp="$(mktemp)"

  sed -E \
    -e "s/^([[:space:]]*kb_layout=).*/\1${LAYOUT}/" \
    -e "s/^([[:space:]]*kb_variant=).*/\1${VARIANT}/" \
    -e "s/^([[:space:]]*kb_options=).*/\1${OPTIONS}/" \
    "$HYPR_CFG" >"$tmp"

  write_if_changed "$tmp" "$HYPR_CFG" 644
}

update_live_vconsole() {
  local tmp
  tmp="$(mktemp)"

  if [[ ! -f "$VCONSOLE_DST" ]] && [[ -z "$SUDO" ]] && [[ "$(id -u)" -ne 0 ]]; then
    die "sudo is required to create $VCONSOLE_DST"
  fi

  if [[ -f "$VCONSOLE_DST" ]]; then
    awk -v layout="$LAYOUT" -v variant="$VARIANT" -v keymap="$TTY_KEYMAP" '
      BEGIN {
        has_layout = 0
        has_variant = 0
        has_keymap = 0
      }
      /^XKBLAYOUT=/ {
        print "XKBLAYOUT=" layout
        has_layout = 1
        next
      }
      /^XKBVARIANT=/ {
        print "XKBVARIANT=" variant
        has_variant = 1
        next
      }
      /^KEYMAP=/ {
        print "KEYMAP=" keymap
        has_keymap = 1
        next
      }
      { print }
      END {
        if (!has_layout) print "XKBLAYOUT=" layout
        if (!has_variant) print "XKBVARIANT=" variant
        if (!has_keymap) print "KEYMAP=" keymap
      }
    ' "$VCONSOLE_DST" >"$tmp"
  else
    printf 'XKBLAYOUT=%s\n' "$LAYOUT" >"$tmp"
    printf 'XKBVARIANT=%s\n' "$VARIANT" >>"$tmp"
    printf 'KEYMAP=%s\n' "$TTY_KEYMAP" >>"$tmp"
  fi

  if [[ -f "$VCONSOLE_DST" ]] && cmp -s "$tmp" "$VCONSOLE_DST"; then
    rm -f "$tmp"
  else
    run_root install -m 644 "$tmp" "$VCONSOLE_DST"
    rm -f "$tmp"
  fi

  if command -v loadkeys >/dev/null 2>&1; then
    run_root loadkeys "$TTY_KEYMAP" >/dev/null 2>&1 || true
  fi
  run_root systemctl restart systemd-vconsole-setup.service >/dev/null 2>&1 || true
}

apply_set() {
  [[ -n "$LAYOUT" ]] || die "--layout is required (or use a preset like: trf, trq, us)"
  [[ -n "$TTY_KEYMAP" ]] || TTY_KEYMAP="$(infer_default_keymap)"
  require_repo_files

  if [[ "$SCOPE" != "live" ]]; then
    log "Updating repo-managed Niri and Hyprland keyboard layout"
    update_repo_niri
    update_repo_hyprland
  fi

  if [[ "$SCOPE" != "repo" ]]; then
    log "Updating live TTY/login-manager keyboard layout"
    update_live_vconsole
  fi

  cat <<EOF
Applied keyboard layout
  layout=${LAYOUT}
  variant=${VARIANT}
  options=${OPTIONS}
  tty_keymap=${TTY_KEYMAP}
  scope=${SCOPE}
EOF
}

main() {
  local action="${1:-help}"
  shift || true

  case "$action" in
    status)
      show_status
      ;;
    set)
      if [[ $# -gt 0 && "${1:-}" != --* ]]; then
        set_preset "$1"
        shift
      fi

      while [[ $# -gt 0 ]]; do
        case "$1" in
          --layout)
            LAYOUT="${2:-}"
            shift 2
            ;;
          --variant)
            VARIANT="${2-}"
            shift 2
            ;;
          --options)
            OPTIONS="${2:-}"
            shift 2
            ;;
          --tty-keymap|--keymap)
            TTY_KEYMAP="${2:-}"
            shift 2
            ;;
          --repo-only)
            SCOPE="repo"
            shift
            ;;
          --live-only)
            SCOPE="live"
            shift
            ;;
          -h|--help|help)
            usage
            return 0
            ;;
          *)
            die "Unknown option: $1"
            ;;
        esac
      done

      apply_set
      ;;
    -h|--help|help|"")
      usage
      ;;
    *)
      die "Unknown command: $action"
      ;;
  esac
}

main "$@"
