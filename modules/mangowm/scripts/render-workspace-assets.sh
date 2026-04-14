#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${MODULE_DIR}/../.." && pwd)"

SOURCE_FILE="${MANGO_WORKSPACE_MAP_FILE:-${REPO_ROOT}/modules/niri/workspaces/workspaces.json}"
RULES_OUT="${MANGO_WORKSPACE_RULES_OUT:-${MODULE_DIR}/dotfiles/mango/generated/workspace-rules.conf}"

usage() {
  cat <<'EOF'
Usage: render-workspace-assets.sh [--check]

Render generated MangoWM workspace routing rules from
modules/niri/workspaces/workspaces.json.
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

[[ -r "${SOURCE_FILE}" ]] || { echo "Workspace source file not found: ${SOURCE_FILE}" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

tmp_rules="$(mktemp)"
cleanup() {
  rm -f "${tmp_rules}"
}
trap cleanup EXIT

{
  cat <<'EOF'
# Generated from modules/niri/workspaces/workspaces.json.
# Edit the canonical workspace map instead of hand-editing these rules.
EOF

  jq -r '
    def normalized_routes($ws):
      if ($ws.routes // null) != null then
        $ws.routes
      elif (($ws.routeAppRegex // "") != "" or ($ws.routeTitleRegex // "") != "") then
        [{
          appIdRegex: ($ws.routeAppRegex // ""),
          titleRegex: ($ws.routeTitleRegex // "")
        }]
      else
        []
      end;

    .workspaces[] as $ws
    | "# Tag \($ws.id): \($ws.name)",
      (
        normalized_routes($ws)[]
        | [
            "windowrule=tags:\($ws.id)",
            "istagsilent:1",
            (if (.appIdRegex // "") != "" then "appid:\(.appIdRegex)" else empty end),
            (if (.titleRegex // "") != "" then "title:\(.titleRegex)" else empty end)
          ]
        | map(select(length > 0))
        | join(",")
      ),
      ""
  ' "${SOURCE_FILE}"
} > "${tmp_rules}"

if [[ "${mode}" == "check" ]]; then
  diff -u "${RULES_OUT}" "${tmp_rules}"
  exit 0
fi

install -D -m 644 "${tmp_rules}" "${RULES_OUT}"
