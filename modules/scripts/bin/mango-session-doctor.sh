#!/usr/bin/env bash
# ==============================================================================
# Script: mango-session-doctor
# Description: Print MangoWM session diagnostics, runtime state, and unit graph.
# Usage: mango-session-doctor [--tree] [--logs] [--all]
# ==============================================================================

set -euo pipefail

SHOW_TREE=false
SHOW_LOGS=false

MANGO_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mango"
MANGO_RUNTIME_DIR="${MANGO_CONFIG_DIR}/runtime"
MANGO_CONFIG_FILE="${MANGO_CONFIG_DIR}/config.conf"
MANGO_PROFILE_FILE="${MANGO_RUNTIME_DIR}/profile.conf"

usage() {
  cat <<'EOF'
Usage: mango-session-doctor [--tree] [--logs] [--all]

  --tree  Show the mangowm-session.target dependency tree.
  --logs  Show recent boot logs for key Mango session units.
  --all   Enable both --tree and --logs.
EOF
}

maybe() {
  command -v "$1" >/dev/null 2>&1
}

print_section() {
  printf '\n== %s ==\n' "$1"
}

kv() {
  local key="$1"
  local value="${2:-<unset>}"
  printf '%-34s %s\n' "${key}" "${value}"
}

print_env_var() {
  local name="$1"
  kv "${name}" "${!name:-<unset>}"
}

systemctl_user_quick() {
  systemctl --user "$@" 2>/dev/null || true
}

unit_state() {
  local unit="$1"
  local state
  state="$(systemctl_user_quick is-active "${unit}")"
  [[ -n "${state}" ]] || state="inactive"
  printf '%s' "${state}"
}

print_units_status() {
  local unit
  for unit in "$@"; do
    [[ -n "${unit}" ]] || continue
    kv "${unit}" "$(unit_state "${unit}")"
  done
}

print_units_status_section() {
  local unit
  local -A seen_units=()
  for unit in "$@"; do
    [[ -n "${unit}" ]] || continue
    if [[ -n "${seen_units[${unit}]:-}" ]]; then
      continue
    fi
    seen_units["${unit}"]=1
    kv "${unit}" "$(unit_state "${unit}")"
  done
}

sysenv_get() {
  local dump="$1"
  local key="$2"
  awk -F= -v wanted="${key}" '
    $1 == wanted {
      sub(/^[^=]*=/, "", $0)
      print
      exit
    }
  ' <<<"${dump}"
}

print_runtime_include_file() {
  local label="$1"
  local relative_name="$2"
  local file_path="$3"
  local include_line="source=./runtime/${relative_name}"
  if [[ ! -f "${file_path}" ]]; then
    kv "${label}" "missing"
    return
  fi
  if [[ -f "${MANGO_CONFIG_FILE}" ]] && grep -Fq "${include_line}" "${MANGO_CONFIG_FILE}"; then
    kv "${label}" "${file_path}"
  else
    kv "${label}" "${file_path} (not sourced from config.conf)"
  fi
}

print_runtime_file() {
  local label="$1"
  local file_path="$2"
  if [[ -f "${file_path}" ]]; then
    kv "${label}" "${file_path}"
  else
    kv "${label}" "missing"
  fi
}

flatten_single_line() {
  tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

print_profile_mappings() {
  if [[ ! -r "${MANGO_PROFILE_FILE}" ]]; then
    kv "profile.conf" "missing"
    return
  fi

  kv "profile.conf" "${MANGO_PROFILE_FILE}"
  awk -F',' '
    /^tagrule=/ {
      tag = ""
      monitor = ""
      layout = ""
      no_hide = ""
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^tagrule=id:/) {
          tag = $i
          sub(/^tagrule=id:/, "", tag)
        } else if ($i ~ /^monitor_name:/) {
          monitor = $i
          sub(/^monitor_name:/, "", monitor)
        } else if ($i ~ /^layout_name:/) {
          layout = $i
          sub(/^layout_name:/, "", layout)
        } else if ($i ~ /^no_hide:/) {
          no_hide = $i
          sub(/^no_hide:/, "", no_hide)
        }
      }
      if (tag != "" && monitor != "") {
        printf "  tag:%s monitor:%s layout:%s no_hide:%s\n", tag, monitor, layout, no_hide
      }
    }
  ' "${MANGO_PROFILE_FILE}" || true
}

while (($#)); do
  case "$1" in
    --tree)
      SHOW_TREE=true
      shift
      ;;
    --logs)
      SHOW_LOGS=true
      shift
      ;;
    --all)
      SHOW_TREE=true
      SHOW_LOGS=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

