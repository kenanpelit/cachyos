#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Try to find REPO_ROOT relative to script, or fallback to known location
if [[ -f "${SCRIPT_DIR}/../../../shared/wm/workspaces.json" ]]; then
  REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
elif [[ -f "${HOME}/.cachy/shared/wm/workspaces.json" ]]; then
  REPO_ROOT="${HOME}/.cachy"
else
  REPO_ROOT="${SCRIPT_DIR}/../../.."
fi
WORKSPACE_MANIFEST="${OSC_WORKSPACE_MANIFEST:-${REPO_ROOT}/shared/wm/workspaces.json}"

usage() {
  cat <<'EOF'
Usage:
  osc-workspace-launch candidates <target>
  osc-workspace-launch first-existing <target>
  osc-workspace-launch focus-regex <target>
  osc-workspace-launch gather-targets

Reads launch metadata from shared/wm/workspaces.json.
EOF
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

preferred_browser_prefix() {
  if [[ "${BROWSER:-start-helium-kenp}" == *"helium"* ]]; then
    printf '%s\n' "helium"
  else
    printf '%s\n' "brave"
  fi
}

expand_candidate() {
  local browser_prefix="$1"
  local candidate="$2"
  printf '%s\n' "${candidate//\{browser\}/${browser_prefix}}"
}

command_exists() {
  local candidate="$1"
  command -v "${candidate}" >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/${candidate}" ]]
}

[[ -r "${WORKSPACE_MANIFEST}" ]] || die "Workspace manifest not found: ${WORKSPACE_MANIFEST}"
command -v jq >/dev/null 2>&1 || die "jq is required"

subcommand="${1:-}"
target="${2:-}"
browser_prefix="$(preferred_browser_prefix)"

case "${subcommand}" in
  candidates)
    [[ -n "${target}" ]] || die "target is required"
    jq -r --arg target "${target}" '
      .workspaces[]
      | select(
          ((.here.target // .hereTarget // "") | ascii_downcase) == ($target | ascii_downcase) or
          ((.here.label // .hereLabel // "") | ascii_downcase) == ($target | ascii_downcase) or
          ((.name // "") | ascii_downcase) == ($target | ascii_downcase)
        )
      | (.launch.commands // [])[]
    ' "${WORKSPACE_MANIFEST}" | while IFS= read -r candidate; do
      [[ -n "${candidate}" ]] || continue
      expand_candidate "${browser_prefix}" "${candidate}"
    done
    ;;
  first-existing)
    [[ -n "${target}" ]] || die "target is required"
    while IFS= read -r candidate; do
      [[ -n "${candidate}" ]] || continue
      if command_exists "${candidate}"; then
        printf '%s\n' "${candidate}"
        exit 0
      fi
    done < <("${BASH_SOURCE[0]}" candidates "${target}")
    exit 1
    ;;
  focus-regex)
    [[ -n "${target}" ]] || die "target is required"
    jq -r --arg target "${target}" '
      first(
        .workspaces[]
        | select((.here.target // .hereTarget // "") == $target)
        | (.focus.regex // .focusRegex // empty)
      ) // empty
    ' "${WORKSPACE_MANIFEST}"
    ;;
  gather-targets)
    jq -r '
      .workspaces[]
      | select(
          if (.launch | has("includeInAll")) then
            .launch.includeInAll == true
          else
            true
          end
        )
      | (.here.target // .hereTarget // empty)
    ' "${WORKSPACE_MANIFEST}"
    ;;
  -h|--help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
