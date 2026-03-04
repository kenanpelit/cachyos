#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/../dotfiles"

WRAPPER_SRC="${CONFIG_DIR}/dms-greeter-wrapper"
HYPR_SRC="${CONFIG_DIR}/hyprland.conf"
GREETD_SRC="${CONFIG_DIR}/config.toml"

WRAPPER_DST="/usr/local/bin/dms-greeter-wrapper"
GREETER_CONF_DIR="/etc/dms-greeter"
HYPR_DST="${GREETER_CONF_DIR}/hyprland.conf"
GREETD_CONF_DIR="/etc/greetd"
GREETD_DST="${GREETD_CONF_DIR}/config.toml"

GREETER_USER="greeter"
GREETER_HOME="/var/lib/dms-greeter"
CACHE_DIR="/var/cache/dms-greeter"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required" >&2
    exit 1
  fi
  SUDO="sudo"
fi

run_root() {
  if [ -n "${SUDO}" ]; then
    "${SUDO}" "$@"
  else
    "$@"
  fi
}

TARGET_USER="${SUDO_USER:-${USER:-}}"
if [ -z "${TARGET_USER}" ] || [ "${TARGET_USER}" = "root" ]; then
  TARGET_USER="$(logname 2>/dev/null || true)"
fi
if [ -z "${TARGET_USER}" ] || [ "${TARGET_USER}" = "root" ]; then
  echo "Could not resolve target desktop user (current: ${USER:-unknown})" >&2
  exit 1
fi

TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
if [ -z "${TARGET_HOME}" ] || [ ! -d "${TARGET_HOME}" ]; then
  echo "Home directory not found for user '${TARGET_USER}'" >&2
  exit 1
fi

SETTINGS_SRC="${TARGET_HOME}/.config/DankMaterialShell/settings.json"
SESSION_SRC="${TARGET_HOME}/.local/state/DankMaterialShell/session.json"
COLORS_SRC="${TARGET_HOME}/.cache/DankMaterialShell/dms-colors.json"

backup_if_exists() {
  local file="$1"
  if run_root test -f "${file}"; then
    run_root cp -a "${file}" "${file}.bak.$(date +%Y%m%d-%H%M%S)"
  fi
}

ensure_greeter_user() {
  if ! id "${GREETER_USER}" >/dev/null 2>&1; then
    run_root useradd -r -M -U -d "${GREETER_HOME}" -s /usr/bin/nologin "${GREETER_USER}"
  else
    current_home="$(getent passwd "${GREETER_USER}" | cut -d: -f6 || true)"
    if [ -z "${current_home}" ] || [ "${current_home}" = "/" ] || [ "${current_home}" != "${GREETER_HOME}" ]; then
      run_root usermod -d "${GREETER_HOME}" "${GREETER_USER}" >/dev/null 2>&1 || true
    fi
  fi

  run_root usermod -aG video,input "${GREETER_USER}" >/dev/null 2>&1 || true

  run_root install -d -m 755 -o "${GREETER_USER}" -g "${GREETER_USER}" "${GREETER_HOME}"
  run_root install -d -m 755 -o "${GREETER_USER}" -g "${GREETER_USER}" "${CACHE_DIR}"
}

install_system_files() {
  [ -f "${WRAPPER_SRC}" ] || { echo "Missing ${WRAPPER_SRC}" >&2; exit 1; }
  [ -f "${HYPR_SRC}" ] || { echo "Missing ${HYPR_SRC}" >&2; exit 1; }
  [ -f "${GREETD_SRC}" ] || { echo "Missing ${GREETD_SRC}" >&2; exit 1; }

  run_root install -d -m 755 /usr/local/bin
  run_root install -m 755 "${WRAPPER_SRC}" "${WRAPPER_DST}"

  run_root install -d -m 755 "${GREETER_CONF_DIR}" "${GREETD_CONF_DIR}"
  run_root install -m 644 "${HYPR_SRC}" "${HYPR_DST}"

  backup_if_exists "${GREETD_DST}"
  run_root install -m 644 "${GREETD_SRC}" "${GREETD_DST}"
}

ensure_json_file() {
  local path="$1"
  local dir
  dir="$(dirname "${path}")"

  mkdir -p "${dir}"
  if [ ! -f "${path}" ]; then
    printf '{}\n' > "${path}"
  fi
  chown "${TARGET_USER}:${TARGET_USER}" "${path}" >/dev/null 2>&1 || true
}

