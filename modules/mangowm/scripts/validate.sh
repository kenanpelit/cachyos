#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${MODULE_DIR}/../.." && pwd)"
source "${REPO_ROOT}/modules/base/lib/core.sh"

mode="fast"
case "${1:-}" in
"" | --fast)
	;;
--strict)
	mode="strict"
	;;
-h | --help)
	cat <<'EOF'
Usage: validate.sh [--fast|--strict|--live]

--fast   Validate Mango-owned scripts, shared manifests, generated asset drift,
         runtime compatibility links, and parse the config through a temporary
         generated/runtime tree.
--strict Validate the same set plus every shell helper under modules/scripts/bin.
--live   Validate the same set plus the active MangoWM IPC/session state.
EOF
	exit 0
	;;
--live)
	mode="live"
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
MANGO_GENERATED_DIR="${MANGO_GENERATED_DIR:-${MODULE_DIR}/dotfiles/mango/generated}"
CONFIG_FILE="${MODULE_DIR}/dotfiles/mango/config.conf"
PROFILE_MANIFEST="${MODULE_DIR}/profiles/profile.env"
THEME_MANIFEST="${MODULE_DIR}/theme/theme.env"
WORKSPACE_SOURCE_FILE="${REPO_ROOT}/shared/wm/workspaces.json"
SHARED_MONITOR_MANIFEST="${REPO_ROOT}/shared/wm/monitors.yaml"
SHARED_MONITOR_ASSETS_SCRIPT="${REPO_ROOT}/shared/wm/render-monitor-assets.sh"
RENDER_PACKAGES_SCRIPT="${MODULE_DIR}/scripts/render-packages.sh"
RENDER_THEME_SCRIPT="${MODULE_DIR}/scripts/render-theme.sh"
RENDER_PROFILE_SCRIPT="${MODULE_DIR}/scripts/render-profile.sh"
RENDER_WORKSPACE_ASSETS_SCRIPT="${MODULE_DIR}/scripts/render-workspace-assets.sh"
RENDER_WINDOW_RULES_SCRIPT="${MODULE_DIR}/scripts/render-window-rules.sh"
RENDER_KEYBIND_CHEATSHEET_SCRIPT="${MODULE_DIR}/scripts/render-keybind-cheatsheet.sh"

# shellcheck source=/dev/null
source "${PROFILE_MANIFEST}"
# shellcheck source=/dev/null
source "${THEME_MANIFEST}"

: "${MANGO_MONITOR_PROFILE:=desk}"

log_info "Validating MangoWM configuration..."

if [[ -x "${SHARED_MONITOR_ASSETS_SCRIPT}" ]]; then
	log_info "Validating shared monitor assets..."
	"${SHARED_MONITOR_ASSETS_SCRIPT}" --check >/dev/null
	log_success "Shared monitor assets match generated outputs!"
fi

log_info "Validating shared workspace manifest..."
jq empty "${WORKSPACE_SOURCE_FILE}" >/dev/null
log_success "Shared workspace manifest is valid JSON!"

log_info "Validating shared workspace manifest semantics..."
python3 - "${WORKSPACE_SOURCE_FILE}" <<'PY'
import json
import sys
from pathlib import Path

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
ALLOWED_MANGO_KEYS = {
    "layoutName",
    "mfact",
    "nmaster",
    "noHide",
    "openAsFloating",
    "noRenderBorder",
}

workspace_file = Path(sys.argv[1])
data = json.loads(workspace_file.read_text())
workspaces = data.get("workspaces")
if not isinstance(workspaces, list):
    raise SystemExit("shared/wm/workspaces.json must contain a top-level 'workspaces' array")

seen_ids = set()
errors = []


def normalize_binary(value, field_name):
    if isinstance(value, bool):
        return
    if isinstance(value, int) and value in (0, 1):
        return
    errors.append(f"{field_name} must be 0/1 or boolean, got {value!r}")


