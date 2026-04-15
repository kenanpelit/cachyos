#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${MODULE_DIR}/../.." && pwd)"
SOURCE_FILE="${NOCTALIA_WORKSPACE_SOURCE_FILE:-${REPO_ROOT}/modules/niri/workspaces/workspaces.json}"
TARGET_FILE="${NOCTALIA_WORKSPACE_META_OUT:-${MODULE_DIR}/dotfiles/noctalia/plugins/6ee06e:nworkspace/WorkspaceMeta.js}"

usage() {
  cat <<'EOF'
Usage: render-workspace-meta.sh [--check]

Render Noctalia workspace metadata from modules/niri/workspaces/workspaces.json.
EOF
}

mode="write"
case "${1:-}" in
  ""|--write)
    ;;
  --check)
    mode="check"
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

[[ -r "${SOURCE_FILE}" ]] || {
  echo "Workspace source file not found: ${SOURCE_FILE}" >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  echo "jq is required for render-workspace-meta.sh" >&2
  exit 1
}

tmp_file="$(mktemp)"
trap 'rm -f "${tmp_file}"' EXIT

aliases_json="$(jq '{aliases: (reduce .workspaces[] as $ws ({}; .[$ws.id] = $ws.name))} | .aliases' "${SOURCE_FILE}")"
items_json="$(jq '[.workspaces[] | {id, name, hereLabel: (.here.label // .hereLabel), hereTarget: (.here.target // .hereTarget)}]' "${SOURCE_FILE}")"

cat <<EOF > "${tmp_file}"
.pragma library

// Generated from modules/niri/workspaces/workspaces.json.
// Edit the source workspace map instead of hand-editing this file.

var aliases = ${aliases_json};
var items = ${items_json};
EOF

if [[ "${mode}" == "check" ]]; then
  diff -u "${TARGET_FILE}" "${tmp_file}"
  exit 0
fi

mkdir -p "$(dirname "${TARGET_FILE}")"
if [[ -f "${TARGET_FILE}" ]] && cmp -s "${tmp_file}" "${TARGET_FILE}"; then
  exit 0
fi
install -m 644 "${tmp_file}" "${TARGET_FILE}"