sync_dms_config_links() {
  ensure_json_file "${SETTINGS_SRC}"
  ensure_json_file "${SESSION_SRC}"
  ensure_json_file "${COLORS_SRC}"

  run_root ln -sfn "${SETTINGS_SRC}" "${CACHE_DIR}/settings.json"
  run_root ln -sfn "${SESSION_SRC}" "${CACHE_DIR}/session.json"
  run_root ln -sfn "${COLORS_SRC}" "${CACHE_DIR}/colors.json"

  run_root chown -h "${GREETER_USER}:${GREETER_USER}" "${CACHE_DIR}/settings.json" "${CACHE_DIR}/session.json" "${CACHE_DIR}/colors.json" || true
}

set_acl_dir_rx() {
  local dir="$1"
  [ -d "${dir}" ] || return 0
  run_root setfacl -m "u:${GREETER_USER}:rx" "${dir}" >/dev/null 2>&1 || true
}

set_acl_file_r() {
  local file="$1"
  [ -f "${file}" ] || return 0
  run_root setfacl -m "u:${GREETER_USER}:r" "${file}" >/dev/null 2>&1 || true
}

set_path_traverse_acl() {
  local path="$1"
  local dir
  dir="$(dirname "${path}")"

  while [ "${dir}" != "/" ] && [ -n "${dir}" ]; do
    run_root setfacl -m "u:${GREETER_USER}:x" "${dir}" >/dev/null 2>&1 || true
    dir="$(dirname "${dir}")"
  done
}

apply_acl_sync_permissions() {
  if ! command -v setfacl >/dev/null 2>&1; then
    echo "setfacl not found, skipping ACL setup (install package: acl)." >&2
    return 0
  fi

  set_acl_dir_rx "${TARGET_HOME}"
  set_acl_dir_rx "${TARGET_HOME}/.config"
  set_acl_dir_rx "${TARGET_HOME}/.local"
  set_acl_dir_rx "${TARGET_HOME}/.local/state"
  set_acl_dir_rx "${TARGET_HOME}/.cache"

  set_acl_file_r "${SETTINGS_SRC}"
  set_acl_file_r "${SESSION_SRC}"
  set_acl_file_r "${COLORS_SRC}"

  # Try to grant read/traverse for wallpaper files referenced in session/state JSON.
  if command -v jq >/dev/null 2>&1; then
    local wp
    while IFS= read -r wp; do
      [ -f "${wp}" ] || continue
      case "${wp,,}" in
        *.png|*.jpg|*.jpeg|*.webp|*.bmp|*.gif|*.avif|*.heic|*.mp4|*.mkv|*.mov|*.webm)
          set_path_traverse_acl "${wp}"
          set_acl_file_r "${wp}"
          ;;
      esac
    done < <(jq -r '.. | strings | select(startswith("/"))' "${SESSION_SRC}" "${SETTINGS_SRC}" 2>/dev/null | sort -u)
  fi
}

enable_greetd() {
  if run_root systemctl list-unit-files greetd.service >/dev/null 2>&1; then
    run_root systemctl daemon-reload
    run_root systemctl enable greetd >/dev/null 2>&1 || true
  else
    echo "greetd.service not found. Install greetd first." >&2
  fi
}

patch_pam_keyring_file() {
  local file="$1"
  local tmp

  [ -f "${file}" ] || return 0
  tmp="$(mktemp)"

  awk '
    BEGIN { auth_added=0; session_added=0 }
    {
      print
      if ($1 == "auth" && $2 == "include" && $3 == "system-local-login" && !auth_added) {
        print "auth       optional     pam_gnome_keyring.so"
        auth_added=1
      }
      if ($1 == "session" && $2 == "include" && $3 == "system-local-login" && !session_added) {
        print "session    optional     pam_gnome_keyring.so auto_start"
        session_added=1
      }
    }
  ' "${file}" > "${tmp}"

  if ! grep -q 'pam_gnome_keyring.so' "${file}"; then
    backup_if_exists "${file}"
    run_root install -m 644 "${tmp}" "${file}"
  fi

  rm -f "${tmp}"
}

ensure_pam_keyring_unlock() {
  patch_pam_keyring_file /etc/pam.d/greetd
  patch_pam_keyring_file /etc/pam.d/login
}

echo "==> DMS Greeter system setup"
echo "Target desktop user: ${TARGET_USER} (${TARGET_HOME})"
echo

ensure_greeter_user
install_system_files
sync_dms_config_links
apply_acl_sync_permissions
ensure_pam_keyring_unlock
enable_greetd

echo "Done."
echo "Synced:"
echo "  ${SETTINGS_SRC} -> ${CACHE_DIR}/settings.json"
echo "  ${SESSION_SRC} -> ${CACHE_DIR}/session.json"
echo "  ${COLORS_SRC} -> ${CACHE_DIR}/colors.json"
echo
echo "If wallpaper still does not update, restart greetd once:"
echo "  sudo systemctl restart greetd"
