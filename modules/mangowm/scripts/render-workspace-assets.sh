#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${MODULE_DIR}/../.." && pwd)"
source "${REPO_ROOT}/modules/base/lib/core.sh"

SOURCE_FILE="${MANGO_WORKSPACE_MAP_FILE:-${REPO_ROOT}/shared/wm/workspaces.json}"
PROFILE_MANIFEST="${MANGO_PROFILE_MANIFEST:-${MODULE_DIR}/profiles/profile.env}"
SHARED_MONITOR_MANIFEST="${MANGO_SHARED_MONITOR_MANIFEST:-${REPO_ROOT}/shared/wm/monitors.yaml}"
OUTPUT_DIR="${MANGO_OUTPUT_DIR:-${MODULE_DIR}/dotfiles/mango/generated}"
RULES_OUT="${MANGO_WORKSPACE_RULES_OUT:-${OUTPUT_DIR}/workspace-rules.conf}"

usage() {
	cat <<'EOF'
Usage: render-workspace-assets.sh [--check] [--out-dir DIR]

Render generated MangoWM workspace routing rules from
shared/wm/workspaces.json plus the active monitor profile.
EOF
}

mode="write"
while (($#)); do
	case "$1" in
	--check)
		mode="check"
		shift
		;;
	--out-dir)
		OUTPUT_DIR="$2"
		RULES_OUT="${OUTPUT_DIR}/workspace-rules.conf"
		shift 2
		;;
	--runtime-dir)
		OUTPUT_DIR="$2"
		RULES_OUT="${OUTPUT_DIR}/workspace-rules.conf"
		shift 2
		;;
	--write)
		shift
		;;
	-h | --help)
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
[[ -r "${PROFILE_MANIFEST}" ]] || {
	echo "Profile manifest not found: ${PROFILE_MANIFEST}" >&2
	exit 1
}
[[ -r "${SHARED_MONITOR_MANIFEST}" ]] || {
	echo "Shared monitor manifest not found: ${SHARED_MONITOR_MANIFEST}" >&2
	exit 1
}
command -v jq >/dev/null 2>&1 || {
	echo "jq is required" >&2
	exit 1
}
command -v python3 >/dev/null 2>&1 || {
	echo "python3 is required" >&2
	exit 1
}

# shellcheck source=/dev/null
source "${PROFILE_MANIFEST}"

: "${MANGO_MONITOR_PROFILE:=desk}"

connected_outputs=""
if [[ "${MANGO_MONITOR_PROFILE}" == "auto" ]]; then
	if command -v mmsg >/dev/null 2>&1; then
		connected_outputs="$(mmsg -O 2>/dev/null | paste -sd, - || true)"
	fi
	if [[ -z "${connected_outputs}" ]] && command -v wlr-randr >/dev/null 2>&1; then
		connected_outputs="$(
			wlr-randr 2>/dev/null |
				awk '/^[^[:space:]]/ { print $1 }' |
				paste -sd, - || true
		)"
	fi
fi

tmp_rules="$(mktemp)"
cleanup() {
	rm -f "${tmp_rules}"
}
trap cleanup EXIT

python3 - "${SOURCE_FILE}" "${SHARED_MONITOR_MANIFEST}" "${MANGO_MONITOR_PROFILE}" "${connected_outputs}" "${tmp_rules}" <<'PY'
import json
import sys
from pathlib import Path

import yaml

workspace_path = Path(sys.argv[1])
monitor_manifest_path = Path(sys.argv[2])
profile_name = sys.argv[3]
connected_outputs = {item for item in sys.argv[4].split(",") if item}
out_path = Path(sys.argv[5])

workspace_data = json.loads(workspace_path.read_text())
monitor_manifest = yaml.safe_load(monitor_manifest_path.read_text())

profiles = monitor_manifest.get("profiles", {})
monitors = {
    monitor["id"]: monitor for monitor in monitor_manifest.get("monitors", [])
}
workspace_monitor_map = {}


def monitor_name_for_mango(monitor):
    return monitor.get("mango_name", monitor.get("wayland_name", monitor["id"]))


def profile_output_names(profile):
    names = []
    for output in profile.get("outputs", []):
        monitor_id = output.get("monitor")
        if not monitor_id:
            continue
        monitor = monitors.get(monitor_id)
        if monitor is not None:
            names.append(monitor_name_for_mango(monitor))
    return names


def resolve_profile_name(requested):
    if requested != "auto":
        return requested
    if not connected_outputs:
        return "desk" if "desk" in profiles else next(iter(profiles), "")

    scored = []
    for candidate_name, candidate_profile in profiles.items():
        names = set(profile_output_names(candidate_profile))
        if not names:
            continue
        matched = len(names & connected_outputs)
        missing = len(names - connected_outputs)
        extra = len(connected_outputs - names)
        exact_subset = 1 if names <= connected_outputs else 0
        scored.append((exact_subset, matched, -missing, -extra, candidate_name))

    if not scored:
        return "desk" if "desk" in profiles else next(iter(profiles), "")
    scored.sort(reverse=True)
    return scored[0][-1]


selected_profile_name = resolve_profile_name(profile_name)
profile = profiles.get(selected_profile_name)
if profile is None:
    raise SystemExit(f"Unknown MANGO_MONITOR_PROFILE: {profile_name}")

for workspace_ref in profile.get("workspaces", []):
    monitor = monitors.get(workspace_ref["monitor"])
    if monitor is None:
        continue
    workspace_monitor_map[str(workspace_ref["id"])] = monitor_name_for_mango(monitor)


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
    "# Generated from shared/wm/workspaces.json.",
    "# Edit the canonical workspace map instead of hand-editing these rules.",
    f"# Active monitor profile: {selected_profile_name}",
]

for workspace in workspace_data.get("workspaces", []):
    workspace_id = str(workspace["id"])
    lines.append(f"# Tag {workspace_id}: {workspace['name']}")
    monitor_name = workspace_monitor_map.get(workspace_id, "")

    for route in normalized_routes(workspace):
        parts = [f"windowrule=tags:{workspace_id}"]
        if monitor_name:
            parts.append(f"monitor:{monitor_name}")
        tag_silent = route.get("tagSilent")
        if tag_silent is None:
            tag_silent = workspace.get("tagSilent", False)
        if tag_silent:
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

run_as_user install -D -m 644 "${tmp_rules}" "${RULES_OUT}"
