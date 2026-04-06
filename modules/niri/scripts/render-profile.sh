#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${MODULE_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/modules/base/lib/core.sh"

PROFILE_MANIFEST="${NIRI_PROFILE_MANIFEST:-${MODULE_DIR}/profiles/profile.env}"
PROFILES_DIR="${NIRI_PROFILE_DIR:-${MODULE_DIR}/profiles/profiles}"
OUTPUT_MAP_FILE="${NIRI_OUTPUT_MAP_FILE:-${MODULE_DIR}/profiles/output-map.tsv}"
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
    | (.layout // [])
    | if type == "array" then .[] else empty end
  ' "${WORKSPACE_MAP_FILE}"
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

[[ -r "${PROFILE_MANIFEST}" ]] || die "Profile manifest not found: ${PROFILE_MANIFEST}"
[[ -r "${OUTPUT_MAP_FILE}" ]] || die "Output map not found: ${OUTPUT_MAP_FILE}"
[[ -r "${WORKSPACE_MAP_FILE}" ]] || die "Workspace map not found: ${WORKSPACE_MAP_FILE}"
command -v jq >/dev/null 2>&1 || die "jq is required for render-profile.sh"

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
done < "${OUTPUT_MAP_FILE}"

while IFS=$'\t' read -r workspace_id workspace_name; do
  [[ -n "${workspace_id}" && -n "${workspace_name}" ]] || continue
  WORKSPACE_NAME_MAP["${workspace_id}"]="${workspace_name}"
done < <(jq -r '.workspaces[] | [.id, .name] | @tsv' "${WORKSPACE_MAP_FILE}")

manifest_checksum="$(
  sha256sum "${PROFILE_MANIFEST}" "${PROFILE_FILE}" "${OUTPUT_MAP_FILE}" "${WORKSPACE_MAP_FILE}" |
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
  printf '// Update the selected monitor profile or output map and rerun modules/niri/scripts/render-profile.sh.\n'
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

      [[ -n "${output_name}" ]] || die "Missing Niri output map for workspace selector: ${monitor_ref}"
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
