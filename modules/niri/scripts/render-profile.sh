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
PROFILES_DIR="${NIRI_PROFILE_DIR:-${MODULE_DIR}/profiles/profiles}"
WORKSPACE_MAP_FILE="${NIRI_WORKSPACE_MAP_FILE:-${MODULE_DIR}/workspaces/workspaces.json}"
TARGET_RUNTIME_DIR="${NIRI_RUNTIME_DIR:-${USER_HOME}/.config/niri/runtime}"
WORKSPACES_OUT="${TARGET_RUNTIME_DIR}/workspaces-auto.kdl"

usage() {
  cat <<'EOF'
Usage: render-profile.sh [--check] [--out-dir DIR]

Without arguments, renders the static Niri workspace placement file from the
selected Niri monitor profile.
With --check, verifies the rendered workspace file matches the target directory.
EOF
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "$value"
}

workspace_layout_lines() {
  local workspace_id="$1"
  jq -r --arg workspace_id "${workspace_id}" '
    .workspaces[]
    | select(.id == $workspace_id)
    | (
        if (.layout | type) == "array" then
          .layout
        else
          (.layout.lines // [])
        end
      )
    | if type == "array" then .[] else empty end
  ' "${WORKSPACE_MAP_FILE}"
}

shared_monitor_output_map() {
  python3 - "${SHARED_MONITOR_MANIFEST}" <<'PY'
import sys
from pathlib import Path

import yaml

manifest_path = Path(sys.argv[1])
data = yaml.safe_load(manifest_path.read_text())

for monitor in data.get("monitors", []):
    selector = (monitor.get("selector") or "").strip()
    output_name = (monitor.get("niri_name") or "").strip()
    if selector and output_name:
        print(f"{selector}\t{output_name}")
PY
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
command -v jq >/dev/null 2>&1 || die "jq is required for render-profile.sh"
command -v python3 >/dev/null 2>&1 || die "python3 is required for render-profile.sh"

# shellcheck source=/dev/null
source "${PROFILE_MANIFEST}"

: "${NIRI_MONITOR_PROFILE:=${HYPR_MONITOR_PROFILE:-desk}}"

PROFILE_FILE="${PROFILES_DIR}/${NIRI_MONITOR_PROFILE}.conf"
[[ -r "${PROFILE_FILE}" ]] || die "Unknown NIRI_MONITOR_PROFILE: ${NIRI_MONITOR_PROFILE}"

declare -A OUTPUT_NAME_MAP=()
declare -A WORKSPACE_NAME_MAP=()

while IFS=$'\t' read -r raw_selector raw_output _rest; do
  [[ -n "${raw_selector:-}" ]] || continue
  [[ "${raw_selector#\#}" == "${raw_selector}" ]] || continue

  selector="$(trim "${raw_selector}")"
  output_name="$(trim "${raw_output:-}")"
  [[ -n "${selector}" && -n "${output_name}" ]] || continue
  OUTPUT_NAME_MAP["${selector}"]="${output_name}"
done < <(shared_monitor_output_map)

while IFS=$'\t' read -r workspace_id workspace_name; do
  [[ -n "${workspace_id}" && -n "${workspace_name}" ]] || continue
  WORKSPACE_NAME_MAP["${workspace_id}"]="${workspace_name}"
done < <(jq -r '.workspaces[] | [.id, .name] | @tsv' "${WORKSPACE_MAP_FILE}")

shared_monitor_checksum="$(shared_monitor_manifest_checksum)"
manifest_checksum="$(
  {
    printf '%s  %s\n' "${shared_monitor_checksum}" "${SHARED_MONITOR_MANIFEST}"
    sha256sum "${PROFILE_MANIFEST}" "${PROFILE_FILE}" "${WORKSPACE_MAP_FILE}"
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

{
  printf '// Generated from modules/niri/profiles/profile.env and %s.\n' "$(basename "${PROFILE_FILE}")"
  printf '// Update the selected monitor profile or shared monitor manifest and rerun modules/niri/scripts/render-profile.sh.\n'
  printf '// Source checksum: %s\n\n' "${manifest_checksum}"
} > "${tmp_workspaces}"

declare -A seen_workspaces=()

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -n "${line//[[:space:]]/}" ]] || continue
  [[ "${line#\#}" == "${line}" ]] || continue

  case "$line" in
    monitor=*)
      continue
      ;;
    workspace=*)
      payload="${line#workspace=}"
      workspace_id="$(trim "${payload%%,*}")"
      workspace_name="${WORKSPACE_NAME_MAP["${workspace_id}"]:-}"
      remainder="${payload#*,}"
      monitor_ref="$(trim "${remainder%%,*}")"
      monitor_ref="${monitor_ref#monitor:}"
      output_name="${OUTPUT_NAME_MAP["${monitor_ref}"]:-}"

      [[ -n "${output_name}" ]] || die "Missing Niri output name for workspace selector: ${monitor_ref}"
      [[ -n "${workspace_name}" ]] || die "Missing Niri workspace name mapping for slot: ${workspace_id}"
      [[ -z "${seen_workspaces[${workspace_id}]:-}" ]] || die "Duplicate workspace mapping in profile: ${workspace_id}"
      seen_workspaces["${workspace_id}"]=1
      workspace_layout="$(workspace_layout_lines "${workspace_id}")"

      {
        printf 'workspace "%s" {\n' "${workspace_name}"
        printf '  open-on-output "%s"\n' "${output_name}"
        if [[ -n "${workspace_layout}" ]]; then
          printf '  layout {\n'
          while IFS= read -r layout_line; do
            [[ -n "${layout_line}" ]] || continue
            printf '    %s\n' "${layout_line}"
          done <<< "${workspace_layout}"
          printf '  }\n'
        fi
        printf '}\n\n'
      } >> "${tmp_workspaces}"
      ;;
  esac
done < "${PROFILE_FILE}"

if [[ "${mode}" == "check" ]]; then
  diff -u "${WORKSPACES_OUT}" "${tmp_workspaces}"
  exit 0
fi

run_as_user mkdir -p "${TARGET_RUNTIME_DIR}"
run_as_user install -m 644 "${tmp_workspaces}" "${WORKSPACES_OUT}"
