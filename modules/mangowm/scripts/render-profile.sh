#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${MODULE_DIR}/../.." && pwd)"
PROFILE_MANIFEST="${MANGO_PROFILE_MANIFEST:-${MODULE_DIR}/profiles/profile.env}"
SHARED_MONITOR_MANIFEST="${MANGO_SHARED_MONITOR_MANIFEST:-${REPO_ROOT}/shared/wm/monitors.yaml}"
WORKSPACE_MAP_FILE="${MANGO_WORKSPACE_MAP_FILE:-${REPO_ROOT}/modules/niri/workspaces/workspaces.json}"
PROFILE_OUT="${MANGO_PROFILE_OUT:-${MODULE_DIR}/dotfiles/mango/generated/profile.conf}"
WORKSPACE_BINDS_OUT="${MANGO_WORKSPACE_BINDS_OUT:-${MODULE_DIR}/dotfiles/mango/generated/workspace-binds.conf}"

usage() {
  cat <<'EOF'
Usage: render-profile.sh [--check]

Without arguments, renders the selected MangoWM monitor/tag profile and
profile-aware workspace bindings.
With --check, verifies that the generated files match the manifests.
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

[[ -r "${PROFILE_MANIFEST}" ]] || { echo "Profile manifest not found: ${PROFILE_MANIFEST}" >&2; exit 1; }
[[ -r "${SHARED_MONITOR_MANIFEST}" ]] || { echo "Shared monitor manifest not found: ${SHARED_MONITOR_MANIFEST}" >&2; exit 1; }
[[ -r "${WORKSPACE_MAP_FILE}" ]] || { echo "Workspace map not found: ${WORKSPACE_MAP_FILE}" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

# shellcheck source=/dev/null
source "${PROFILE_MANIFEST}"

: "${MANGO_MONITOR_PROFILE:=desk}"

tmp_profile="$(mktemp)"
tmp_binds="$(mktemp)"
cleanup() {
  rm -f "${tmp_profile}" "${tmp_binds}"
}
trap cleanup EXIT

python3 - "${SHARED_MONITOR_MANIFEST}" "${WORKSPACE_MAP_FILE}" "${MANGO_MONITOR_PROFILE}" "${tmp_profile}" "${tmp_binds}" <<'PY'
import hashlib
import json
import re
import sys
from pathlib import Path

import yaml

manifest_path = Path(sys.argv[1])
workspace_path = Path(sys.argv[2])
profile_name = sys.argv[3]
out_path = Path(sys.argv[4])
binds_out_path = Path(sys.argv[5])

manifest = yaml.safe_load(manifest_path.read_text())
workspace_data = json.loads(workspace_path.read_text())

monitors = manifest.get("monitors", [])
profiles = manifest.get("profiles", {})
workspaces = workspace_data.get("workspaces", [])
profile = profiles.get(profile_name)

if profile is None:
    raise SystemExit(f"Unknown MANGO_MONITOR_PROFILE: {profile_name}")

monitors_by_id = {monitor["id"]: monitor for monitor in monitors}
workspaces_by_id = {str(workspace["id"]): workspace for workspace in workspaces}

checksum = hashlib.sha256(
    json.dumps(
        {
            "monitors": monitors,
            "profile": profile,
            "workspaces": workspaces,
        },
        sort_keys=True,
        separators=(",", ":"),
    ).encode()
).hexdigest()


def parse_mode(mode: str):
    match = re.match(r"^(?P<width>\d+)x(?P<height>\d+)@(?P<refresh>\d+(?:\.\d+)?)$", mode)
    if not match:
        raise SystemExit(f"Unsupported monitor mode format: {mode}")
    width = int(match.group("width"))
    height = int(match.group("height"))
    refresh = match.group("refresh")
    if refresh.endswith(".0"):
        refresh = refresh[:-2]
    return width, height, refresh


def parse_position(raw_position, monitor):
    if isinstance(raw_position, dict):
        return int(raw_position.get("x", 0)), int(raw_position.get("y", 0))
    if isinstance(raw_position, str) and "x" in raw_position:
        x_raw, y_raw = raw_position.split("x", 1)
        return int(x_raw), int(y_raw)
    position = monitor.get("position", {})
    return int(position.get("x", 0)), int(position.get("y", 0))


def layout_name_for_workspace(workspace):
    return "scroller"


lines = [
    "# Generated from shared/wm/monitors.yaml and modules/niri/workspaces/workspaces.json.",
    "# Update the shared manifests and rerun modules/mangowm/scripts/render-profile.sh.",
    f"# Source checksum: {checksum}",
    "",
    f"# Active monitor profile: {profile_name}",
    "",
]

seen_monitor_names = set()
for output in profile.get("outputs", []):
    monitor_id = output.get("monitor")
    if not monitor_id:
        continue
    monitor = monitors_by_id[monitor_id]
    monitor_name = monitor.get("niri_name", monitor_id)
    if monitor_name in seen_monitor_names:
        continue
    seen_monitor_names.add(monitor_name)

    width, height, refresh = parse_mode(output.get("mode") or monitor["mode"])
    x, y = parse_position(output.get("position"), monitor)
    scale = output.get("scale", monitor.get("scale", 1))
    vrr = 1 if monitor.get("variable_refresh_rate") in (True, "on-demand") else 0

    lines.append(
        "monitorrule="
        f"name:^{re.escape(monitor_name)}$,"
        f"width:{width},height:{height},refresh:{refresh},"
        f"x:{x},y:{y},scale:{scale},vrr:{vrr}"
    )

lines.append("")
lines.append("# Tag placement for the selected profile.")

for workspace_ref in sorted(profile.get("workspaces", []), key=lambda item: int(item["id"])):
    workspace_id = str(workspace_ref["id"])
    workspace = workspaces_by_id[workspace_id]
    monitor = monitors_by_id[workspace_ref["monitor"]]
    monitor_name = monitor.get("niri_name", monitor["id"])
    layout_name = layout_name_for_workspace(workspace)
    lines.append(f"# Tag {workspace_id}: {workspace['name']}")
    lines.append(
        f"tagrule=id:{workspace_id},monitor_name:{monitor_name},no_hide:1,layout_name:{layout_name}"
    )

lines.append("")
out_path.write_text("\n".join(lines))

bind_lines = [
    "# Generated from shared/wm/monitors.yaml and modules/niri/workspaces/workspaces.json.",
    "# Update the shared manifests and rerun modules/mangowm/scripts/render-profile.sh.",
    f"# Source checksum: {checksum}",
    "",
    f"# Active monitor profile: {profile_name}",
    "# Profile-aware workspace binds: switch follows the target monitor.",
    "# Shift-number moves are defined in conf.d/50-binds.conf via mango-tag-smart.",
    "# Alt binds jump to the app's home tag and spawn it only when that tag is empty.",
    "",
]

for workspace_ref in sorted(profile.get("workspaces", []), key=lambda item: int(item["id"])):
    workspace_id = str(workspace_ref["id"])
    workspace = workspaces_by_id[workspace_id]
    monitor = monitors_by_id[workspace_ref["monitor"]]
    monitor_name = monitor.get("niri_name", monitor["id"])
    here = workspace.get("here", {})
    here_target = here.get("target") or workspace.get("hereTarget") or workspace["name"]
    bind_lines.append(f"# Tag {workspace_id}: {workspace['name']} ({monitor_name})")
    bind_lines.append(
        f"binds=SUPER,{workspace_id},spawn,mango-workspace-smart {workspace_id} {monitor_name}"
    )
    bind_lines.append(
        f"binds=ALT,{workspace_id},spawn,mango-here {workspace_id} {monitor_name} {here_target}"
    )
    bind_lines.append("")

binds_out_path.write_text("\n".join(bind_lines).rstrip() + "\n")
PY

if [[ "${mode}" == "check" ]]; then
  diff -u "${PROFILE_OUT}" "${tmp_profile}"
  diff -u "${WORKSPACE_BINDS_OUT}" "${tmp_binds}"
  exit 0
fi

install -D -m 644 "${tmp_profile}" "${PROFILE_OUT}"
install -D -m 644 "${tmp_binds}" "${WORKSPACE_BINDS_OUT}"