for index, workspace in enumerate(workspaces, start=1):
    workspace_id = str(workspace.get("id", ""))
    if not workspace_id:
        errors.append(f"workspace[{index}] is missing id")
        continue
    if workspace_id in seen_ids:
        errors.append(f"duplicate workspace id {workspace_id}")
    seen_ids.add(workspace_id)

    layout = workspace.get("layout")
    if layout is None:
        continue

    if isinstance(layout, list):
        if not all(isinstance(line, str) for line in layout):
            errors.append(f"workspace {workspace_id} layout list must only contain strings")
        continue

    if not isinstance(layout, dict):
        errors.append(f"workspace {workspace_id} layout must be an object or list")
        continue

    layout_lines = layout.get("lines", [])
    if layout_lines is None:
        layout_lines = []
    if not isinstance(layout_lines, list) or not all(isinstance(line, str) for line in layout_lines):
        errors.append(f"workspace {workspace_id} layout.lines must be an array of strings")

    mango = layout.get("mango")
    if mango is None:
        continue
    if not isinstance(mango, dict):
        errors.append(f"workspace {workspace_id} layout.mango must be an object")
        continue

    unknown_keys = sorted(set(mango) - ALLOWED_MANGO_KEYS)
    if unknown_keys:
        errors.append(
            f"workspace {workspace_id} layout.mango has unknown keys: {', '.join(unknown_keys)}"
        )

    if "layoutName" in mango:
        value = mango["layoutName"]
        if not isinstance(value, str) or value not in SUPPORTED_LAYOUTS:
            errors.append(
                f"workspace {workspace_id} layout.mango.layoutName must be one of "
                f"{', '.join(sorted(SUPPORTED_LAYOUTS))}"
            )
    if "mfact" in mango:
        value = mango["mfact"]
        if not isinstance(value, (int, float)) or not 0.1 <= float(value) <= 0.9:
            errors.append(f"workspace {workspace_id} layout.mango.mfact must be between 0.1 and 0.9")
    if "nmaster" in mango:
        value = mango["nmaster"]
        if not isinstance(value, int) or not 0 <= value <= 99:
            errors.append(f"workspace {workspace_id} layout.mango.nmaster must be an integer between 0 and 99")
    for field in ("noHide", "openAsFloating", "noRenderBorder"):
        if field in mango:
            normalize_binary(mango[field], f"workspace {workspace_id} layout.mango.{field}")

if errors:
    for error in errors:
        print(error, file=sys.stderr)
    raise SystemExit(1)
PY
log_success "Shared workspace manifest semantics are valid!"

log_info "Validating generated Mango package manifest..."
"${RENDER_PACKAGES_SCRIPT}" --check >/dev/null
log_success "Generated Mango package manifest matches theme variant!"

log_info "Validating generated Mango theme..."
"${RENDER_THEME_SCRIPT}" --check >/dev/null
log_success "Generated Mango theme matches theme manifest!"

case "${MANGO_PACKAGE_VARIANT}" in
full | full-git)
	expected_family=(mangowm-git)
	other_family=(mangowm mangowm-wlonly mangowm-wlonly-git)
	;;
full-stable)
	expected_family=(mangowm)
	other_family=(mangowm-wlonly mangowm-wlonly-git)
	;;
wlonly | wlonly-git)
	expected_family=(mangowm-wlonly-git)
	other_family=(mangowm mangowm-git mangowm-wlonly)
	;;
wlonly-stable)
	expected_family=(mangowm-wlonly)
	other_family=(mangowm mangowm-git mangowm-wlonly-git)
	;;
*)
	die "Unknown MANGO_PACKAGE_VARIANT: ${MANGO_PACKAGE_VARIANT}"
	;;
esac

if command -v pacman >/dev/null 2>&1; then
	log_info "Checking installed Mango package family..."
	selected_installed=""
	other_installed=""
	for candidate in "${expected_family[@]}"; do
		if pacman -Qq "${candidate}" >/dev/null 2>&1; then
			selected_installed="${candidate}"
			break
		fi
	done
	for candidate in "${other_family[@]}"; do
		if pacman -Qq "${candidate}" >/dev/null 2>&1; then
			other_installed="${candidate}"
			break
		fi
	done

	if [[ -n "${selected_installed}" ]]; then
		log_success "Installed Mango package family matches theme variant (${selected_installed})!"
	elif [[ -n "${other_installed}" ]]; then
		die "theme/theme.env selects '${MANGO_PACKAGE_VARIANT}', but installed Mango package is ${other_installed}"
	else
		log_warn "Could not confirm an installed Mango package via pacman. Skipping backend-family check."
	fi
