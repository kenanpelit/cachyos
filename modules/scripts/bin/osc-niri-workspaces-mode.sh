#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
TARGET_RUNTIME_DIR="${NIRI_RUNTIME_DIR:-${XDG_CONFIG_HOME}/niri/runtime}"
TARGET_FILE="${TARGET_RUNTIME_DIR}/workspaces-auto.kdl"
CONFIG_FILE_DEFAULT="${NIRI_CONFIG_FILE:-${XDG_CONFIG_HOME}/niri/config.kdl}"
RUNTIME_RULES_FILE="${TARGET_RUNTIME_DIR}/workspace-rules.tsv"
RUNTIME_HERE_FILE="${TARGET_RUNTIME_DIR}/workspace-here.tsv"

BEGIN_SHORTCUTS='// BEGIN OSC_NIRI_WORKSPACE_SHORTCUTS'
END_SHORTCUTS='// END OSC_NIRI_WORKSPACE_SHORTCUTS'
BEGIN_RULES='// BEGIN OSC_NIRI_WORKSPACE_RULES'
END_RULES='// END OSC_NIRI_WORKSPACE_RULES'

find_repo_root() {
  local candidates=()
  local here=""

  if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    candidates+=("$(cd -- "${here}/../.." && pwd)")
  fi

  candidates+=(
    "$HOME/.cachy"
    "$HOME/.config/arch-config"
  )

  local candidate=""
  for candidate in "${candidates[@]}"; do
    [[ -f "${candidate}/modules/niri/scripts/render-profile.sh" ]] || continue
    printf '%s\n' "$candidate"
    return 0
  done

  return 1
}

resolve_config_file() {
  readlink -f "${CONFIG_FILE_DEFAULT}" 2>/dev/null || printf '%s\n' "${CONFIG_FILE_DEFAULT}"
}

generated_shortcuts_file() {
  local repo_root
  repo_root="$(find_repo_root)" || return 1
  printf '%s\n' "${repo_root}/modules/niri/dotfiles/niri/generated/workspace-shortcuts.kdl"
}

generated_rules_file() {
  local repo_root
  repo_root="$(find_repo_root)" || return 1
  printf '%s\n' "${repo_root}/modules/niri/dotfiles/niri/generated/workspace-rules.kdl"
}

workspace_assets_script() {
  local repo_root
  repo_root="$(find_repo_root)" || return 1
  printf '%s\n' "${repo_root}/modules/niri/scripts/render-workspace-assets.sh"
}

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME <command>

Commands:
  status                         Show current Niri workspace mode
  current|managed|with-workspaces
                                 Render/apply repo-managed static workspaces
  natural|plain|dynamic|no-workspaces
                                 Disable static workspace mapping/shortcuts/rules

Examples:
  $SCRIPT_NAME status
  $SCRIPT_NAME managed
  $SCRIPT_NAME natural
EOF
}

ensure_target_dir() {
  mkdir -p "${TARGET_RUNTIME_DIR}"
}

workspace_count() {
  local count

  [[ -f "${TARGET_FILE}" ]] || {
    printf '0\n'
    return 0
  }

  count="$(awk '/^workspace "/ {c++} END {print c+0}' "${TARGET_FILE}" 2>/dev/null || true)"
  printf '%s\n' "${count:-0}"
}

block_contains() {
  local file="$1"
  local begin="$2"
  local end="$3"
  local pattern="$4"

  awk -v begin="${begin}" -v end="${end}" -v pattern="${pattern}" '
    $0 == begin { in_block=1; next }
    $0 == end { in_block=0 }
    in_block && $0 ~ pattern { found=1 }
    END { exit found ? 0 : 1 }
  ' "${file}"
}

shortcuts_mode() {
  local shortcuts_file="$1"
  if block_contains "${shortcuts_file}" "${BEGIN_SHORTCUTS}" "${END_SHORTCUTS}" 'focus-workspace "1"'; then
    printf 'managed\n'
  else
    printf 'natural\n'
  fi
}

rules_mode() {
  local rules_file="$1"
  if block_contains "${rules_file}" "${BEGIN_RULES}" "${END_RULES}" 'open-on-workspace "1"'; then
    printf 'managed\n'
  else
    printf 'natural\n'
  fi
}

