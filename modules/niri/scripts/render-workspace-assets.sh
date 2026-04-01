#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${MODULE_DIR}/../.." && pwd)"

SOURCE_FILE="${NIRI_WORKSPACE_MAP_FILE:-${MODULE_DIR}/workspaces/workspaces.json}"
SHORTCUTS_OUT="${NIRI_WORKSPACE_SHORTCUTS_OUT:-${MODULE_DIR}/dotfiles/niri/generated/workspace-shortcuts.kdl}"
RULES_OUT="${NIRI_WORKSPACE_RULES_OUT:-${MODULE_DIR}/dotfiles/niri/generated/workspace-rules.kdl}"
NOCTALIA_META_OUT="${NIRI_NOCTALIA_WORKSPACE_META_OUT:-${REPO_ROOT}/modules/noctalia/dotfiles/noctalia/plugins/6ee06e:nworkspace/WorkspaceMeta.js}"
RUNTIME_DIR="${NIRI_RUNTIME_DIR:-}"
RUNTIME_RULES_BASENAME="workspace-rules.tsv"
RUNTIME_HERE_BASENAME="workspace-here.tsv"

usage() {
  cat <<'EOF'
Usage: render-workspace-assets.sh [--check] [--runtime-dir DIR]
                                 [--stdout shortcuts|rules|noctalia-meta|runtime-rules|runtime-here]

Render generated Niri/Noctalia workspace assets from modules/niri/workspaces/workspaces.json.
EOF
}

require_jq() {
  command -v jq >/dev/null 2>&1 || {
    echo "jq is required for render-workspace-assets.sh" >&2
    exit 1
  }
}

emit_shortcuts() {
  cat <<'EOF'
// Generated from modules/niri/workspaces/workspaces.json.
// Edit the source workspace map instead of hand-editing these shortcuts.
binds {
// BEGIN OSC_NIRI_WORKSPACE_SHORTCUTS
  // ----------------------------------------------------------------------
  // Workspace Navigation (1..9)
  // ----------------------------------------------------------------------
EOF

  jq -r '.workspaces[] | "  Mod+\(.id) hotkey-overlay-title=\"Workspace \(.id): \(.name)\" { focus-workspace \"\(.id)\"; }"' "${SOURCE_FILE}"

  cat <<'EOF'

  // Move current column to workspace (1..9).
EOF

  jq -r '.workspaces[] | "  Mod+Shift+\(.id) hotkey-overlay-title=\"Move To WS \(.id): \(.name)\" { move-column-to-workspace \"\(.id)\"; }"' "${SOURCE_FILE}"

  cat <<'EOF'

  // ----------------------------------------------------------------------
  // "Here" Actions (Workspace shortcuts for specific apps)
  // ----------------------------------------------------------------------
EOF

  jq -r '.workspaces[] | "  Alt+\(.id) allow-inhibiting=false repeat=false hotkey-overlay-title=\"Here: \(.hereLabel)\" { spawn \"niri-osc\" \"set\" \"here\" \"\(.hereTarget)\"; }"' "${SOURCE_FILE}"

  cat <<'EOF'
  Alt+0 allow-inhibiting=false repeat=false hotkey-overlay-title="Here: ALL" { spawn "niri-osc" "set" "here" "all"; }

  // Global window rearrangement.
  Mod+Alt+0 allow-inhibiting=false repeat=false hotkey-overlay-title="Go (Arrange Windows)" { spawn "niri-osc" "set" "go"; }
// END OSC_NIRI_WORKSPACE_SHORTCUTS
}
EOF
}

emit_rules() {
  cat <<'EOF'
// Generated from modules/niri/workspaces/workspaces.json.
// Edit the source workspace map instead of hand-editing these rules.
// BEGIN OSC_NIRI_WORKSPACE_RULES
// Default workspace placements by application ID.
EOF

  jq -r '.workspaces[] |
    "window-rule {\n" +
    "  match app-id=r#\"\(.routeAppRegex)\"#\n" +
    "  open-on-workspace \"\(.id)\"\n" +
    "}\n"
  ' "${SOURCE_FILE}"

  cat <<'EOF'
// END OSC_NIRI_WORKSPACE_RULES
EOF
}

emit_noctalia_meta() {
  local aliases_json items_json
  aliases_json="$(jq '{aliases: (reduce .workspaces[] as $ws ({}; .[$ws.id] = $ws.name))} | .aliases' "${SOURCE_FILE}")"
  items_json="$(jq '[.workspaces[] | {id, name, hereLabel, hereTarget}]' "${SOURCE_FILE}")"

  cat <<EOF
.pragma library

// Generated from modules/niri/workspaces/workspaces.json.
// Edit the source workspace map instead of hand-editing this file.

var aliases = ${aliases_json};
var items = ${items_json};
EOF
}

