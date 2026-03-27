#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
TARGET_DMS_DIR="${XDG_CONFIG_HOME}/niri/dms"
TARGET_FILE="${TARGET_DMS_DIR}/workspaces-auto.kdl"

find_repo_root() {
  local candidates=()
  local here=""

  if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    candidates+=("$(cd -- "${here}/../.." && pwd)")
  fi

  candidates+=(
    "$HOME/.cachy"
    "$HOME/.config/arch-config"
  )

  local candidate=""
  for candidate in "${candidates[@]}"; do
    [[ -f "${candidate}/modules/niri/scripts/render-profile.sh" ]] || continue
    printf '%s\n' "$candidate"
    return 0
  done

  return 1
}

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME <command>

Commands:
  status                         Show current Niri workspace mode
  current|managed|with-workspaces
                                 Render/apply repo-managed static workspaces
  natural|plain|dynamic|no-workspaces
                                 Remove static workspace mapping and use Niri defaults

Examples:
  $SCRIPT_NAME status
  $SCRIPT_NAME managed
  $SCRIPT_NAME natural
EOF
}

ensure_target_dir() {
  mkdir -p "${TARGET_DMS_DIR}"
}

workspace_count() {
  [[ -f "${TARGET_FILE}" ]] || {
    printf '0\n'
    return 0
  }

  grep -c '^workspace "' "${TARGET_FILE}" 2>/dev/null || printf '0\n'
}

current_mode() {
  local count
  count="$(workspace_count)"
  if [[ "${count}" -gt 0 ]]; then
    printf 'managed\n'
  else
    printf 'natural\n'
  fi
}

reload_niri_config() {
  command -v niri >/dev/null 2>&1 || return 0
  niri msg action load-config-file >/dev/null 2>&1 || true
}

write_natural_file() {
  ensure_target_dir
  cat > "${TARGET_FILE}" <<'EOF'
// Dynamic workspace mode enabled by osc-niri-workspaces-mode.
// This file is intentionally empty so Niri uses its natural/dynamic workspace behavior.
// Run `osc-niri-workspaces-mode managed` to restore repo-managed static workspace placement.
EOF
}

show_status() {
  local mode count
  mode="$(current_mode)"
  count="$(workspace_count)"

  printf 'Niri workspace mode\n'
  printf '  mode: %s\n' "${mode}"
  printf '  file: %s\n' "${TARGET_FILE}"
  printf '  static workspace blocks: %s\n' "${count}"

  if [[ "${mode}" == "managed" ]]; then
    printf '  source: repo-rendered static workspace mapping is active\n'
  else
    printf '  source: dynamic/natural workspace behavior is active\n'
  fi
}

apply_managed() {
  local repo_root render_script
  repo_root="$(find_repo_root)" || {
    echo "ERROR: repo root not found; cannot render managed workspaces" >&2
    exit 1
  }

  render_script="${repo_root}/modules/niri/scripts/render-profile.sh"
  bash "${render_script}"
  reload_niri_config
  show_status
}

apply_natural() {
  write_natural_file
  reload_niri_config
  show_status
}

main() {
  local cmd="${1:-status}"

  case "${cmd}" in
    status|show)
      show_status
      ;;
    current|managed|with-workspaces)
      apply_managed
      ;;
    natural|plain|dynamic|no-workspaces)
      apply_natural
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