fi

log_info "Validating generated Mango workspace/profile assets..."
"${RENDER_PROFILE_SCRIPT}" --check >/dev/null
"${RENDER_WORKSPACE_ASSETS_SCRIPT}" --check >/dev/null
"${RENDER_WINDOW_RULES_SCRIPT}" --check >/dev/null
"${RENDER_KEYBIND_CHEATSHEET_SCRIPT}" --check >/dev/null
log_success "Generated Mango profile, workspace, and cheatsheet assets are in sync!"

if [[ -d "${MANGO_RUNTIME_DIR}" ]]; then
	log_info "Validating Mango runtime compatibility mirror..."
	runtime_warning=0
	for runtime_asset in \
		profile.conf \
		workspace-binds.conf \
		workspace-rules.conf \
		window-rules.conf \
		keybind-cheatsheet.conf; do
		generated_file="${MANGO_GENERATED_DIR}/${runtime_asset}"
		runtime_file="${MANGO_RUNTIME_DIR}/${runtime_asset}"

		if [[ ! -e "${runtime_file}" ]]; then
			die "Missing Mango runtime compatibility file: ${runtime_file}"
		fi

		diff -u "${generated_file}" "${runtime_file}" >/dev/null

		if [[ ! -L "${runtime_file}" ]]; then
			log_warn "Runtime file is not a symlink: ${runtime_file}"
			runtime_warning=1
		fi
	done

	if [[ "${runtime_warning}" -eq 0 ]]; then
		log_success "Mango runtime compatibility files are symlinked and in sync!"
	else
		log_success "Mango runtime compatibility files match generated outputs."
	fi
else
	log_warn "Mango runtime directory not found yet. Skipping runtime compatibility check."
fi

log_info "Checking Mango bind semantics..."
python3 - "${MODULE_DIR}/dotfiles/mango/conf.d/50-binds.conf" <<'PY'
import sys
from pathlib import Path

binds_file = Path(sys.argv[1])
seen = {}
duplicates = []
declared_modes = {"default"}
keymode_targets = []
current_mode = "default"

for lineno, raw_line in enumerate(binds_file.read_text().splitlines(), start=1):
    line = raw_line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    if line.startswith("keymode="):
        current_mode = line.split("=", 1)[1].strip().lower() or "default"
        declared_modes.add(current_mode)
        continue
    kind, payload = line.split("=", 1)
    if kind not in {"bind", "binds"}:
        continue
    parts = [part.strip() for part in payload.split(",")]
    if len(parts) < 3:
        continue
    key = (current_mode.upper(), parts[0].upper(), parts[1].upper())
    if key in seen:
        duplicates.append((key, seen[key], lineno))
    else:
        seen[key] = lineno
    if parts[2] == "setkeymode" and len(parts) >= 4:
        keymode_targets.append((parts[3].strip().lower(), lineno))

if duplicates:
    for (mode, mods, key), first, second in duplicates:
        print(
            f"Duplicate Mango bind for mode={mode} {mods},{key} at lines {first} and {second}",
            file=sys.stderr,
        )
    raise SystemExit(1)

unknown_targets = [
    (target, lineno)
    for target, lineno in keymode_targets
    if target and target not in declared_modes and target not in {"default", "common"}
]
if unknown_targets:
    for target, lineno in unknown_targets:
        print(f"Unknown Mango keymode target {target!r} at line {lineno}", file=sys.stderr)
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
tmp_generated="${tmp_mango_dir}/generated"
mkdir -p "${tmp_runtime}" "${tmp_generated}"
ln -s "${MODULE_DIR}/dotfiles/mango/conf.d" "${tmp_mango_dir}/conf.d"
ln -s "${CONFIG_FILE}" "${tmp_mango_dir}/config.conf"
ln -s "${MODULE_DIR}/dotfiles/mango/generated/theme.conf" "${tmp_generated}/theme.conf"
ln -s "${tmp_runtime}" "${tmp_mango_dir}/runtime"