emit_runtime_rules() {
  cat <<'EOF'
# Generated from modules/niri/workspaces/workspaces.json.
# Format: APP_ID_REGEX<TAB>WORKSPACE<TAB>TITLE_REGEX
EOF

  jq -r '.workspaces[] | [.routeAppRegex, .id, .routeTitleRegex] | @tsv' "${SOURCE_FILE}"
}

emit_runtime_here() {
  cat <<'EOF'
# Generated from modules/niri/workspaces/workspaces.json.
# Format: WORKSPACE<TAB>NAME<TAB>HERE_LABEL<TAB>HERE_TARGET<TAB>FOCUS_REGEX
EOF

  jq -r '.workspaces[] | [.id, .name, .hereLabel, .hereTarget, .focusRegex] | @tsv' "${SOURCE_FILE}"
}

write_if_changed() {
  local target="$1"
  local tmp="$2"
  mkdir -p "$(dirname "${target}")"
  if [[ -f "${target}" ]] && cmp -s "${tmp}" "${target}"; then
    rm -f "${tmp}"
    return 0
  fi
  mv -f "${tmp}" "${target}"
}

check_file_matches() {
  local target="$1"
  local tmp="$2"
  diff -u "${target}" "${tmp}"
}

mode="write"
stdout_kind=""

while (($#)); do
  case "$1" in
    --check)
      mode="check"
      shift
      ;;
    --runtime-dir)
      RUNTIME_DIR="$2"
      shift 2
      ;;
    --stdout)
      stdout_kind="$2"
      shift 2
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
done

[[ -r "${SOURCE_FILE}" ]] || {
  echo "Workspace source file not found: ${SOURCE_FILE}" >&2
  exit 1
}
require_jq

if [[ -n "${stdout_kind}" ]]; then
  case "${stdout_kind}" in
    shortcuts) emit_shortcuts ;;
    rules) emit_rules ;;
    noctalia-meta) emit_noctalia_meta ;;
    runtime-rules) emit_runtime_rules ;;
    runtime-here) emit_runtime_here ;;
    *)
      echo "Unknown stdout kind: ${stdout_kind}" >&2
      exit 2
      ;;
  esac
  exit 0
fi

tmp_shortcuts="$(mktemp)"
tmp_rules="$(mktemp)"
tmp_noctalia_meta="$(mktemp)"
trap 'rm -f "${tmp_shortcuts}" "${tmp_rules}" "${tmp_noctalia_meta}" "${tmp_runtime_rules:-}" "${tmp_runtime_here:-}"' EXIT

emit_shortcuts > "${tmp_shortcuts}"
emit_rules > "${tmp_rules}"
emit_noctalia_meta > "${tmp_noctalia_meta}"

if [[ -n "${RUNTIME_DIR}" ]]; then
  tmp_runtime_rules="$(mktemp)"
  tmp_runtime_here="$(mktemp)"
  emit_runtime_rules > "${tmp_runtime_rules}"
  emit_runtime_here > "${tmp_runtime_here}"
fi

if [[ "${mode}" == "check" ]]; then
  check_file_matches "${SHORTCUTS_OUT}" "${tmp_shortcuts}"
  check_file_matches "${RULES_OUT}" "${tmp_rules}"
  check_file_matches "${NOCTALIA_META_OUT}" "${tmp_noctalia_meta}"
  if [[ -n "${RUNTIME_DIR}" ]]; then
    check_file_matches "${RUNTIME_DIR}/${RUNTIME_RULES_BASENAME}" "${tmp_runtime_rules}"
    check_file_matches "${RUNTIME_DIR}/${RUNTIME_HERE_BASENAME}" "${tmp_runtime_here}"
  fi
  exit 0
fi

write_if_changed "${SHORTCUTS_OUT}" "${tmp_shortcuts}"
write_if_changed "${RULES_OUT}" "${tmp_rules}"
write_if_changed "${NOCTALIA_META_OUT}" "${tmp_noctalia_meta}"

if [[ -n "${RUNTIME_DIR}" ]]; then
  mkdir -p "${RUNTIME_DIR}"
  write_if_changed "${RUNTIME_DIR}/${RUNTIME_RULES_BASENAME}" "${tmp_runtime_rules}"
  write_if_changed "${RUNTIME_DIR}/${RUNTIME_HERE_BASENAME}" "${tmp_runtime_here}"
fi
