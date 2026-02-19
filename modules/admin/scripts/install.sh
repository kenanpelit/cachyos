#!/usr/bin/env bash
set -euo pipefail

# Only proceed if we are root
if [ "${EUID}" -ne 0 ]; then
  echo "Requires root privileges."
  exit 1
fi

ADMIN_USER="${ADMIN_USER:-kenan}"
SUDOERS_FILE="/etc/sudoers.d/${ADMIN_USER}"
SUDOERS_LINE="${ADMIN_USER} ALL=(ALL) NOPASSWD: ALL"

# Keep groups declarative in admin module. This matches current host usage and
# ensures fusuma/libinput permissions with `input`.
ADMIN_GROUPS=(
  sys
  network
  wheel
  audio
  lp
  storage
  video
  users
  rfkill
  nopasswdlogin
  input
)

ensure_sudoers() {
  if [ -f "${SUDOERS_FILE}" ] && grep -Fxq "${SUDOERS_LINE}" "${SUDOERS_FILE}"; then
    echo "System admin configuration (sudo) already applied."
    return 0
  fi

  echo "Applying system admin configuration (sudo)..."
  printf '%s\n' "${SUDOERS_LINE}" > "${SUDOERS_FILE}"
  chmod 0440 "${SUDOERS_FILE}"
}

ensure_user_groups() {
  if ! id "${ADMIN_USER}" >/dev/null 2>&1; then
    echo "Warning: user '${ADMIN_USER}' not found, skipping group membership management."
    return 0
  fi

  # Required by fusuma/libinput workflows on Arch-like systems.
  groupadd -f input >/dev/null 2>&1 || true

  local changed=0
  local grp
  for grp in "${ADMIN_GROUPS[@]}"; do
    if ! getent group "${grp}" >/dev/null 2>&1; then
      echo "Warning: group '${grp}' does not exist, skipping."
      continue
    fi

    if id -nG "${ADMIN_USER}" | tr ' ' '\n' | grep -qx "${grp}"; then
      continue
    fi

    usermod -aG "${grp}" "${ADMIN_USER}"
    echo "Added '${ADMIN_USER}' to group '${grp}'."
    changed=1
  done

  if [ "${changed}" -eq 1 ]; then
    echo "Group membership updated. Logout/login is required for all changes to take effect."
  fi
}

apply_snapper_root_config() {
  local script_dir snapper_conf_src snapper_conf_dest
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  snapper_conf_src="${script_dir}/../dotfiles/snapper-root"
  snapper_conf_dest="/etc/snapper/configs/root"

  if [ ! -f "${snapper_conf_src}" ]; then
    return 0
  fi

  if [ -d "/etc/snapper/configs" ]; then
    echo "Applying snapper root configuration..."
    cp "${snapper_conf_src}" "${snapper_conf_dest}"
    chmod 644 "${snapper_conf_dest}"
  else
    echo "Warning: /etc/snapper/configs directory not found. Is snapper installed?"
  fi
}

ensure_sudoers
ensure_user_groups
apply_snapper_root_config
