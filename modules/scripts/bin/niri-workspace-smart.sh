#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="niri-workspace-smart"
RUNTIME_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/niri/runtime"
HERE_FILE="${NIRI_WORKSPACE_HERE_FILE:-${RUNTIME_DIR}/workspace-here.tsv}"

usage() {
  cat <<'EOF'
Usage:
  niri-workspace-smart focus <workspace-id|workspace-name>
  niri-workspace-smart move <workspace-id|workspace-name>
  niri-workspace-smart here <workspace-target|workspace-name>
  niri-workspace-smart launch <workspace-target|workspace-name>
  niri-workspace-smart all

Thin Niri IPC wrapper around the generated workspace manifest. It gives Niri a
Mango-like smart workspace entry point without duplicating workspace metadata.
EOF
}

die() {
  printf '%s: %s\n' "${SCRIPT_NAME}" "$*" >&2
  exit 1
}

workspace_name_from_ref() {
  local ref="${1:-}"
  [[ -n "${ref}" ]] || return 1
  [[ -f "${HERE_FILE}" ]] || {
    printf '%s\n' "${ref}"
    return 0
  }

  awk -F '\t' -v ref="${ref}" '
    /^[[:space:]]*#/ { next }
    $1 == ref || $2 == ref || $3 == ref || $4 == ref {
      print $2
      found = 1
      exit 0
    }
    END { exit found ? 0 : 1 }
  ' "${HERE_FILE}" 2>/dev/null || printf '%s\n' "${ref}"
}

workspace_target_from_ref() {
  local ref="${1:-}"
  [[ -n "${ref}" ]] || return 1
  [[ -f "${HERE_FILE}" ]] || {
    printf '%s\n' "${ref}"
    return 0
  }

  awk -F '\t' -v ref="${ref}" '
    /^[[:space:]]*#/ { next }
    $1 == ref || $2 == ref || $3 == ref || $4 == ref {
      print ($4 != "" ? $4 : $2)
      found = 1
      exit 0
    }
    END { exit found ? 0 : 1 }
  ' "${HERE_FILE}" 2>/dev/null || printf '%s\n' "${ref}"
}

run_detached() {
  local cmd="$1"
  shift || true
  PATH="$HOME/.local/bin:$HOME/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}" "$cmd" "$@" >/dev/null 2>&1 &
  disown || true
}

command="${1:-}"
target="${2:-}"

case "${command}" in
  focus)
    [[ -n "${target}" ]] || die "target is required"
    command -v niri >/dev/null 2>&1 || die "niri not found"
    niri msg action focus-workspace "$(workspace_name_from_ref "${target}")"
    ;;
  move)
    [[ -n "${target}" ]] || die "target is required"
    command -v niri >/dev/null 2>&1 || die "niri not found"
    niri msg action move-column-to-workspace "$(workspace_name_from_ref "${target}")"
    ;;
  here)
    [[ -n "${target}" ]] || die "target is required"
    exec niri-osc set here "$(workspace_target_from_ref "${target}")"
    ;;
  launch)
    [[ -n "${target}" ]] || die "target is required"
    launcher="$(command -v osc-workspace-launch 2>/dev/null || true)"
    [[ -n "${launcher}" ]] || die "osc-workspace-launch not found"
    candidate="$("${launcher}" first-existing "$(workspace_target_from_ref "${target}")" 2>/dev/null || true)"
    [[ -n "${candidate}" ]] || die "no launch candidate found for ${target}"
    run_detached "${candidate}"
    ;;
  all)
    exec niri-osc set here all
    ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