"${RENDER_PROFILE_SCRIPT}" --out-dir "${tmp_generated}" >/dev/null
"${RENDER_WORKSPACE_ASSETS_SCRIPT}" --out-dir "${tmp_generated}" >/dev/null
"${RENDER_WINDOW_RULES_SCRIPT}" --out-dir "${tmp_generated}" >/dev/null
"${RENDER_KEYBIND_CHEATSHEET_SCRIPT}" --out-dir "${tmp_generated}" >/dev/null

ln -s "${tmp_generated}/profile.conf" "${tmp_runtime}/profile.conf"
ln -s "${tmp_generated}/workspace-binds.conf" "${tmp_runtime}/workspace-binds.conf"
ln -s "${tmp_generated}/workspace-rules.conf" "${tmp_runtime}/workspace-rules.conf"
ln -s "${tmp_generated}/window-rules.conf" "${tmp_runtime}/window-rules.conf"
ln -s "${tmp_generated}/keybind-cheatsheet.conf" "${tmp_runtime}/keybind-cheatsheet.conf"

log_info "Validating Mango tagrule contract..."
python3 - "${WORKSPACE_SOURCE_FILE}" "${SHARED_MONITOR_MANIFEST}" "${MANGO_MONITOR_PROFILE}" "${tmp_runtime}/profile.conf" <<'PY'
import json
import sys
from pathlib import Path

import yaml

workspace_file = Path(sys.argv[1])
monitor_file = Path(sys.argv[2])
profile_name = sys.argv[3]
profile_file = Path(sys.argv[4])

workspace_data = json.loads(workspace_file.read_text())
monitor_data = yaml.safe_load(monitor_file.read_text())

workspaces = {
    str(workspace["id"]): workspace for workspace in workspace_data.get("workspaces", [])
}
monitors = {
    monitor["id"]: monitor for monitor in monitor_data.get("monitors", [])
}
if profile_name == "auto":
    active_profile = ""
    for raw_line in profile_file.read_text().splitlines():
        if raw_line.startswith("# Active monitor profile: "):
            active_profile = raw_line.split(": ", 1)[1].strip()
            break
    profile_name = active_profile or "desk"

profile = monitor_data.get("profiles", {}).get(profile_name)
if profile is None:
    raise SystemExit(f"Unknown MANGO_MONITOR_PROFILE: {profile_name}")


def normalize_binary(value):
    if isinstance(value, bool):
        return str(int(value))
    return str(value)


def monitor_name_for_mango(monitor):
    return monitor.get("mango_name", monitor.get("wayland_name", monitor["id"]))


expected = {}
for workspace_ref in sorted(profile.get("workspaces", []), key=lambda item: int(item["id"])):
    workspace_id = str(workspace_ref["id"])
    workspace = workspaces[workspace_id]
    monitor = monitors[workspace_ref["monitor"]]
    layout = workspace.get("layout", {})
    mango = layout.get("mango", {}) if isinstance(layout, dict) else {}
    expected_fields = {
        "id": workspace_id,
        "monitor_name": monitor_name_for_mango(monitor),
        "no_hide": normalize_binary(mango.get("noHide", 1)),
        "layout_name": mango.get("layoutName", "scroller"),
    }
    if "openAsFloating" in mango:
        expected_fields["open_as_floating"] = normalize_binary(mango["openAsFloating"])
    if "noRenderBorder" in mango:
        expected_fields["no_render_border"] = normalize_binary(mango["noRenderBorder"])
    if "nmaster" in mango:
        expected_fields["nmaster"] = str(mango["nmaster"])
    if "mfact" in mango:
        expected_fields["mfact"] = f"{float(mango['mfact']):.2f}".rstrip("0").rstrip(".")
    expected[workspace_id] = expected_fields

actual = {}
for raw_line in profile_file.read_text().splitlines():
    line = raw_line.strip()
    if not line.startswith("tagrule="):
        continue
    fields = {}
    for token in line[len("tagrule="):].split(","):
        if ":" not in token:
            continue
        key, value = token.split(":", 1)
        fields[key.strip()] = value.strip()
    workspace_id = fields.get("id")
    if workspace_id:
        actual[workspace_id] = fields

