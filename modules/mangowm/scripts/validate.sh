#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${MODULE_DIR}/../.." && pwd)"
source "${REPO_ROOT}/modules/base/lib/core.sh"

mode="fast"
case "${1:-}" in
  ""|--fast)
    ;;
  --strict)
    mode="strict"
    ;;
  -h|--help)
    cat <<'EOF'
Usage: validate.sh [--fast|--strict]

--fast   Validate Mango-owned scripts, shared manifests, generated runtime drift,
         and parse the config through a temporary runtime tree.
--strict Validate the same set plus every shell helper under modules/scripts/bin.
EOF
    exit 0
    ;;
  *)
    echo "Unknown argument: ${1}" >&2
    exit 2
    ;;
esac

command -v bash >/dev/null 2>&1 || die "bash is required"
command -v mango >/dev/null 2>&1 || die "mango is required"
command -v jq >/dev/null 2>&1 || die "jq is required"
command -v python3 >/dev/null 2>&1 || die "python3 is required"

MANGO_RUNTIME_DIR="${MANGO_RUNTIME_DIR:-${USER_HOME}/.config/mango/runtime}"
CONFIG_FILE="${MODULE_DIR}/dotfiles/mango/config.conf"
WORKSPACE_SOURCE_FILE="${REPO_ROOT}/shared/wm/workspaces.json"
SHARED_MONITOR_ASSETS_SCRIPT="${REPO_ROOT}/shared/wm/render-monitor-assets.sh"
RENDER_THEME_SCRIPT="${MODULE_DIR}/scripts/render-theme.sh"
RENDER_PROFILE_SCRIPT="${MODULE_DIR}/scripts/render-profile.sh"
RENDER_WORKSPACE_ASSETS_SCRIPT="${MODULE_DIR}/scripts/render-workspace-assets.sh"
RENDER_KEYBIND_CHEATSHEET_SCRIPT="${MODULE_DIR}/scripts/render-keybind-cheatsheet.sh"

log_info "Validating MangoWM configuration..."

if [[ -x "${SHARED_MONITOR_ASSETS_SCRIPT}" ]]; then
  log_info "Validating shared monitor assets..."
  "${SHARED_MONITOR_ASSETS_SCRIPT}" --check >/dev/null
  log_success "Shared monitor assets match generated outputs!"
fi

log_info "Validating shared workspace manifest..."
jq empty "${WORKSPACE_SOURCE_FILE}" >/dev/null
log_success "Shared workspace manifest is valid JSON!"

log_info "Validating generated Mango theme..."
"${RENDER_THEME_SCRIPT}" --check >/dev/null
log_success "Generated Mango theme matches theme manifest!"

if [[ -d "${MANGO_RUNTIME_DIR}" ]]; then
  log_info "Validating Mango runtime drift..."
  if [ "$(id -u)" -eq 0 ]; then
    run_as_user "${RENDER_PROFILE_SCRIPT}" --check --out-dir "${MANGO_RUNTIME_DIR}" >/dev/null
    run_as_user "${RENDER_WORKSPACE_ASSETS_SCRIPT}" --check --runtime-dir "${MANGO_RUNTIME_DIR}" >/dev/null
    run_as_user "${RENDER_KEYBIND_CHEATSHEET_SCRIPT}" --check --runtime-dir "${MANGO_RUNTIME_DIR}" >/dev/null
  else
    "${RENDER_PROFILE_SCRIPT}" --check --out-dir "${MANGO_RUNTIME_DIR}" >/dev/null
    "${RENDER_WORKSPACE_ASSETS_SCRIPT}" --check --runtime-dir "${MANGO_RUNTIME_DIR}" >/dev/null
    "${RENDER_KEYBIND_CHEATSHEET_SCRIPT}" --check --runtime-dir "${MANGO_RUNTIME_DIR}" >/dev/null
  fi
  log_success "Mango runtime outputs are in sync!"
else
  log_warn "Mango runtime directory not found yet. Skipping installed-runtime drift check."
fi

log_info "Checking Mango bind semantics..."
python3 - "${MODULE_DIR}/dotfiles/mango/conf.d/50-binds.conf" <<'PY'
import sys
from pathlib import Path

binds_file = Path(sys.argv[1])
seen = {}
duplicates = []

for lineno, raw_line in enumerate(binds_file.read_text().splitlines(), start=1):
    line = raw_line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    kind, payload = line.split("=", 1)
    if kind not in {"bind", "binds"}:
        continue
    parts = [part.strip() for part in payload.split(",")]
    if len(parts) < 3:
        continue
    key = (parts[0].upper(), parts[1].upper())
    if key in seen:
        duplicates.append((key, seen[key], lineno))
    else:
        seen[key] = lineno

