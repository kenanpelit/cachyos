#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
source "$repo_root/modules/base/lib/core.sh"

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

--fast   Validate Niri-owned scripts plus the small set of shared helpers that
         the Niri session directly executes. This is the default.
--strict Validate the same set plus every shell helper under modules/scripts/bin.
EOF
    exit 0
    ;;
  *)
    echo "Unknown argument: ${1}" >&2
    exit 2
    ;;
esac

NIRI_CONFIG="$USER_HOME/.config/niri/config.kdl"
NIRI_RUNTIME_DIR="$USER_HOME/.config/niri/runtime"
REPO_NIRI_CONFIG="$script_dir/../dotfiles/niri/config.kdl"
WORKSPACE_SOURCE_FILE="$repo_root/shared/wm/workspaces.json"
WORKSPACE_RULES_FILE="$script_dir/../dotfiles/niri/generated/workspace-rules.kdl"
RENDER_PROFILE_SCRIPT="$script_dir/render-profile.sh"
RENDER_WORKSPACE_ASSETS_SCRIPT="$script_dir/render-workspace-assets.sh"
RENDER_THEME_SCRIPT="$script_dir/render-theme.sh"
RENDER_BACKGROUND_EFFECTS_SCRIPT="$script_dir/render-background-effects.sh"
RENDER_KEYBIND_CHEATSHEET_SCRIPT="$script_dir/render-keybind-cheatsheet.sh"
SHARED_MONITOR_ASSETS_SCRIPT="$repo_root/shared/wm/render-monitor-assets.sh"
THEME_FILE="$script_dir/../dotfiles/niri/generated/theme.kdl"
BACKGROUND_EFFECTS_FILE="$script_dir/../dotfiles/niri/conf/41-background-effects.kdl"
BACKGROUND_POLICY_FILE="$script_dir/../effects/background-policy.json"
LAYOUT_RECIPES_FILE="$script_dir/../layouts/recipes.json"
PACKAGES_FILE="$script_dir/../packages.yaml"
MODULE_FILE="$script_dir/../module.yaml"
KEYBIND_CHEATSHEET_FILE="$script_dir/../dotfiles/niri/generated/keybind-cheatsheet.conf"

log_info "Validating Niri configuration..."