errors = []
for workspace_id, expected_fields in expected.items():
    actual_fields = actual.get(workspace_id)
    if actual_fields is None:
        errors.append(f"workspace {workspace_id} is missing from rendered profile.conf")
        continue
    for key, value in expected_fields.items():
        if actual_fields.get(key) != value:
            errors.append(
                f"workspace {workspace_id} rendered tagrule mismatch for {key}: "
                f"expected {value!r}, got {actual_fields.get(key)!r}"
            )

if errors:
    for error in errors:
        print(error, file=sys.stderr)
    raise SystemExit(1)
PY
log_success "Rendered Mango tagrule contract matches workspace manifest!"

log_info "Validating Mango config parse against temporary runtime..."
mango -c "${tmp_mango_dir}/config.conf" -p >/dev/null
log_success "Mango config parses successfully with rendered runtime files!"

helper_failure=0
helper_candidates=(
	"${MODULE_DIR}/scripts/install.sh"
	"${MODULE_DIR}/scripts/ensure-runtime-files.sh"
	"${MODULE_DIR}/scripts/render-packages.sh"
	"${MODULE_DIR}/scripts/render-theme.sh"
	"${MODULE_DIR}/scripts/render-profile.sh"
	"${MODULE_DIR}/scripts/render-workspace-assets.sh"
	"${MODULE_DIR}/scripts/render-window-rules.sh"
	"${MODULE_DIR}/scripts/render-keybind-cheatsheet.sh"
	"${MODULE_DIR}/scripts/validate.sh"
	"${REPO_ROOT}/modules/scripts/bin/mango-arrange.sh"
	"${REPO_ROOT}/modules/scripts/bin/mango-monitor-smart.sh"
	"${REPO_ROOT}/modules/scripts/bin/mango-overview.sh"
	"${REPO_ROOT}/modules/scripts/bin/mango-layer-audit.sh"
	"${REPO_ROOT}/modules/scripts/bin/mango-virtual-output.sh"
	"${REPO_ROOT}/modules/scripts/bin/mango-profile-select.sh"
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
	"${REPO_ROOT}/modules/scripts/bin/mango-blueman-applet.sh"
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

if [[ "${mode}" == "live" ]]; then
	log_info "Validating live MangoWM IPC/session state..."

	command -v mmsg >/dev/null 2>&1 || die "mmsg is required for --live"
	[[ -n "${WAYLAND_DISPLAY:-}" ]] || die "--live requires WAYLAND_DISPLAY"

	live_outputs="$(mmsg -O 2>/dev/null || true)"
	[[ -n "${live_outputs}" ]] || die "mmsg -O returned no outputs"

	while IFS= read -r expected_output; do
		[[ -n "${expected_output}" ]] || continue
		if ! grep -Fxq "${expected_output}" <<<"${live_outputs}"; then
			die "Configured Mango output is not live: ${expected_output}"
		fi
	done < <(
		awk -F',' '
			/^monitorrule=/ {
				for (i = 1; i <= NF; i++) {
					if ($i ~ /^monitorrule=name:\^/) {
						name = $i
						sub(/^monitorrule=name:\^/, "", name)
						sub(/\$$/, "", name)
						gsub(/\\-/, "-", name)
						print name
					}
				}
			}
		' "${MANGO_GENERATED_DIR}/profile.conf"
	)

	keymode_state="$(mmsg -g -b 2>/dev/null || true)"
	[[ -n "${keymode_state}" ]] || die "mmsg -g -b returned no keymode state"

	tag_state="$(mmsg -g -t 2>/dev/null || true)"
	[[ -n "${tag_state}" ]] || die "mmsg -g -t returned no tag state"

	if command -v systemctl >/dev/null 2>&1; then
		if failed_units="$(systemctl --user --failed --plain --no-legend 2>/dev/null || true)" &&
			grep -Eq '(^|[[:space:]])mango|(^|[[:space:]])mangowm' <<<"${failed_units}"; then
			printf '%s\n' "${failed_units}" >&2
			die "Failed Mango user units are present"
		fi
	fi

	portal_file="${XDG_CONFIG_HOME:-${USER_HOME}/.config}/xdg-desktop-portal/mango-portals.conf"
	[[ -r "${portal_file}" ]] || log_warn "Mango portal preference file not found: ${portal_file}"

	log_success "Live MangoWM IPC/session state looks healthy!"
fi
