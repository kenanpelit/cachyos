#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${MODULE_DIR}/../.." && pwd)"
source "${REPO_ROOT}/modules/base/lib/core.sh"

PROFILE_MANIFEST="${MANGO_PROFILE_MANIFEST:-${MODULE_DIR}/profiles/profile.env}"
SHARED_MONITOR_MANIFEST="${MANGO_SHARED_MONITOR_MANIFEST:-${REPO_ROOT}/shared/wm/monitors.yaml}"
WORKSPACE_MAP_FILE="${MANGO_WORKSPACE_MAP_FILE:-${REPO_ROOT}/shared/wm/workspaces.json}"
OUTPUT_DIR="${MANGO_OUTPUT_DIR:-${MODULE_DIR}/dotfiles/mango/generated}"
PROFILE_OUT="${MANGO_PROFILE_OUT:-${OUTPUT_DIR}/profile.conf}"
WORKSPACE_BINDS_OUT="${MANGO_WORKSPACE_BINDS_OUT:-${OUTPUT_DIR}/workspace-binds.conf}"
PROFILE_RESOLVER="${MODULE_DIR}/scripts/profile-resolver.py"

usage() {
	cat <<'EOF'
Usage: render-profile.sh [--check] [--out-dir DIR]

Without arguments, renders the selected MangoWM monitor/tag profile and
profile-aware workspace bindings into the Mango generated directory.
With --check, verifies that the generated files match the target outputs.
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
		PROFILE_OUT="${OUTPUT_DIR}/profile.conf"
		WORKSPACE_BINDS_OUT="${OUTPUT_DIR}/workspace-binds.conf"
		shift 2
		;;
	--runtime-dir)
		OUTPUT_DIR="$2"
		PROFILE_OUT="${OUTPUT_DIR}/profile.conf"
		WORKSPACE_BINDS_OUT="${OUTPUT_DIR}/workspace-binds.conf"
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

[[ -r "${PROFILE_MANIFEST}" ]] || {
	echo "Profile manifest not found: ${PROFILE_MANIFEST}" >&2
	exit 1
}
[[ -r "${SHARED_MONITOR_MANIFEST}" ]] || {
	echo "Shared monitor manifest not found: ${SHARED_MONITOR_MANIFEST}" >&2
	exit 1
}
[[ -r "${WORKSPACE_MAP_FILE}" ]] || {
	echo "Workspace map not found: ${WORKSPACE_MAP_FILE}" >&2
	exit 1
}
command -v python3 >/dev/null 2>&1 || {
	echo "python3 is required" >&2
	exit 1
}
[[ -x "${PROFILE_RESOLVER}" ]] || {
	echo "Profile resolver not executable: ${PROFILE_RESOLVER}" >&2
	exit 1
}

# shellcheck source=/dev/null
source "${PROFILE_MANIFEST}"

: "${MANGO_MONITOR_PROFILE:=desk}"

selected_profile_name="$("${PROFILE_RESOLVER}" --manifest "${SHARED_MONITOR_MANIFEST}" --profile "${MANGO_MONITOR_PROFILE}")"

tmp_profile="$(mktemp)"
tmp_binds="$(mktemp)"
cleanup() {
	rm -f "${tmp_profile}" "${tmp_binds}"
}
trap cleanup EXIT

python3 - "${SHARED_MONITOR_MANIFEST}" "${WORKSPACE_MAP_FILE}" "${selected_profile_name}" "${tmp_profile}" "${tmp_binds}" <<'PY'
import hashlib
import json
import re
import sys
from collections import OrderedDict
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

SUPPORTED_LAYOUTS = {
    "tile",
    "scroller",
    "monocle",
    "grid",
    "deck",
    "center_tile",
    "vertical_tile",
    "right_tile",
    "vertical_scroller",
    "vertical_grid",
    "vertical_deck",
    "tgmix",
}

monitors_by_id = {monitor["id"]: monitor for monitor in monitors}
workspaces_by_id = {str(workspace["id"]): workspace for workspace in workspaces}


def monitor_name_for_mango(monitor):
    return monitor.get("mango_name", monitor.get("wayland_name", monitor["id"]))


profile = profiles.get(profile_name)
if profile is None:
    raise SystemExit(f"Unknown MANGO_MONITOR_PROFILE: {profile_name}")

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


def normalize_binary(value, field_name: str) -> int:
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, int) and value in (0, 1):
        return value
    raise SystemExit(f"{field_name} must be 0/1 or boolean, got {value!r}")


