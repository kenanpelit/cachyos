#!/usr/bin/env bash
# ==============================================================================
# Script: osc-keyboard-layout.sh
# Description: Inspect or update the shared keyboard layout for TTY and Margo.
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
  candidates+=("${SCRIPT_DIR}" "$(pwd -P)" "${HOME}/.cachy" "${HOME}/.config/mdots")

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
readonly MARGO_CFG="${REPO_ROOT}/modules/margo/dotfiles/margo/config.conf"

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
      modules/margo/dotfiles/margo/config.conf
  - Live scope updates:
      /etc/vconsole.conf
  - If neither --repo-only nor --live-only is provided, both are updated.
  - Margo changes apply on next login or after `mctl reload`.
  - TTY/login-manager changes apply immediately best-effort and definitely on next login.
EOF
}

require_repo_files() {
  [[ -f "$MARGO_CFG" ]] || die "Margo config not found: $MARGO_CFG"
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
      VARIANT=""
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
  local margo_layout="" margo_variant="" margo_options=""
  local vc_layout="" vc_variant="" vc_keymap=""

  require_repo_files

  # Margo's flat-key shape (`xkb_rules_layout = …`). The trim-space
  # pattern accepts `key = value` with optional whitespace around `=`
  # so config formatters that align on `=` still parse cleanly.
  margo_layout="$(awk -F= '/^[[:space:]]*xkb_rules_layout[[:space:]]*=/{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}' "$MARGO_CFG" 2>/dev/null || true)"
  margo_variant="$(awk -F= '/^[[:space:]]*xkb_rules_variant[[:space:]]*=/{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}' "$MARGO_CFG" 2>/dev/null || true)"
  margo_options="$(awk -F= '/^[[:space:]]*xkb_rules_options[[:space:]]*=/{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}' "$MARGO_CFG" 2>/dev/null || true)"

  if [[ -r "$VCONSOLE_DST" ]]; then
    vc_layout="$(awk -F= '/^XKBLAYOUT=/{print $2; exit}' "$VCONSOLE_DST" 2>/dev/null || true)"
    vc_variant="$(awk -F= '/^XKBVARIANT=/{print $2; exit}' "$VCONSOLE_DST" 2>/dev/null || true)"
    vc_keymap="$(awk -F= '/^KEYMAP=/{print $2; exit}' "$VCONSOLE_DST" 2>/dev/null || true)"
  fi

  cat <<EOF
Repo-managed layout
  Margo:     layout=${margo_layout:-<unset>} variant=${margo_variant:-<unset>} options=${margo_options:-<unset>}

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

# Margo's config formatter aligns `=` with surrounding spaces
# (`xkb_rules_layout  = tr`) — `\1` here captures everything up to
# and including the equals + trailing spaces, so we preserve the
# user's chosen alignment instead of collapsing it.
update_repo_margo() {
  local tmp
  tmp="$(mktemp)"

  sed -E \
    -e "s/^([[:space:]]*xkb_rules_layout[[:space:]]*=[[:space:]]*).*/\1${LAYOUT}/" \
    -e "s/^([[:space:]]*xkb_rules_variant[[:space:]]*=[[:space:]]*).*/\1${VARIANT}/" \
    -e "s/^([[:space:]]*xkb_rules_options[[:space:]]*=[[:space:]]*).*/\1${OPTIONS}/" \
    "$MARGO_CFG" >"$tmp"

  write_if_changed "$tmp" "$MARGO_CFG" 644
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

# Best-effort live reload of the margo compositor. `mctl` is the
# margo CLI; `mctl status` returns non-zero when no margo session
# is reachable, in which case there's nothing to reload (the new
# layout will apply on next margo login from the on-disk config).
# `--force` skips the pre-flight validator so a typo in an
# unrelated config block doesn't block a layout swap.
reload_live_margo() {
  command -v mctl >/dev/null 2>&1 || return 0
  mctl status >/dev/null 2>&1 || return 0
  mctl reload --force >/dev/null 2>&1 || true
}

apply_set() {
  [[ -n "$LAYOUT" ]] || die "--layout is required (or use a preset like: trf, trq, us)"
  [[ -n "$TTY_KEYMAP" ]] || TTY_KEYMAP="$(infer_default_keymap)"
  require_repo_files

  if [[ "$SCOPE" != "live" ]]; then
    log "Updating repo-managed Margo keyboard layout"
    update_repo_margo
    reload_live_margo
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