overall_mode() {
  local shortcuts_file="$1"
  local rules_file="$2"
  local file_mode shortcut_mode_value rules_mode_value

  file_mode="natural"
  [[ "$(workspace_count)" -gt 0 ]] && file_mode="managed"
  shortcut_mode_value="$(shortcuts_mode "${shortcuts_file}")"
  rules_mode_value="$(rules_mode "${rules_file}")"

  if [[ "${file_mode}" == "managed" && "${shortcut_mode_value}" == "managed" && "${rules_mode_value}" == "managed" ]]; then
    printf 'managed\n'
  elif [[ "${file_mode}" == "natural" && "${shortcut_mode_value}" == "natural" && "${rules_mode_value}" == "natural" ]]; then
    printf 'natural\n'
  else
    printf 'mixed\n'
  fi
}

reload_niri_config() {
  command -v niri >/dev/null 2>&1 || return 0
  niri msg action load-config-file >/dev/null 2>&1 || true
}

refresh_noctalia_if_running() {
  command -v systemctl >/dev/null 2>&1 || return 0
  systemctl --user --quiet is-active noctalia.service >/dev/null 2>&1 || return 0
  systemctl --user restart noctalia.service >/dev/null 2>&1 || true
  sleep 2
}

write_natural_file() {
  ensure_target_dir
  cat > "${TARGET_FILE}" <<'EOF'
// Dynamic workspace mode enabled by osc-niri-workspaces-mode.
// This file is intentionally empty so Niri uses its natural/dynamic workspace behavior.
// Run `osc-niri-workspaces-mode managed` to restore repo-managed static workspace placement.
EOF
}

natural_shortcuts_content() {
  cat <<'EOF'
  // Static workspace shortcuts disabled.
  // Niri now uses natural/dynamic workspaces without fixed 1..9 bindings.
EOF
}

natural_rules_content() {
  cat <<'EOF'
// Static app-to-workspace placement disabled.
// Applications will open according to Niri's natural/dynamic workspace behavior.
EOF
}

write_natural_runtime_rules() {
  ensure_target_dir
  cat > "${RUNTIME_RULES_FILE}" <<'EOF'
# Natural workspace mode enabled by osc-niri-workspaces-mode.
# This file is intentionally empty so arrange helpers skip static app routing.
EOF
}

replace_marked_block() {
  local file="$1"
  local begin="$2"
  local end="$3"
  local content_source="$4"
  local tmp out

  grep -Fqx "${begin}" "${file}" || {
    echo "ERROR: begin marker not found in ${file}: ${begin}" >&2
    exit 1
  }
  grep -Fqx "${end}" "${file}" || {
    echo "ERROR: end marker not found in ${file}: ${end}" >&2
    exit 1
  }

  tmp="$(mktemp)"
  out="$(mktemp)"
  "${content_source}" > "${tmp}"

  awk -v begin="${begin}" -v end="${end}" -v replacement="${tmp}" '
    $0 == begin {
      print
      while ((getline line < replacement) > 0) {
        print line
      }
      skip=1
      next
    }
    $0 == end {
      skip=0
      print
      next
    }
    !skip { print }
  ' "${file}" > "${out}"

  mv -f "${out}" "${file}"
  rm -f "${tmp}"
}

live_workspaces_json() {
  command -v niri >/dev/null 2>&1 || return 1
  niri msg -j workspaces 2>/dev/null || return 1
}

live_windows_json() {
  command -v niri >/dev/null 2>&1 || return 1
  niri msg -j windows 2>/dev/null || return 1
}

focused_window_id() {
  local windows_json="$1"
  jq -r 'first(.[]? | select(.is_focused == true) | .id) // empty' <<<"${windows_json}" 2>/dev/null || true
}

