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
WORKSPACE_SOURCE_FILE="$repo_root/shared/wm/workspaces.json"
WORKSPACE_RULES_FILE="$script_dir/../dotfiles/niri/generated/workspace-rules.kdl"
RENDER_PROFILE_SCRIPT="$script_dir/render-profile.sh"
RENDER_WORKSPACE_ASSETS_SCRIPT="$script_dir/render-workspace-assets.sh"
RENDER_THEME_SCRIPT="$script_dir/render-theme.sh"
SHARED_MONITOR_ASSETS_SCRIPT="$repo_root/shared/wm/render-monitor-assets.sh"

log_info "Validating Niri configuration..."

if [[ ! -f "$NIRI_CONFIG" ]]; then
    log_warn "Niri config file not found yet. Skipping validation."
    exit 0
fi

if ! command -v niri >/dev/null 2>&1; then
    log_warn "Niri binary not found in PATH. Cannot validate syntax."
    exit 0
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

if niri validate -c "$NIRI_CONFIG" >/dev/null 2>&1; then
    log_success "Niri config is valid!"
else
    log_error "Niri config validation failed!"
    niri validate -c "$NIRI_CONFIG" # Show the error output
    exit 1
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
    "$repo_root/modules/scripts/bin/niri-osc.sh" \
    "$repo_root/modules/scripts/bin/niri-post-bootstrap.sh" \
    "$repo_root/modules/scripts/bin/niri-session-common.sh" \
    "$repo_root/modules/scripts/bin/niri-session-init.sh" \
    "$repo_root/modules/scripts/bin/niri-status-notifier-ready.sh" \
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
