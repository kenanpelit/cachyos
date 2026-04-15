#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${MODULE_DIR}/../.." && pwd)"
SHARED_MONITOR_ASSETS_SCRIPT="${REPO_ROOT}/shared/wm/render-monitor-assets.sh"
SHARED_MONITOR_MANIFEST="${NIRI_SHARED_MONITOR_MANIFEST:-${REPO_ROOT}/shared/wm/monitors.yaml}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/modules/base/lib/core.sh"

PROFILE_MANIFEST="${NIRI_PROFILE_MANIFEST:-${MODULE_DIR}/profiles/profile.env}"
WORKSPACE_MAP_FILE="${NIRI_WORKSPACE_MAP_FILE:-${MODULE_DIR}/workspaces/workspaces.json}"
TARGET_RUNTIME_DIR="${NIRI_RUNTIME_DIR:-${USER_HOME}/.config/niri/runtime}"
WORKSPACES_OUT="${TARGET_RUNTIME_DIR}/workspaces-auto.kdl"

usage() {
  cat <<'EOF'
Usage: render-profile.sh [--check] [--out-dir DIR]

Without arguments, renders the static Niri workspace placement file from the
selected shared monitor profile.
With --check, verifies the rendered workspace file matches the target directory.
EOF
}

shared_monitor_manifest_checksum() {
  python3 - "${SHARED_MONITOR_MANIFEST}" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

import yaml

manifest_path = Path(sys.argv[1])
data = yaml.safe_load(manifest_path.read_text())
payload = {
    "monitors": data.get("monitors", []),
    "profiles": data.get("profiles", {}),
}
print(hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()).hexdigest())
PY
}

mode="write"
while (($#)); do
  case "$1" in
    --check)
      mode="check"
      shift
      ;;
    --out-dir)
      TARGET_RUNTIME_DIR="$2"
      WORKSPACES_OUT="${TARGET_RUNTIME_DIR}/workspaces-auto.kdl"
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

if [[ -x "${SHARED_MONITOR_ASSETS_SCRIPT}" ]]; then
  "${SHARED_MONITOR_ASSETS_SCRIPT}" $([[ "${mode}" == "check" ]] && printf '%s' '--check')
fi

[[ -r "${PROFILE_MANIFEST}" ]] || die "Profile manifest not found: ${PROFILE_MANIFEST}"
[[ -r "${SHARED_MONITOR_MANIFEST}" ]] || die "Shared monitor manifest not found: ${SHARED_MONITOR_MANIFEST}"
[[ -r "${WORKSPACE_MAP_FILE}" ]] || die "Workspace map not found: ${WORKSPACE_MAP_FILE}"
command -v python3 >/dev/null 2>&1 || die "python3 is required for render-profile.sh"

# shellcheck source=/dev/null
source "${PROFILE_MANIFEST}"

: "${NIRI_MONITOR_PROFILE:=${HYPR_MONITOR_PROFILE:-desk}}"

shared_monitor_checksum="$(shared_monitor_manifest_checksum)"
manifest_checksum="$(
  {
    printf '%s  %s\n' "${shared_monitor_checksum}" "${SHARED_MONITOR_MANIFEST}"
    sha256sum "${PROFILE_MANIFEST}" "${WORKSPACE_MAP_FILE}"
  } |
    awk '{print $1}' |
    sha256sum |
    awk '{print $1}'
)"

tmp_workspaces="$(mktemp)"
chmod 0644 "${tmp_workspaces}"

cleanup() {
  rm -f "${tmp_workspaces}"
}
trap cleanup EXIT

python3 - "${SHARED_MONITOR_MANIFEST}" "${WORKSPACE_MAP_FILE}" "${NIRI_MONITOR_PROFILE}" "${manifest_checksum}" "${tmp_workspaces}" <<'PY'
import json
import sys
from pathlib import Path

import yaml

manifest_path = Path(sys.argv[1])
workspace_path = Path(sys.argv[2])
profile_name = sys.argv[3]
checksum = sys.argv[4]
out_path = Path(sys.argv[5])

manifest = yaml.safe_load(manifest_path.read_text())
workspace_data = json.loads(workspace_path.read_text())

monitors = manifest.get("monitors", [])
profiles = manifest.get("profiles", {})
workspaces = workspace_data.get("workspaces", [])
profile = profiles.get(profile_name)

if profile is None:
    raise SystemExit(f"Unknown NIRI_MONITOR_PROFILE: {profile_name}")

monitors_by_id = {monitor["id"]: monitor for monitor in monitors}
workspaces_by_id = {str(workspace["id"]): workspace for workspace in workspaces}

lines = [
    "// Generated from modules/niri/profiles/profile.env and shared/wm/monitors.yaml.",
    "// Update the selected monitor profile or shared monitor manifest and rerun modules/niri/scripts/render-profile.sh.",
    f"// Source checksum: {checksum}",
    "",
]

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

    workspace_name = workspace["name"]
    output_name = monitor.get("niri_name", monitor["id"])
    layout = workspace.get("layout", {})
    layout_lines = []
    if isinstance(layout, list):
        layout_lines = layout
    elif isinstance(layout, dict):
        layout_lines = layout.get("lines", [])

    lines.append(f'workspace "{workspace_name}" {{')
    lines.append(f'  open-on-output "{output_name}"')
    if layout_lines:
        lines.append("  layout {")
        for layout_line in layout_lines:
          lines.append(f"    {layout_line}")
        lines.append("  }")
    lines.append("}")
    lines.append("")

out_path.write_text("\n".join(lines).rstrip() + "\n")
PY

if [[ "${mode}" == "check" ]]; then
  diff -u "${WORKSPACES_OUT}" "${tmp_workspaces}"
  exit 0
fi

run_as_user mkdir -p "${TARGET_RUNTIME_DIR}"
run_as_user install -m 644 "${tmp_workspaces}" "${WORKSPACES_OUT}"