workspace_output_by_id() {
  local workspace_id="$1"
  local workspaces_json="$2"
  jq -r --arg id "${workspace_id}" '
    first(.[]? | select((.id | tostring) == $id) | (.output // "")) // ""
  ' <<<"${workspaces_json}" 2>/dev/null || true
}

workspace_name_by_id() {
  local workspace_id="$1"
  local workspaces_json="$2"
  jq -r --arg id "${workspace_id}" '
    first(.[]? | select((.id | tostring) == $id) | (.name // "")) // ""
  ' <<<"${workspaces_json}" 2>/dev/null || true
}

niri_action() {
  command -v niri >/dev/null 2>&1 || return 1
  niri msg action "$@" >/dev/null 2>&1
}

focus_monitor_name() {
  local output_name="$1"
  [[ -n "${output_name}" ]] || return 0
  niri_action focus-monitor "${output_name}" || true
}

focus_workspace_ref() {
  local workspace_ref="$1"
  [[ -n "${workspace_ref}" ]] || return 0
  niri_action focus-workspace "${workspace_ref}" || true
}

set_workspace_name_ref() {
  local workspace_ref="$1"
  local workspace_name="$2"
  [[ -n "${workspace_ref}" && -n "${workspace_name}" ]] || return 0
  niri_action set-workspace-name --workspace "${workspace_ref}" "${workspace_name}" || true
}

unset_workspace_name_ref() {
  local workspace_ref="$1"
  [[ -n "${workspace_ref}" ]] || return 0
  niri_action unset-workspace-name "${workspace_ref}" || true
}

sanitize_token() {
  local value="${1:-}"
  value="${value//[^[:alnum:]]/_}"
  printf '%s\n' "${value}"
}

managed_workspace_targets() {
  awk '
    /^workspace "/ {
      name = $2
      gsub(/"/, "", name)
      next
    }
    /open-on-output "/ {
      output = $2
      gsub(/"|;/, "", output)
      if (name != "" && output != "") {
        print output "\t" name
      }
      name = ""
      output = ""
    }
  ' "${TARGET_FILE}" 2>/dev/null || true
}

RULES_LOADED=0
declare -a RULE_PATTERNS=()
declare -a RULE_WORKSPACES=()
declare -a RULE_TITLE_PATTERNS=()

load_runtime_workspace_rules() {
  [[ "${RULES_LOADED}" -eq 1 ]] && return 0
  RULES_LOADED=1
  RULE_PATTERNS=()
  RULE_WORKSPACES=()
  RULE_TITLE_PATTERNS=()

  [[ -f "${RUNTIME_RULES_FILE}" ]] || return 1

  while IFS=$'\t' read -r pattern ws title; do
    [[ -z "${pattern//[[:space:]]/}" ]] && continue
    [[ "${pattern:0:1}" == "#" ]] && continue
    [[ -z "${ws//[[:space:]]/}" ]] && continue
    RULE_PATTERNS+=("${pattern}")
    RULE_WORKSPACES+=("${ws}")
    RULE_TITLE_PATTERNS+=("${title:-}")
  done < "${RUNTIME_RULES_FILE}"

  [[ "${#RULE_PATTERNS[@]}" -gt 0 ]]
}

cleanup_osc_workspace_names() {
  local workspaces_json workspace_name

  workspaces_json="$(live_workspaces_json || true)"
  [[ -n "${workspaces_json}" ]] || return 0

  while IFS= read -r workspace_name; do
    [[ -n "${workspace_name}" ]] || continue
    unset_workspace_name_ref "${workspace_name}"
  done < <(
    jq -r '
      .[]?
      | (.name // "")
      | select(startswith("__osc_"))
    ' <<<"${workspaces_json}" 2>/dev/null | sort -u
  )
}

prime_managed_live_workspaces() {
  local workspaces_json output_name workspace_idx target_slot
  local target_output target_name
  local -a live_indices=()
  local -a output_targets=()
  local -A existing_slots=()

  workspaces_json="$(live_workspaces_json || true)"
  [[ -n "${workspaces_json}" ]] || return 0

  while IFS= read -r target_slot; do
    [[ -n "${target_slot}" ]] || continue
    existing_slots["${target_slot}"]=1
  done < <(
    jq -r '
      .[]?
      | (.name // "")
      | select(test("^[0-9]+$"))
    ' <<<"${workspaces_json}" 2>/dev/null
  )

  while IFS=$'\t' read -r target_output target_name; do
    [[ -n "${target_output}" && -n "${target_name}" ]] || continue
    output_targets+=("${target_output}"$'\t'"${target_name}")
  done < <(managed_workspace_targets)

  while IFS= read -r output_name; do
    [[ -n "${output_name}" ]] || continue

    mapfile -t live_indices < <(
      jq -r --arg output "${output_name}" '
        .[]?
        | select(.output == $output and ((.name // "") == ""))
        | (.idx | tostring)
      ' <<<"${workspaces_json}" 2>/dev/null | sort -n
    )

    [[ "${#live_indices[@]}" -gt 0 ]] || continue

    mapfile -t output_targets < <(
      managed_workspace_targets | awk -F '\t' -v output="${output_name}" '$1 == output { print $2 }'
    )

    [[ "${#output_targets[@]}" -gt 0 ]] || continue

    for workspace_idx in "${live_indices[@]}"; do
      target_slot=""
      while [[ "${#output_targets[@]}" -gt 0 ]]; do
        target_slot="${output_targets[0]}"
        output_targets=("${output_targets[@]:1}")
        [[ -n "${existing_slots[${target_slot}]:-}" ]] && continue
        break
      done

      [[ -n "${target_slot}" ]] || break
      focus_monitor_name "${output_name}"
      set_workspace_name_ref "${workspace_idx}" "${target_slot}"
      existing_slots["${target_slot}"]=1
      workspaces_json="$(live_workspaces_json || true)"
    done
  done < <(managed_workspace_targets | awk -F '\t' '{print $1}' | sort -u)
}

move_window_to_workspace_ref() {
  local window_id="$1"
  local workspace_ref="$2"
  local follow_focus="${3:-false}"
  [[ -n "${window_id}" && -n "${workspace_ref}" ]] || return 0
  niri msg action move-window-to-workspace --window-id "${window_id}" --focus "${follow_focus}" "${workspace_ref}" >/dev/null 2>&1 || true
}

focus_window_id() {
  local window_id="$1"
  [[ -n "${window_id}" ]] || return 0
  niri msg action focus-window --id "${window_id}" >/dev/null 2>&1 || true
}

managed_target_workspace_for_window() {
  local app_id="${1:-}"
  local title="${2:-}"
  local i=""
  local title_pattern=""

  if load_runtime_workspace_rules; then
    for i in "${!RULE_PATTERNS[@]}"; do
      if [[ "${app_id}" =~ ${RULE_PATTERNS[$i]} ]]; then
        title_pattern="${RULE_TITLE_PATTERNS[$i]:-}"
        if [[ -n "${title_pattern//[[:space:]]/}" ]] && [[ ! "${title}" =~ ${title_pattern} ]]; then
          continue
        fi
        printf '%s\n' "${RULE_WORKSPACES[$i]}"
        return 0
      fi
    done
  fi

  if [[ "${app_id}" =~ ^Kenp$ ]]; then
    printf '1\n'
  elif [[ "${app_id}" == "TmuxKenp" ]] || [[ "${app_id}" =~ ^(kitty|org\.wezfurlong\.wezterm)$ && "${title}" =~ ^Tmux$ ]]; then
    printf '2\n'
  elif [[ "${app_id}" =~ ^(Ai|Nil)$ ]]; then
    printf '3\n'
  elif [[ "${app_id}" =~ ^CompecTA$ ]]; then
    printf '4\n'
  elif [[ "${app_id}" =~ ^(discord|WebCord|audacious)$ ]]; then
    printf '5\n'
  elif [[ "${app_id}" =~ ^(Exclude|org\.telegram\.desktop|vlc|remote-viewer)$ ]]; then
    printf '6\n'
  elif [[ "${app_id}" =~ ^(transmission|org\.keepassxc\.KeePassXC|(brave-youtube|chrome-youtube)\.com__-Default)$ ]]; then
    printf '7\n'
  elif [[ "${app_id}" =~ ^(spotify|Spotify|com\.spotify\.Client)$ ]]; then
    printf '8\n'
  elif [[ "${app_id}" =~ ^(ferdium|Ferdium|com\.rtosta\.zapzap|Whats|chrome-web\.whatsapp\.com__-Default)$ ]]; then
    printf '9\n'
  else
    printf '\n'
  fi
}

rearrange_live_windows_managed() {
  local windows_json workspaces_json focused_id
  local window_id app_id title target_slot target_ref focused_target_ref
  local output_name workspace_idx temp_ref
  declare -A target_refs=()
  declare -A focus_refs_by_output=()

  cleanup_osc_workspace_names
  windows_json="$(live_windows_json || true)"
  workspaces_json="$(live_workspaces_json || true)"
  [[ -n "${windows_json}" && -n "${workspaces_json}" ]] || return 0

  focused_id="$(focused_window_id "${windows_json}")"

  for target_slot in 1 2 3 4 5 6 7 8 9; do
    workspaces_json="$(live_workspaces_json || true)"
    read -r output_name workspace_idx < <(
      jq -r --arg slot "${target_slot}" '
        first(
          .[]?
          | select((.name // "") == $slot)
          | [(.output // ""), (.idx | tostring)]
          | @tsv
        ) // ""
      ' <<<"${workspaces_json}" 2>/dev/null
    )
    [[ -n "${target_slot}" && -n "${output_name}" && -n "${workspace_idx}" ]] || continue
    temp_ref="__osc_managed_${BASHPID}_${target_slot}"
    focus_monitor_name "${output_name}"
    set_workspace_name_ref "${workspace_idx}" "${temp_ref}"
    target_refs["${target_slot}"]="${temp_ref}"
    if [[ -z "${focus_refs_by_output[${output_name}]:-}" ]]; then
      focus_refs_by_output["${output_name}"]="${temp_ref}"
    fi
  done

  windows_json="$(live_windows_json || true)"

  while IFS=$'\t' read -r window_id app_id title; do
    [[ -n "${window_id}" ]] || continue
    target_slot="$(managed_target_workspace_for_window "${app_id}" "${title}")"
    target_ref="${target_refs[${target_slot}]:-}"
    [[ -n "${target_ref}" ]] || continue
    if [[ "${window_id}" == "${focused_id}" ]]; then
      focused_target_ref="${target_ref}"
      continue
    fi
    move_window_to_workspace_ref "${window_id}" "${target_ref}" false
  done < <(
    jq -r '.[]? | [(.id | tostring), (.app_id // ""), (.title // "")] | @tsv' <<<"${windows_json}" 2>/dev/null
  )

  for output_name in "${!focus_refs_by_output[@]}"; do
    focus_monitor_name "${output_name}"
    focus_workspace_ref "${focus_refs_by_output[${output_name}]}"
  done

  if [[ -n "${focused_id}" && -n "${focused_target_ref:-}" ]]; then
    move_window_to_workspace_ref "${focused_id}" "${focused_target_ref}" true
  fi

  for target_slot in 1 2 3 4 5 6 7 8 9; do
    target_ref="${target_refs[${target_slot}]:-}"
    [[ -n "${target_ref}" ]] || continue
    set_workspace_name_ref "${target_ref}" "${target_slot}"
  done

  focus_window_id "${focused_id}"
}

rearrange_live_windows_natural() {
  local windows_json workspaces_json focused_id
  local window_id workspace_id output_name current_name target_ref focused_target_ref
  local workspace_idx temp_ref workspace_name
  declare -A output_targets=()

  cleanup_osc_workspace_names
  windows_json="$(live_windows_json || true)"
  workspaces_json="$(live_workspaces_json || true)"
  [[ -n "${windows_json}" && -n "${workspaces_json}" ]] || return 0

  focused_id="$(focused_window_id "${windows_json}")"

  while IFS=$'\t' read -r output_name workspace_idx; do
    [[ -n "${output_name}" && -n "${workspace_idx}" ]] || continue
    temp_ref="__osc_natural_${BASHPID}_$(sanitize_token "${output_name}")"
    focus_monitor_name "${output_name}"
    set_workspace_name_ref "${workspace_idx}" "${temp_ref}"
    output_targets["${output_name}"]="${temp_ref}"
  done < <(
    jq -r '
      .[]?
      | select(.is_active == true)
      | [(.output // ""), (.idx | tostring)]
      | @tsv
    ' <<<"${workspaces_json}" 2>/dev/null
  )

  workspaces_json="$(live_workspaces_json || true)"
  windows_json="$(live_windows_json || true)"

  while IFS=$'\t' read -r window_id workspace_id; do
    [[ -n "${window_id}" && -n "${workspace_id}" ]] || continue
    output_name="$(workspace_output_by_id "${workspace_id}" "${workspaces_json}")"
    target_ref="${output_targets[${output_name}]:-}"
    [[ -n "${target_ref}" ]] || continue
    current_name="$(workspace_name_by_id "${workspace_id}" "${workspaces_json}")"
    [[ "${current_name}" == "${target_ref}" ]] && continue
    if [[ "${window_id}" == "${focused_id}" ]]; then
      focused_target_ref="${target_ref}"
      continue
    fi
    move_window_to_workspace_ref "${window_id}" "${target_ref}" false
  done < <(
    jq -r '.[]? | [(.id | tostring), (.workspace_id | tostring)] | @tsv' <<<"${windows_json}" 2>/dev/null
  )

  for output_name in "${!output_targets[@]}"; do
    focus_monitor_name "${output_name}"
    focus_workspace_ref "${output_targets[${output_name}]}"
  done

  if [[ -n "${focused_id}" && -n "${focused_target_ref:-}" ]]; then
    move_window_to_workspace_ref "${focused_id}" "${focused_target_ref}" true
  fi

  workspaces_json="$(live_workspaces_json || true)"
  while IFS= read -r workspace_name; do
    [[ -n "${workspace_name}" ]] || continue
    unset_workspace_name_ref "${workspace_name}"
  done < <(
    jq -r --arg prefix "__osc_natural_${BASHPID}_" '
      .[]?
      | (.name // "")
      | select(. != "" and (startswith($prefix) | not))
    ' <<<"${workspaces_json}" 2>/dev/null | sort -u
  )

  for output_name in "${!output_targets[@]}"; do
    unset_workspace_name_ref "${output_targets[${output_name}]}"
  done

  focus_window_id "${focused_id}"
}

show_status() {
  local config_file shortcuts_file rules_file mode count shortcut_mode_value rules_mode_value
  config_file="$(resolve_config_file)"
  shortcuts_file="$(generated_shortcuts_file)"
  rules_file="$(generated_rules_file)"
  mode="$(overall_mode "${shortcuts_file}" "${rules_file}")"
  count="$(workspace_count)"
  shortcut_mode_value="$(shortcuts_mode "${shortcuts_file}")"
  rules_mode_value="$(rules_mode "${rules_file}")"

  printf 'Niri workspace mode\n'
  printf '  overall mode: %s\n' "${mode}"
  printf '  config: %s\n' "${config_file}"
  printf '  generated shortcuts: %s\n' "${shortcuts_file}"
  printf '  generated rules: %s\n' "${rules_file}"
  printf '  workspace file: %s\n' "${TARGET_FILE}"
  printf '  static workspace blocks: %s\n' "${count}"
  printf '  shortcuts: %s\n' "${shortcut_mode_value}"
  printf '  app placement rules: %s\n' "${rules_mode_value}"

  if command -v niri >/dev/null 2>&1; then
    local runtime_json="" runtime_count="" named_count="" unnamed_count=""
    runtime_json="$(niri msg -j workspaces 2>/dev/null || true)"
    runtime_count="$(jq 'length' <<<"${runtime_json}" 2>/dev/null || true)"
    named_count="$(jq '[.[]? | select((.name // "") != "")] | length' <<<"${runtime_json}" 2>/dev/null || true)"
    unnamed_count="$(jq '[.[]? | select((.name // "") == "")] | length' <<<"${runtime_json}" 2>/dev/null || true)"
    if [[ -n "${runtime_count}" ]]; then
      printf '  live runtime workspaces: %s\n' "${runtime_count}"
      printf '  live named workspaces: %s\n' "${named_count:-0}"
      printf '  live unnamed workspaces: %s\n' "${unnamed_count:-0}"
    fi
  fi
}

apply_managed() {
  local repo_root render_script assets_script
  repo_root="$(find_repo_root)" || {
    echo "ERROR: repo root not found; cannot render managed workspaces" >&2
    exit 1
  }

  assets_script="${repo_root}/modules/niri/scripts/render-workspace-assets.sh"
  render_script="${repo_root}/modules/niri/scripts/render-profile.sh"

  NIRI_RUNTIME_DIR="${TARGET_RUNTIME_DIR}" bash "${assets_script}" --runtime-dir "${TARGET_RUNTIME_DIR}"
  NIRI_RUNTIME_DIR="${TARGET_RUNTIME_DIR}" bash "${render_script}"
  prime_managed_live_workspaces
  reload_niri_config
  rearrange_live_windows_managed
  refresh_noctalia_if_running
  sleep 0.1
  show_status
}

apply_natural() {
  local shortcuts_file rules_file
  shortcuts_file="$(generated_shortcuts_file)"
  rules_file="$(generated_rules_file)"

  replace_marked_block "${shortcuts_file}" "${BEGIN_SHORTCUTS}" "${END_SHORTCUTS}" natural_shortcuts_content
  replace_marked_block "${rules_file}" "${BEGIN_RULES}" "${END_RULES}" natural_rules_content
  write_natural_file
  write_natural_runtime_rules
  reload_niri_config
  rearrange_live_windows_natural
  refresh_noctalia_if_running
  sleep 0.1
  show_status
}

main() {
  local cmd="${1:-status}"

  case "${cmd}" in
    status|show)
      show_status
      ;;
    current|managed|with-workspaces)
      apply_managed
      ;;
    natural|plain|dynamic|no-workspaces)
      apply_natural
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
