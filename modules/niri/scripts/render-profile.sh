#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${MODULE_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/modules/base/lib/core.sh"

PROFILE_MANIFEST="${NIRI_PROFILE_MANIFEST:-${REPO_ROOT}/modules/hyprland/monitors/profile.env}"
PROFILES_DIR="${NIRI_PROFILE_DIR:-${REPO_ROOT}/modules/hyprland/monitors/profiles}"
OUTPUT_MAP_FILE="${NIRI_OUTPUT_MAP_FILE:-${MODULE_DIR}/profiles/output-map.tsv}"
TARGET_DMS_DIR="${NIRI_DMS_DIR:-${USER_HOME}/.config/niri/dms}"
OUTPUTS_OUT="${TARGET_DMS_DIR}/outputs.kdl"
WORKSPACES_OUT="${TARGET_DMS_DIR}/workspaces-auto.kdl"

usage() {
  cat <<'EOF'
Usage: render-profile.sh [--check] [--out-dir DIR]

Without arguments, renders the static Niri outputs/workspaces files from the
selected monitor profile.
With --check, verifies the rendered files match the target directory.
EOF
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "$value"
}

format_scale() {
  local scale="$1"

  if [[ "$scale" =~ ^[0-9]+$ ]]; then
    printf '%s.0\n' "$scale"
    return 0
  fi

  printf '%s\n' "$scale"
}

mode="write"
while (($#)); do
  case "$1" in
    --check)
      mode="check"
      shift
      ;;
    --out-dir)
      TARGET_DMS_DIR="$2"
      OUTPUTS_OUT="${TARGET_DMS_DIR}/outputs.kdl"
      WORKSPACES_OUT="${TARGET_DMS_DIR}/workspaces-auto.kdl"
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

# shellcheck source=/dev/null
source "${PROFILE_MANIFEST}"

: "${HYPR_MONITOR_PROFILE:=desk}"

PROFILE_FILE="${PROFILES_DIR}/${HYPR_MONITOR_PROFILE}.conf"
[[ -r "${PROFILE_FILE}" ]] || die "Unknown HYPR_MONITOR_PROFILE: ${HYPR_MONITOR_PROFILE}"

declare -A OUTPUT_NAME_MAP=()

while IFS=$'\t' read -r raw_selector raw_output _rest; do
  [[ -n "${raw_selector:-}" ]] || continue
  [[ "${raw_selector#\#}" == "${raw_selector}" ]] || continue

  selector="$(trim "${raw_selector}")"
  output_name="$(trim "${raw_output:-}")"
  [[ -n "${selector}" && -n "${output_name}" ]] || continue
  OUTPUT_NAME_MAP["${selector}"]="${output_name}"
done < "${OUTPUT_MAP_FILE}"

manifest_checksum="$(
  sha256sum "${PROFILE_MANIFEST}" "${PROFILE_FILE}" "${OUTPUT_MAP_FILE}" |
    awk '{print $1}' |
    sha256sum |
    awk '{print $1}'
)"

tmp_outputs="$(mktemp)"
tmp_workspaces="$(mktemp)"

cleanup() {
  rm -f "${tmp_outputs}" "${tmp_workspaces}"
}
trap cleanup EXIT

{
  printf '// Generated from modules/hyprland/monitors/profile.env and %s.\n' "$(basename "${PROFILE_FILE}")"
  printf '// Update the selected monitor profile or output map and rerun modules/niri/scripts/render-profile.sh.\n'
  printf '// Source checksum: %s\n\n' "${manifest_checksum}"
} > "${tmp_outputs}"

{
  printf '// Generated from modules/hyprland/monitors/profile.env and %s.\n' "$(basename "${PROFILE_FILE}")"
  printf '// Update the selected monitor profile or output map and rerun modules/niri/scripts/render-profile.sh.\n'
  printf '// Source checksum: %s\n\n' "${manifest_checksum}"
} > "${tmp_workspaces}"

declare -A seen_outputs=()
declare -A seen_workspaces=()

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -n "${line//[[:space:]]/}" ]] || continue
  [[ "${line#\#}" == "${line}" ]] || continue

  case "$line" in
    monitor=*)
      payload="${line#monitor=}"
      IFS=',' read -r monitor_selector mode_value position_value scale_value _ <<<"${payload}"
      monitor_selector="$(trim "${monitor_selector}")"
      [[ -n "${monitor_selector}" ]] || continue

      output_name="${OUTPUT_NAME_MAP["${monitor_selector}"]:-}"
      [[ -n "${output_name}" ]] || die "Missing Niri output map for monitor selector: ${monitor_selector}"
      [[ -z "${seen_outputs[${output_name}]:-}" ]] || continue
      seen_outputs["${output_name}"]=1

      position_value="$(trim "${position_value}")"
      scale_value="$(format_scale "$(trim "${scale_value}")")"
      pos_x="${position_value%%x*}"
      pos_y="${position_value#*x}"

      {
        printf 'output "%s" {\n' "${output_name}"
        printf '  mode "%s"\n' "$(trim "${mode_value}")"
        printf '  position x=%s y=%s\n' "${pos_x}" "${pos_y}"
        printf '  scale %s\n' "${scale_value}"
        if [[ "${output_name}" == eDP* ]]; then
          printf '  variable-refresh-rate on-demand=true\n'
        fi
        printf '}\n\n'
      } >> "${tmp_outputs}"
      ;;
    workspace=*)
      payload="${line#workspace=}"
      workspace_id="$(trim "${payload%%,*}")"
      remainder="${payload#*,}"
      monitor_ref="$(trim "${remainder%%,*}")"
      monitor_ref="${monitor_ref#monitor:}"
      output_name="${OUTPUT_NAME_MAP["${monitor_ref}"]:-}"

      [[ -n "${output_name}" ]] || die "Missing Niri output map for workspace selector: ${monitor_ref}"
      [[ -z "${seen_workspaces[${workspace_id}]:-}" ]] || die "Duplicate workspace mapping in profile: ${workspace_id}"
      seen_workspaces["${workspace_id}"]=1

      {
        printf 'workspace "%s" {\n' "${workspace_id}"
        printf '  open-on-output "%s"\n' "${output_name}"
        if [[ "${workspace_id}" == "8" ]]; then
          printf '  layout {\n'
          printf '    border {\n'
          printf '      active-color "#89dceb"\n'
          printf '      inactive-color "#313244"\n'
          printf '    }\n'
          printf '  }\n'
        fi
        printf '}\n\n'
      } >> "${tmp_workspaces}"
      ;;
  esac
done < "${PROFILE_FILE}"

if [[ "${mode}" == "check" ]]; then
  diff -u "${OUTPUTS_OUT}" "${tmp_outputs}"
  diff -u "${WORKSPACES_OUT}" "${tmp_workspaces}"
  exit 0
fi

run_as_user mkdir -p "${TARGET_DMS_DIR}"
run_as_user install -m 644 "${tmp_outputs}" "${OUTPUTS_OUT}"
run_as_user install -m 644 "${tmp_workspaces}" "${WORKSPACES_OUT}"