if duplicates:
    for (mods, key), first, second in duplicates:
        print(
            f"Duplicate Mango bind for {mods},{key} at lines {first} and {second}",
            file=sys.stderr,
        )
    raise SystemExit(1)
PY
log_success "No duplicate Mango binds detected!"

tmp_root="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp_root}"
}
trap cleanup EXIT

tmp_runtime="${tmp_root}/runtime"
tmp_mango_dir="${tmp_root}/mango"
mkdir -p "${tmp_runtime}" "${tmp_mango_dir}/generated"
ln -s "${MODULE_DIR}/dotfiles/mango/conf.d" "${tmp_mango_dir}/conf.d"
ln -s "${CONFIG_FILE}" "${tmp_mango_dir}/config.conf"
ln -s "${MODULE_DIR}/dotfiles/mango/generated/theme.conf" "${tmp_mango_dir}/generated/theme.conf"
ln -s "${tmp_runtime}" "${tmp_mango_dir}/runtime"

"${RENDER_PROFILE_SCRIPT}" --out-dir "${tmp_runtime}" >/dev/null
"${RENDER_WORKSPACE_ASSETS_SCRIPT}" --runtime-dir "${tmp_runtime}" >/dev/null
"${RENDER_KEYBIND_CHEATSHEET_SCRIPT}" --runtime-dir "${tmp_runtime}" >/dev/null

log_info "Validating Mango config parse against temporary runtime..."
mango -c "${tmp_mango_dir}/config.conf" -p >/dev/null
log_success "Mango config parses successfully with rendered runtime files!"

helper_failure=0
helper_candidates=(
  "${MODULE_DIR}/scripts/install.sh"
  "${MODULE_DIR}/scripts/ensure-runtime-files.sh"
  "${MODULE_DIR}/scripts/render-theme.sh"
  "${MODULE_DIR}/scripts/render-profile.sh"
  "${MODULE_DIR}/scripts/render-workspace-assets.sh"
  "${MODULE_DIR}/scripts/render-keybind-cheatsheet.sh"
  "${MODULE_DIR}/scripts/validate.sh"
  "${REPO_ROOT}/modules/scripts/bin/mango-arrange.sh"
  "${REPO_ROOT}/modules/scripts/bin/mango-monitor-smart.sh"
  "${REPO_ROOT}/modules/scripts/bin/mango-here.sh"
  "${REPO_ROOT}/modules/scripts/bin/mango-tag-smart.sh"
  "${REPO_ROOT}/modules/scripts/bin/mango-workspace-smart.sh"
  "${REPO_ROOT}/modules/scripts/bin/mango-session-common.sh"
  "${REPO_ROOT}/modules/scripts/bin/mango-session-refresh.sh"
  "${REPO_ROOT}/modules/scripts/bin/mango-session-doctor.sh"
  "${REPO_ROOT}/modules/scripts/bin/mango-session-init.sh"
  "${REPO_ROOT}/modules/scripts/bin/mango-bootstrap.sh"
  "${REPO_ROOT}/modules/scripts/bin/mango-post-bootstrap.sh"
  "${REPO_ROOT}/modules/scripts/bin/mango-desktop-settings.sh"
  "${REPO_ROOT}/modules/scripts/bin/mango-status-notifier-ready.sh"
  "${REPO_ROOT}/modules/sessions/dotfiles/mango-session"
  "${REPO_ROOT}/modules/sessions/dotfiles/mango-uwsm-session"
)

if [[ "${mode}" == "strict" ]]; then
  while IFS= read -r helper_script; do
    [[ -n "${helper_script}" ]] || continue
    helper_candidates+=("${helper_script}")
  done < <(
    find "${REPO_ROOT}/modules/scripts/bin" -maxdepth 1 -type f -name '*.sh' | sort
  )
fi

log_info "Validating Mango helper shell syntax..."
while IFS= read -r helper_script; do
  [[ -n "${helper_script}" ]] || continue
  if ! bash -n "${helper_script}"; then
    log_error "Shell syntax check failed: ${helper_script}"
    helper_failure=1
  fi
done < <(printf '%s\n' "${helper_candidates[@]}" | sort -u)

if [[ "${helper_failure}" -ne 0 ]]; then
  exit 1
fi

log_success "Mango helper shell syntax is valid!"