main() {
  local bus_state="unavailable"

  print_section "Session"
  print_env_var XDG_CURRENT_DESKTOP
  print_env_var XDG_SESSION_DESKTOP
  print_env_var DESKTOP_SESSION
  print_env_var XDG_SESSION_TYPE
  print_env_var WAYLAND_DISPLAY
  print_env_var DISPLAY
  print_env_var SSH_AUTH_SOCK

  print_section "Mango IPC"
  if maybe mmsg; then
    if mmsg -g -b >/dev/null 2>&1; then
      kv "mmsg:keymode" "$(mmsg -g -b 2>/dev/null | flatten_single_line)"
      kv "mmsg:keyboard-layout" "$(mmsg -g -k 2>/dev/null | flatten_single_line)"
      kv "mmsg:focused-client" "$(mmsg -g -c 2>/dev/null | flatten_single_line)"
      echo "Outputs (raw)"
      mmsg -O 2>/dev/null | sed 's/^/  /' || true
    else
      kv "mmsg" "available, but not connected to a live Mango session"
    fi
  else
    kv "mmsg" "not installed"
  fi

  print_section "Manager Environment"
  if maybe systemctl; then
    local sysenv_dump
    sysenv_dump="$(systemctl_user_quick show-environment)"
    bus_state="$(systemctl_user_quick is-system-running)"
    [[ -n "${bus_state}" ]] || bus_state="unavailable"
    kv "systemd --user bus" "${bus_state}"
    if [[ "${bus_state}" != "unavailable" && -n "${sysenv_dump}" ]]; then
      kv "userenv:WAYLAND_DISPLAY" "$(sysenv_get "${sysenv_dump}" "WAYLAND_DISPLAY")"
      kv "userenv:XDG_CURRENT_DESKTOP" "$(sysenv_get "${sysenv_dump}" "XDG_CURRENT_DESKTOP")"
      kv "userenv:XDG_SESSION_DESKTOP" "$(sysenv_get "${sysenv_dump}" "XDG_SESSION_DESKTOP")"
      kv "userenv:XDG_SESSION_TYPE" "$(sysenv_get "${sysenv_dump}" "XDG_SESSION_TYPE")"
      kv "userenv:DESKTOP_SESSION" "$(sysenv_get "${sysenv_dump}" "DESKTOP_SESSION")"
      kv "userenv:DISPLAY" "$(sysenv_get "${sysenv_dump}" "DISPLAY")"
    fi
  else
    kv "systemctl" "not available"
  fi

  print_section "Units (key)"
  if maybe systemctl && [[ "${bus_state}" != "unavailable" ]]; then
    print_units_status \
      mangowm-session.target \
      mango-daemons.target \
      mango-post-daemons.target \
      mango-session-ready.target \
      graphical-session.target \
      xdg-desktop-autostart.target \
      mango-session-env.service \
      mango-bootstrap.service \
      mango-audio-init.service \
      mango-arrange.service \
      mango-shell-ensure.service \
      mango-desktop-settings.service \
      mango-post-bootstrap.service \
      mango-status-notifier-ready.service \
      mango-polkit-agent.service \
      mango-nm-applet.service \
      mango-blueman-applet.service \
      noctalia.service \
      xdg-desktop-portal.service \
      xdg-desktop-portal-wlr.service \
      xdg-desktop-portal-gtk.service \
      "wayland-wm@mango\\x2dsession.service"

    local wants_raw requires_raw
    wants_raw="$(systemctl_user_quick show -p Wants --value mangowm-session.target)"
    requires_raw="$(systemctl_user_quick show -p Requires --value mangowm-session.target)"
    if [[ -n "${wants_raw}${requires_raw}" ]]; then
      local -a wants_units=()
      local -a requires_units=()
      IFS=' ' read -r -a wants_units <<<"${wants_raw:-}"
      IFS=' ' read -r -a requires_units <<<"${requires_raw:-}"
      print_section "Units (mangowm-session.target wants/requires)"
      print_units_status_section "${wants_units[@]}" "${requires_units[@]}"
    fi
  else
    kv "systemd --user" "unavailable"
  fi

  print_section "Runtime"
  kv "config.conf" "$([[ -f "${MANGO_CONFIG_FILE}" ]] && printf '%s' "${MANGO_CONFIG_FILE}" || printf 'missing')"
  print_runtime_include_file "runtime:profile.conf" "profile.conf" "${MANGO_RUNTIME_DIR}/profile.conf"
  print_runtime_include_file "runtime:workspace-rules.conf" "workspace-rules.conf" "${MANGO_RUNTIME_DIR}/workspace-rules.conf"
  print_runtime_include_file "runtime:workspace-binds.conf" "workspace-binds.conf" "${MANGO_RUNTIME_DIR}/workspace-binds.conf"
  print_runtime_file "runtime:keybind-cheatsheet.conf" "${MANGO_RUNTIME_DIR}/keybind-cheatsheet.conf"
  echo "Profile mappings"
  print_profile_mappings

  if [[ "${SHOW_TREE}" == "true" ]] && maybe systemctl; then
    print_section "Dependency tree (mangowm-session.target)"
    systemctl --user list-dependencies --plain --no-pager mangowm-session.target 2>/dev/null || true
  fi

  if [[ "${SHOW_LOGS}" == "true" ]] && maybe journalctl; then
    print_section "Logs (this boot)"
    journalctl --user -b --no-pager -n 80 \
      -u mango-session-env.service \
      -u mango-bootstrap.service \
      -u mango-arrange.service \
      -u mango-post-bootstrap.service \
      -u noctalia.service || true
  fi

  if [[ -t 1 ]]; then
    printf '\nPress any key to close...'
    IFS= read -r -n 1 _ || true
    printf '\n'
  fi
}

main "$@"