def normalize_layout_name(value, workspace_id: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise SystemExit(f"workspace {workspace_id} layout.mango.layoutName must be a non-empty string")
    normalized = value.strip()
    if normalized not in SUPPORTED_LAYOUTS:
        raise SystemExit(
            f"workspace {workspace_id} layout.mango.layoutName must be one of "
            f"{', '.join(sorted(SUPPORTED_LAYOUTS))}; got {normalized!r}"
        )
    return normalized


def normalize_nmaster(value, workspace_id: str) -> int:
    if not isinstance(value, int):
        raise SystemExit(f"workspace {workspace_id} layout.mango.nmaster must be an integer")
    if not 0 <= value <= 99:
        raise SystemExit(f"workspace {workspace_id} layout.mango.nmaster must be between 0 and 99")
    return value


def normalize_mfact(value, workspace_id: str) -> str:
    if not isinstance(value, (int, float)):
        raise SystemExit(f"workspace {workspace_id} layout.mango.mfact must be numeric")
    numeric = float(value)
    if not 0.1 <= numeric <= 0.9:
        raise SystemExit(f"workspace {workspace_id} layout.mango.mfact must be between 0.1 and 0.9")
    return f"{numeric:.2f}".rstrip("0").rstrip(".")


def mango_layout_config_for_workspace(workspace):
    workspace_id = str(workspace["id"])
    layout = workspace.get("layout", {})
    if layout is None:
        layout = {}
    if isinstance(layout, list):
        mango_layout = {}
    elif isinstance(layout, dict):
        mango_layout = layout.get("mango", {})
        if mango_layout is None:
            mango_layout = {}
        if not isinstance(mango_layout, dict):
            raise SystemExit(f"workspace {workspace_id} layout.mango must be an object")
    else:
        raise SystemExit(f"workspace {workspace_id} layout must be an object or list")

    fields = OrderedDict()
    fields["no_hide"] = str(
        normalize_binary(mango_layout.get("noHide", 1), f"workspace {workspace_id} layout.mango.noHide")
    )
    fields["layout_name"] = normalize_layout_name(
        mango_layout.get("layoutName", "scroller"),
        workspace_id,
    )

    if "openAsFloating" in mango_layout:
        fields["open_as_floating"] = str(
            normalize_binary(
                mango_layout["openAsFloating"],
                f"workspace {workspace_id} layout.mango.openAsFloating",
            )
        )
    if "noRenderBorder" in mango_layout:
        fields["no_render_border"] = str(
            normalize_binary(
                mango_layout["noRenderBorder"],
                f"workspace {workspace_id} layout.mango.noRenderBorder",
            )
        )
    if "nmaster" in mango_layout:
        fields["nmaster"] = str(normalize_nmaster(mango_layout["nmaster"], workspace_id))
    if "mfact" in mango_layout:
        fields["mfact"] = normalize_mfact(mango_layout["mfact"], workspace_id)

    return fields


lines = [
    "# Generated from shared/wm/monitors.yaml and shared/wm/workspaces.json.",
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
    monitor_name = monitor_name_for_mango(monitor)
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

seen_workspaces = set()
for workspace_ref in sorted(profile.get("workspaces", []), key=lambda item: int(item["id"])):
    workspace_id = str(workspace_ref["id"])
    if workspace_id in seen_workspaces:
        raise SystemExit(f"Duplicate workspace mapping in profile '{profile_name}': {workspace_id}")
    seen_workspaces.add(workspace_id)

    workspace = workspaces_by_id.get(workspace_id)
    if workspace is None:
        raise SystemExit(f"Unknown workspace id '{workspace_id}' in profile '{profile_name}'")

    monitor = monitors_by_id.get(workspace_ref["monitor"])
    if monitor is None:
        raise SystemExit(
            f"Unknown monitor '{workspace_ref['monitor']}' in workspace for profile '{profile_name}'"
        )

    monitor_name = monitor_name_for_mango(monitor)
    tag_fields = OrderedDict(
        [
            ("id", workspace_id),
            ("monitor_name", monitor_name),
        ]
    )
    tag_fields.update(mango_layout_config_for_workspace(workspace))
    lines.append(f"# Tag {workspace_id}: {workspace['name']}")
    lines.append("tagrule=" + ",".join(f"{key}:{value}" for key, value in tag_fields.items()))

lines.append("")
out_path.write_text("\n".join(lines).rstrip() + "\n")

bind_lines = [
    "# Generated from shared/wm/monitors.yaml and shared/wm/workspaces.json.",
    "# Update the shared manifests and rerun modules/mangowm/scripts/render-profile.sh.",
    f"# Source checksum: {checksum}",
    "",
    f"# Active monitor profile: {profile_name}",
    "# Profile-aware workspace binds: switch follows the target monitor.",
    "# Shift-number moves are defined in conf.d/50-binds.conf via mango-tag-smart.",
    "# Alt binds focus the mapped app on the current tag, move it here if already open elsewhere, or launch it.",
    "",
]

for workspace_ref in sorted(profile.get("workspaces", []), key=lambda item: int(item["id"])):
    workspace_id = str(workspace_ref["id"])
    workspace = workspaces_by_id[workspace_id]
    monitor = monitors_by_id[workspace_ref["monitor"]]
    monitor_name = monitor_name_for_mango(monitor)
    here = workspace.get("here", {})
    here_target = here.get("target") or workspace.get("hereTarget") or workspace["name"]
    here_label = here.get("label") or workspace.get("hereLabel") or workspace["name"]
    bind_lines.append(f"# Tag {workspace_id}: {workspace['name']} ({monitor_name})")
    bind_lines.append(f"# Here label: {here_label}")
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

run_as_user install -D -m 644 "${tmp_profile}" "${PROFILE_OUT}"
run_as_user install -D -m 644 "${tmp_binds}" "${WORKSPACE_BINDS_OUT}"
