#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
SOURCE_FILE="${MODULE_DIR}/dotfiles/hypr/workspace-rules.tsv"
OUT_FILE="${MODULE_DIR}/dotfiles/hypr/conf.d/rules/20-workspace-routing.conf"

usage() {
  cat <<'EOF'
Usage: render-workspace-routing.sh [--check]

Without arguments, regenerates the static Hyprland workspace routing rules from
workspace-rules.tsv.
With --check, verifies that the generated file matches the TSV source.
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

[[ -r "${SOURCE_FILE}" ]] || {
  printf 'Missing workspace rules source: %s\n' "${SOURCE_FILE}" >&2
  exit 1
}

manifest_checksum="$(sha256sum "${SOURCE_FILE}" | awk '{print $1}')"
tmp_out="$(mktemp)"

cleanup() {
  rm -f "${tmp_out}"
}
trap cleanup EXIT

write_if_changed() {
  local generated="$1"
  local current="$2"
  local current_mode=""

  if [[ -e "$current" ]]; then
    current_mode="$(stat -c '%a' "$current")"
  fi

  if cmp -s "$generated" "$current" 2>/dev/null &&
    [[ -O "$current" ]] &&
    [[ "$current_mode" == "644" ]]; then
    return 0
  fi

  install -m 644 "$generated" "$current"
}

parse_rule_line() {
  local line="$1"

  RULE_PATTERN="$(awk -F $'\t' '{print $1}' <<<"${line}")"
  RULE_WORKSPACE="$(awk -F $'\t' '{print $2}' <<<"${line}")"
  RULE_TITLE="$(awk -F $'\t' '{print $3}' <<<"${line}")"
  RULE_MODE="$(awk -F $'\t' '{print $4}' <<<"${line}")"
}

{
  printf '# Generated from modules/hyprland/dotfiles/hypr/workspace-rules.tsv.\n'
  printf '# Update the TSV and rerun modules/hyprland/scripts/render-workspace-routing.sh.\n'
  printf '# Source checksum: %s\n\n' "${manifest_checksum}"
  printf '# Static workspace placement.\n'
  printf '# Monitor ownership and persistence stay in 70-monitors.conf.\n\n'

  while IFS= read -r line; do
    [[ -n "${line//[[:space:]]/}" ]] || continue
    [[ "${line:0:1}" != "#" ]] || continue

    parse_rule_line "${line}"

    [[ -n "${RULE_PATTERN//[[:space:]]/}" ]] || continue
    [[ -n "${RULE_WORKSPACE//[[:space:]]/}" ]] || continue

    printf 'windowrule = match:class %s' "${RULE_PATTERN}"

    if [[ -n "${RULE_TITLE:-}" ]]; then
      printf ', match:initial_title %s' "${RULE_TITLE}"
    fi

    printf ', workspace %s' "${RULE_WORKSPACE}"

    if [[ "${RULE_MODE:-}" == "silent" ]]; then
      printf ' silent'
    fi

    printf '\n'
  done <"${SOURCE_FILE}"
} >"${tmp_out}"

if [[ "${mode}" == "check" ]]; then
  diff -u "${OUT_FILE}" "${tmp_out}"
  exit 0
fi

write_if_changed "${tmp_out}" "${OUT_FILE}"