niri_available=0
if command -v niri >/dev/null 2>&1; then
    niri_available=1
    niri_version_raw="$(niri --version 2>/dev/null | awk '{print $2}' || true)"
    if [[ "$niri_version_raw" =~ ^([0-9]+)\.([0-9]+) ]]; then
        niri_version_major="${BASH_REMATCH[1]}"
        niri_version_minor="${BASH_REMATCH[2]}"
        if (( 10#$niri_version_major < 26 || (10#$niri_version_major == 26 && 10#$niri_version_minor < 4) )); then
            log_error "Niri ${niri_version_raw} is too old for this module; 26.04+ is required."
            exit 1
        fi
    else
        log_warn "Could not parse Niri version '${niri_version_raw:-unknown}'; continuing validation."
    fi
else
    log_warn "Niri binary not found in PATH. Syntax validation will be skipped."
fi

if [[ -x "$SHARED_MONITOR_ASSETS_SCRIPT" ]]; then
    log_info "Validating shared monitor assets..."
    if "$SHARED_MONITOR_ASSETS_SCRIPT" --check >/dev/null 2>&1; then
        log_success "Shared monitor assets match generated outputs!"
    else
        log_error "Shared monitor asset drift detected!"
        "$SHARED_MONITOR_ASSETS_SCRIPT" --check
        exit 1
    fi
fi

if command -v jq >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    log_info "Validating shared workspace manifest semantics for Niri..."
    jq empty "$WORKSPACE_SOURCE_FILE" >/dev/null
    python3 - "$WORKSPACE_SOURCE_FILE" "$LAYOUT_RECIPES_FILE" <<'PY'
import json
import re
import sys
from pathlib import Path

workspace_file = Path(sys.argv[1])
recipes_file = Path(sys.argv[2])
data = json.loads(workspace_file.read_text())
recipe_data = json.loads(recipes_file.read_text())
recipes = recipe_data.get("recipes", {})

workspaces = data.get("workspaces")
if not isinstance(workspaces, list) or not workspaces:
    raise SystemExit("shared/wm/workspaces.json must contain a non-empty workspaces array")
if not isinstance(recipes, dict) or not recipes:
    raise SystemExit("modules/niri/layouts/recipes.json must contain recipes")

errors = []
seen_ids = set()
seen_names = set()


def require_string(value, label):
    if not isinstance(value, str) or not value.strip():
        errors.append(f"{label} must be a non-empty string")
        return ""
    return value


def compile_regex(value, label):
    if not value:
        return
    if not isinstance(value, str):
        errors.append(f"{label} must be a string regex")
        return
    try:
        re.compile(value)
    except re.error as exc:
        errors.append(f"{label} is not a valid regex: {exc}")


def normalize_recipe_names(layout, workspace_id):
    raw = layout.get("niriRecipes") if "niriRecipes" in layout else layout.get("niriRecipe", layout.get("recipe", []))
    if raw in (None, ""):
        return []
    if isinstance(raw, str):
        return [raw]
    if isinstance(raw, list) and all(isinstance(item, str) and item for item in raw):
        return raw
    errors.append(f"workspace {workspace_id} layout.niriRecipe/niriRecipes must be a string or string array")
    return []


for recipe_name, recipe in recipes.items():
    if not isinstance(recipe, dict):
        errors.append(f"Niri layout recipe {recipe_name} must be an object")
        continue
    lines = recipe.get("lines", [])
    if not isinstance(lines, list) or not lines or not all(isinstance(line, str) and line.strip() for line in lines):
        errors.append(f"Niri layout recipe {recipe_name} must contain non-empty string lines")

for index, workspace in enumerate(workspaces, start=1):
    if not isinstance(workspace, dict):
        errors.append(f"workspace[{index}] must be an object")
        continue

    workspace_id = require_string(str(workspace.get("id", "")), f"workspace[{index}].id")
    workspace_name = require_string(workspace.get("name"), f"workspace {workspace_id}.name")

    if workspace_id:
        if workspace_id in seen_ids:
            errors.append(f"duplicate workspace id {workspace_id}")
        seen_ids.add(workspace_id)
        if not workspace_id.isdigit():
            errors.append(f"workspace {workspace_id}.id must be numeric text for keybind generation")
    if workspace_name:
        if workspace_name in seen_names:
            errors.append(f"duplicate workspace name {workspace_name}")
        seen_names.add(workspace_name)

    here = workspace.get("here", {})
    if not isinstance(here, dict):
        errors.append(f"workspace {workspace_id}.here must be an object")
        here = {}
    require_string(here.get("label") or workspace.get("hereLabel"), f"workspace {workspace_id}.here.label")
    require_string(here.get("target") or workspace.get("hereTarget"), f"workspace {workspace_id}.here.target")

    launch = workspace.get("launch", {})
    if launch and not isinstance(launch, dict):
        errors.append(f"workspace {workspace_id}.launch must be an object")
    elif launch:
        commands = launch.get("commands", [])
        if commands and (not isinstance(commands, list) or not all(isinstance(item, str) and item for item in commands)):
            errors.append(f"workspace {workspace_id}.launch.commands must be an array of strings")
        if "includeInAll" in launch and not isinstance(launch["includeInAll"], bool):
            errors.append(f"workspace {workspace_id}.launch.includeInAll must be boolean")

    focus = workspace.get("focus", {})
    if focus and not isinstance(focus, dict):
        errors.append(f"workspace {workspace_id}.focus must be an object")
    elif focus:
        compile_regex(focus.get("regex") or workspace.get("focusRegex"), f"workspace {workspace_id}.focus.regex")

    routes = workspace.get("routes")
    if routes is None:
        legacy_app = workspace.get("routeAppRegex", "")
        legacy_title = workspace.get("routeTitleRegex", "")
        routes = [{"appIdRegex": legacy_app, "titleRegex": legacy_title}] if legacy_app or legacy_title else []
    if not isinstance(routes, list):
        errors.append(f"workspace {workspace_id}.routes must be an array")
        routes = []
    for route_index, route in enumerate(routes, start=1):
        if not isinstance(route, dict):
            errors.append(f"workspace {workspace_id}.routes[{route_index}] must be an object")
            continue
        app_regex = route.get("appIdRegex", "")
        title_regex = route.get("titleRegex", "")
        if not app_regex and not title_regex:
            errors.append(f"workspace {workspace_id}.routes[{route_index}] must set appIdRegex or titleRegex")
        compile_regex(app_regex, f"workspace {workspace_id}.routes[{route_index}].appIdRegex")
        compile_regex(title_regex, f"workspace {workspace_id}.routes[{route_index}].titleRegex")

    layout = workspace.get("layout")
    if layout is None:
        continue
    if isinstance(layout, list):
        if not all(isinstance(line, str) and line.strip() for line in layout):
            errors.append(f"workspace {workspace_id}.layout list must only contain non-empty strings")
        continue
    if not isinstance(layout, dict):
        errors.append(f"workspace {workspace_id}.layout must be an object or list")
        continue
    lines = layout.get("lines", [])
    if lines is None:
        lines = []
    if not isinstance(lines, list) or not all(isinstance(line, str) and line.strip() for line in lines):
        errors.append(f"workspace {workspace_id}.layout.lines must be an array of non-empty strings")
    for recipe_name in normalize_recipe_names(layout, workspace_id):
        if recipe_name not in recipes:
            errors.append(f"workspace {workspace_id} references unknown Niri layout recipe {recipe_name!r}")

if errors:
    for error in errors:
        print(error, file=sys.stderr)
    raise SystemExit(1)
PY
    log_success "Shared workspace manifest semantics are valid for Niri!"
else
    log_warn "jq/python3 missing; skipping shared workspace semantic checks."
fi

if [[ -x "$RENDER_THEME_SCRIPT" ]]; then
    log_info "Validating generated Niri theme..."
    if "$RENDER_THEME_SCRIPT" --check >/dev/null 2>&1; then
        log_success "Generated Niri theme matches theme manifest!"
    else
        log_error "Generated Niri theme drift detected!"
        "$RENDER_THEME_SCRIPT" --check
        exit 1
    fi
fi

if [[ -x "$RENDER_BACKGROUND_EFFECTS_SCRIPT" ]]; then
    log_info "Validating generated Niri background effect policy..."
    if "$RENDER_BACKGROUND_EFFECTS_SCRIPT" --check >/dev/null 2>&1; then
        log_success "Generated Niri background effects match policy manifest!"
    else
        log_error "Generated Niri background effect drift detected!"
        "$RENDER_BACKGROUND_EFFECTS_SCRIPT" --check
        exit 1
    fi
fi

if command -v python3 >/dev/null 2>&1; then
    log_info "Validating Niri overview readability and blur guardrails..."
    python3 - "$THEME_FILE" "$BACKGROUND_EFFECTS_FILE" "$BACKGROUND_POLICY_FILE" <<'PY'
import json
import re
import sys
from pathlib import Path

theme_file = Path(sys.argv[1])
effects_file = Path(sys.argv[2])
policy_file = Path(sys.argv[3])
theme = theme_file.read_text()
effects = effects_file.read_text()
policy = json.loads(policy_file.read_text())

zoom_match = re.search(r"(?m)^\s*zoom\s+([0-9.]+)\s*$", theme)
if not zoom_match:
    raise SystemExit("generated/theme.kdl must define overview zoom")

zoom = float(zoom_match.group(1))
if not 0.30 <= zoom <= 0.75:
    raise SystemExit(
        f"NIRI_OVERVIEW_ZOOM must stay readable for touchpad overview gestures; got {zoom}"
    )

guarded_surfaces = ("niri-overview-launcher", "launcher-overlay", "noctalia-osd", "region-selector")
for surface in guarded_surfaces:
    if surface not in effects:
        raise SystemExit(f"41-background-effects.kdl must explicitly guard {surface}")

for namespace in policy.get("blurNamespaces", []):
    for forbidden in ("overview", "launcher-overlay", "osd", "region", "record", "measure", "annotate"):
        if forbidden in namespace:
            raise SystemExit(f"blur policy must not allow blur for {forbidden}: {namespace}")

overview_mentions = []
for surface in guarded_surfaces:
    overview_mentions.extend(match.start() for match in re.finditer(surface, effects))

for pos in overview_mentions:
    block_start = effects.rfind("layer-rule", 0, pos)
    block_end = effects.find("layer-rule", pos + 1)
    block = effects[block_start:block_end if block_end != -1 else len(effects)]
    if "blur true" in block:
        raise SystemExit("overview/launcher surfaces must not be in a blur true layer-rule")
    if "blur false" not in block:
        raise SystemExit("overview/launcher surfaces must force blur false")
PY
    log_success "Niri overview readability and blur guardrails are valid!"
fi

if [[ -x "$RENDER_WORKSPACE_ASSETS_SCRIPT" ]]; then
    log_info "Validating generated workspace assets..."
    if [ "$(id -u)" -eq 0 ]; then
        if run_as_user "$RENDER_WORKSPACE_ASSETS_SCRIPT" --check --runtime-dir "$NIRI_RUNTIME_DIR" >/dev/null 2>&1; then
            log_success "Generated workspace assets match repo/runtime files!"
        else
            log_error "Generated workspace assets drift detected!"
            run_as_user "$RENDER_WORKSPACE_ASSETS_SCRIPT" --check --runtime-dir "$NIRI_RUNTIME_DIR"
            exit 1
        fi
    else
        if "$RENDER_WORKSPACE_ASSETS_SCRIPT" --check --runtime-dir "$NIRI_RUNTIME_DIR" >/dev/null 2>&1; then
            log_success "Generated workspace assets match repo/runtime files!"
        else
            log_error "Generated workspace assets drift detected!"
            "$RENDER_WORKSPACE_ASSETS_SCRIPT" --check --runtime-dir "$NIRI_RUNTIME_DIR"
            exit 1
        fi
    fi
fi

if [[ -x "$RENDER_KEYBIND_CHEATSHEET_SCRIPT" ]]; then
    log_info "Validating generated Niri keybind cheatsheet..."
    if "$RENDER_KEYBIND_CHEATSHEET_SCRIPT" --check >/dev/null 2>&1; then
        if [[ -d "$NIRI_RUNTIME_DIR" && -e "$NIRI_RUNTIME_DIR/keybind-cheatsheet.conf" ]]; then
            diff -u "$KEYBIND_CHEATSHEET_FILE" "$NIRI_RUNTIME_DIR/keybind-cheatsheet.conf" >/dev/null
        fi
        log_success "Generated Niri keybind cheatsheet is in sync!"
    else
        log_error "Generated Niri keybind cheatsheet drift detected!"
        "$RENDER_KEYBIND_CHEATSHEET_SCRIPT" --check
        exit 1
    fi
fi

if command -v python3 >/dev/null 2>&1; then
    log_info "Validating Niri package/session contract..."
    python3 - "$PACKAGES_FILE" "$MODULE_FILE" <<'PY'
import sys
from pathlib import Path

packages_file = Path(sys.argv[1])
module_file = Path(sys.argv[2])
packages_text = packages_file.read_text()
module_text = module_file.read_text()

required_packages = {
    "niri-git": "Niri compositor package",
    "jq": "IPC/helper JSON parsing",
    "xwayland-satellite": "Niri Xwayland support",
}
errors = []
for package, reason in required_packages.items():
    needle = f"- {package}"
    if needle not in packages_text:
        errors.append(f"packages.yaml must include {package} ({reason})")

required_dependencies = {"xdg-portal", "scripts", "wayland-env", "user-services"}
for dependency in required_dependencies:
    if f"- {dependency}" not in module_text:
        errors.append(f"module.yaml must depend on {dependency}")

if errors:
    for error in errors:
        print(error, file=sys.stderr)
    raise SystemExit(1)
PY
    log_success "Niri package/session contract is valid!"
fi

if [[ -r "$WORKSPACE_SOURCE_FILE" && -r "$WORKSPACE_RULES_FILE" ]] && command -v jq >/dev/null 2>&1; then
    log_info "Validating title-aware native workspace rules..."
    semantic_failure=0
    while IFS=$'\t' read -r workspace_name app_regex title_regex; do
        [[ -n "${title_regex//[[:space:]]/}" ]] || continue

        expected_match="  match"
        if [[ -n "${app_regex//[[:space:]]/}" ]]; then
            expected_match+=" app-id=r#\"${app_regex}\"#"
        fi
        expected_match+=" title=r#\"${title_regex}\"#"

        if ! grep -Fqx "$expected_match" "$WORKSPACE_RULES_FILE"; then
            log_error "Missing native title-aware rule for workspace '${workspace_name}'"
            semantic_failure=1
        fi
    done < <(
        jq -r '
          def normalized_routes($ws):
            if ($ws.routes // null) != null then
              $ws.routes
            elif (($ws.routeAppRegex // "") != "" or ($ws.routeTitleRegex // "") != "") then
              [{
                appIdRegex: ($ws.routeAppRegex // ""),
                titleRegex: ($ws.routeTitleRegex // "")
              }]
            else
              []
            end;

          .workspaces[] as $ws
          | normalized_routes($ws)[]
          | select((.titleRegex // "") != "")
          | [$ws.name, (.appIdRegex // ""), (.titleRegex // "")] | @tsv
        ' "$WORKSPACE_SOURCE_FILE"
    )

    if [[ "$semantic_failure" -ne 0 ]]; then
        exit 1
    fi

    log_success "Title-aware native workspace rules are in sync!"
fi

if command -v python3 >/dev/null 2>&1; then
    log_info "Checking Niri bind semantics..."
    python3 - "$REPO_NIRI_CONFIG" <<'PY'
import re
import sys
from pathlib import Path

root_config = Path(sys.argv[1]).resolve()
parsed_files = set()
seen = {}
duplicates = []


def resolve_include(base: Path, raw_path: str) -> Path:
    if raw_path.startswith("~/"):
        raw_path = str(Path.home()) + raw_path[1:]
    path = Path(raw_path)
    if path.is_absolute():
        return path
    return (base.parent / path).resolve()


def collect_file(path: Path):
    if path in parsed_files or not path.exists() or not path.is_file():
        return []
    parsed_files.add(path)
    text = path.read_text(errors="replace")
    files = [(path, text)]
    for match in re.finditer(r'^\s*include(?:\s+optional=true)?\s+"([^"]+)"', text, re.MULTILINE):
        files.extend(collect_file(resolve_include(path, match.group(1))))
    return files


def scan_binds(path: Path, text: str):
    in_binds = False
    depth = 0
    pending = None

    for lineno, raw_line in enumerate(text.splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("//"):
            continue
        if not in_binds:
            if re.match(r"^binds\s*\{", line):
                in_binds = True
                depth = line.count("{") - line.count("}")
            continue

        match = re.match(r"^([A-Za-z0-9_+]+)\s", line)
        if match and "{" in line and pending is None:
            key = match.group(1).upper()
            if key in seen:
                duplicates.append((key, seen[key], f"{path}:{lineno}"))
            else:
                seen[key] = f"{path}:{lineno}"
            local_depth = 1 + line.split("{", 1)[1].count("{") - line.split("{", 1)[1].count("}")
            if local_depth > 0:
                pending = key

        if pending is not None:
            local_delta = line.count("{") - line.count("}")
            if local_delta < 0:
                pending = None

        depth += line.count("{") - line.count("}")
        if depth <= 0:
            in_binds = False
            pending = None


for path, text in collect_file(root_config):
    scan_binds(path, text)

if duplicates:
    for key, first, second in duplicates:
        print(f"Duplicate Niri bind {key} at {first} and {second}", file=sys.stderr)
    raise SystemExit(1)
PY
    log_success "No duplicate Niri binds detected!"
fi

if [[ "$niri_available" -eq 1 ]]; then
    tmp_root="$(mktemp -d)"
    cleanup_tmp_niri() {
        rm -rf "$tmp_root"
    }
    trap cleanup_tmp_niri EXIT

    tmp_niri_dir="$tmp_root/niri"
    tmp_runtime_dir="$tmp_niri_dir/runtime"
    mkdir -p "$tmp_niri_dir" "$tmp_runtime_dir"
    cp "$REPO_NIRI_CONFIG" "$tmp_niri_dir/config.kdl"
    ln -s "$script_dir/../dotfiles/niri/outputs.kdl" "$tmp_niri_dir/outputs.kdl"
    ln -s "$script_dir/../dotfiles/niri/conf" "$tmp_niri_dir/conf"
    ln -s "$script_dir/../dotfiles/niri/generated" "$tmp_niri_dir/generated"
    touch "$tmp_runtime_dir/debug.kdl"

    if [[ -x "$RENDER_PROFILE_SCRIPT" ]]; then
        "$RENDER_PROFILE_SCRIPT" --out-dir "$tmp_runtime_dir" >/dev/null
    fi
    if [[ -x "$RENDER_WORKSPACE_ASSETS_SCRIPT" ]]; then
        "$RENDER_WORKSPACE_ASSETS_SCRIPT" --runtime-dir "$tmp_runtime_dir" >/dev/null
    fi

    log_info "Validating Niri config parse against temporary runtime..."
    if niri validate -c "$tmp_niri_dir/config.kdl" >/dev/null 2>&1; then
        log_success "Niri config parses successfully with rendered temporary runtime!"
    else
        log_error "Niri temporary runtime config validation failed!"
        niri validate -c "$tmp_niri_dir/config.kdl"
        exit 1
    fi

    if [[ -f "$NIRI_CONFIG" ]]; then
        if niri validate -c "$NIRI_CONFIG" >/dev/null 2>&1; then
            log_success "Live Niri config is valid!"
        else
            log_error "Live Niri config validation failed!"
            niri validate -c "$NIRI_CONFIG"
            exit 1
        fi
    else
        log_warn "Live Niri config file not found yet. Skipping live syntax validation."
    fi
else
    log_warn "Skipping Niri syntax validation because niri is not in PATH."
fi

if [[ -x "$RENDER_PROFILE_SCRIPT" ]] && [[ -d "$NIRI_RUNTIME_DIR" ]]; then
    log_info "Validating rendered Niri workspace profile..."
    if [ "$(id -u)" -eq 0 ]; then
        if run_as_user "$RENDER_PROFILE_SCRIPT" --check --out-dir "$NIRI_RUNTIME_DIR" >/dev/null 2>&1; then
            log_success "Rendered Niri profile matches runtime files!"
        else
            log_error "Rendered Niri profile drift detected!"
            run_as_user "$RENDER_PROFILE_SCRIPT" --check --out-dir "$NIRI_RUNTIME_DIR"
            exit 1
        fi
    else
        if "$RENDER_PROFILE_SCRIPT" --check --out-dir "$NIRI_RUNTIME_DIR" >/dev/null 2>&1; then
            log_success "Rendered Niri profile matches runtime files!"
        else
            log_error "Rendered Niri profile drift detected!"
            "$RENDER_PROFILE_SCRIPT" --check --out-dir "$NIRI_RUNTIME_DIR"
            exit 1
        fi
    fi
fi

log_info "Validating Niri helper shell syntax..."
helper_failure=0
helper_candidates=()

while IFS= read -r helper_script; do
    [[ -n "$helper_script" ]] || continue
    helper_candidates+=("$helper_script")
done < <(
    find \
        "$repo_root/modules/niri/scripts" \
        "$repo_root/shared/wm" \
        -maxdepth 1 -type f -name '*.sh' | sort
)

for helper_script in \
    "$repo_root/modules/scripts/bin/niri-arrange.sh" \
    "$repo_root/modules/scripts/bin/niri-bootstrap.sh" \
    "$repo_root/modules/scripts/bin/niri-desktop-settings.sh" \
    "$repo_root/modules/scripts/bin/niri-float-sticky.sh" \
    "$repo_root/modules/scripts/bin/niri-osc.sh" \
    "$repo_root/modules/scripts/bin/niri-post-bootstrap.sh" \
    "$repo_root/modules/scripts/bin/niri-session-common.sh" \
    "$repo_root/modules/scripts/bin/niri-session-init.sh" \
    "$repo_root/modules/scripts/bin/niri-status-notifier-ready.sh" \
    "$repo_root/modules/scripts/bin/niri-two-column-layout.sh" \
    "$repo_root/modules/scripts/bin/niri-workspace-smart.sh" \
    "$repo_root/modules/scripts/bin/osc-niri-workspaces-mode.sh" \
    "$repo_root/modules/scripts/bin/osc-shell.sh" \
    "$repo_root/modules/scripts/bin/osc-tty-launcher.sh" \
    "$repo_root/modules/scripts/bin/osc-workspace-launch.sh"
do
    [[ -f "$helper_script" ]] || continue
    helper_candidates+=("$helper_script")
done

if [[ "$mode" == "strict" ]]; then
    while IFS= read -r helper_script; do
        [[ -n "$helper_script" ]] || continue
        helper_candidates+=("$helper_script")
    done < <(
        find "$repo_root/modules/scripts/bin" -maxdepth 1 -type f -name '*.sh' | sort
    )
fi

while IFS= read -r helper_script; do
    [[ -n "$helper_script" ]] || continue
    if ! bash -n "$helper_script"; then
        log_error "Shell syntax check failed: $helper_script"
        helper_failure=1
    fi
done < <(printf '%s\n' "${helper_candidates[@]}" | sort -u)

if [[ "$helper_failure" -ne 0 ]]; then
    exit 1
fi

log_success "Niri helper shell syntax is valid!"
