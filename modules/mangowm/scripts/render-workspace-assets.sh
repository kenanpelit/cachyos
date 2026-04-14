#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${MODULE_DIR}/../.." && pwd)"

SOURCE_FILE="${MANGO_WORKSPACE_MAP_FILE:-${REPO_ROOT}/modules/niri/workspaces/workspaces.json}"
PROFILE_MANIFEST="${MANGO_PROFILE_MANIFEST:-${MODULE_DIR}/profiles/profile.env}"
SHARED_MONITOR_MANIFEST="${MANGO_SHARED_MONITOR_MANIFEST:-${REPO_ROOT}/shared/wm/monitors.yaml}"
RULES_OUT="${MANGO_WORKSPACE_RULES_OUT:-${MODULE_DIR}/dotfiles/mango/generated/workspace-rules.conf}"

usage() {
  cat <<'EOF'
Usage: render-workspace-assets.sh [--check]

Render generated MangoWM workspace routing rules from
modules/niri/workspaces/workspaces.json plus the active monitor profile.
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
[[ -r "${PROFILE_MANIFEST}" ]] || { echo "Profile manifest not found: ${PROFILE_MANIFEST}" >&2; exit 1; }
[[ -r "${SHARED_MONITOR_MANIFEST}" ]] || { echo "Shared monitor manifest not found: ${SHARED_MONITOR_MANIFEST}" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

# shellcheck source=/dev/null
source "${PROFILE_MANIFEST}"

: "${MANGO_MONITOR_PROFILE:=desk}"

tmp_rules="$(mktemp)"
cleanup() {
  rm -f "${tmp_rules}"
}
trap cleanup EXIT

python3 - "${SOURCE_FILE}" "${SHARED_MONITOR_MANIFEST}" "${MANGO_MONITOR_PROFILE}" "${tmp_rules}" <<'PY'
import json
import os
import sys
from pathlib import Path

import yaml

workspace_path = Path(sys.argv[1])
monitor_manifest_path = Path(sys.argv[2])
profile_name = sys.argv[3]
out_path = Path(sys.argv[4])

workspace_data = json.loads(workspace_path.read_text())
monitor_manifest = yaml.safe_load(monitor_manifest_path.read_text())

profiles = monitor_manifest.get("profiles", {})
monitors = {
    monitor["id"]: monitor for monitor in monitor_manifest.get("monitors", [])
}
profile = profiles.get(profile_name)

if profile is None:
    raise SystemExit(f"Unknown MANGO_MONITOR_PROFILE: {profile_name}")

workspace_monitor_map = {}
for workspace_ref in profile.get("workspaces", []):
    monitor = monitors.get(workspace_ref["monitor"])
    if monitor is None:
        continue
    workspace_monitor_map[str(workspace_ref["id"])] = monitor.get(
        "niri_name", monitor["id"]
    )


def normalized_routes(workspace):
    routes = workspace.get("routes")
    if routes is not None:
        return routes

    app = workspace.get("routeAppRegex", "")
    title = workspace.get("routeTitleRegex", "")
    if app or title:
        return [{"appIdRegex": app, "titleRegex": title}]
    return []


lines = [
    "# Generated from modules/niri/workspaces/workspaces.json.",
    "# Edit the canonical workspace map instead of hand-editing these rules.",
    f"# Active monitor profile: {profile_name}",
]

for workspace in workspace_data.get("workspaces", []):
    workspace_id = str(workspace["id"])
    lines.append(f"# Tag {workspace_id}: {workspace['name']}")
    monitor_name = workspace_monitor_map.get(workspace_id, "")

    for route in normalized_routes(workspace):
        parts = [f"windowrule=tags:{workspace_id}"]
        if monitor_name:
            parts.append(f"monitor:{monitor_name}")
        parts.append("istagsilent:1")

        app_id_regex = route.get("appIdRegex", "")
        title_regex = route.get("titleRegex", "")
        if app_id_regex:
            parts.append(f"appid:{app_id_regex}")
        if title_regex:
            parts.append(f"title:{title_regex}")

        lines.append(",".join(parts))

    lines.append("")

out_path.write_text("\n".join(lines))
PY

if [[ "${mode}" == "check" ]]; then
  diff -u "${RULES_OUT}" "${tmp_rules}"
  exit 0
fi

install -D -m 644 "${tmp_rules}" "${RULES_OUT}"
