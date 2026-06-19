#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

JOURNAL_SRC="${SCRIPT_DIR}/../dotfiles/journald/10-limits.conf"
JOURNAL_DST="/etc/systemd/journald.conf.d/10-logs.conf"

COREDUMP_SRC="${SCRIPT_DIR}/../dotfiles/coredump/10-limits.conf"
COREDUMP_DST="/etc/systemd/coredump.conf.d/10-logs.conf"

LOGROTATE_SRC="${SCRIPT_DIR}/../dotfiles/logrotate/logs"
LOGROTATE_DST="/etc/logrotate.d/logs"

ATOP_DEFAULTS="/etc/default/atop"
ATOP_GENERATIONS="14"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required" >&2
    exit 1
  fi
  SUDO="sudo"
fi

CHANGED=0

install_managed_file() {
  local src="$1"
  local dst="$2"
  local mode="$3"

  if [ ! -f "${src}" ]; then
    echo "missing source file: ${src}" >&2
    exit 1
  fi

  if [ -L "${dst}" ] || { [ -e "${dst}" ] && [ ! -f "${dst}" ]; }; then
    ${SUDO} rm -f "${dst}"
  fi

  if [ -f "${dst}" ] && cmp -s "${src}" "${dst}"; then
    return 0
  fi

  ${SUDO} install -d -m 755 "$(dirname "${dst}")"
  ${SUDO} install -m "${mode}" "${src}" "${dst}"
  CHANGED=1
}

configure_atop_generations() {
  local tmp

  [ -f "${ATOP_DEFAULTS}" ] || return 0

  tmp="$(mktemp)"
  awk -v val="${ATOP_GENERATIONS}" '
    BEGIN { done = 0 }
    /^[[:space:]]*LOGGENERATIONS=/ {
      print "LOGGENERATIONS=" val
      done = 1
      next
    }
    { print }
    END {
      if (!done) {
        print "LOGGENERATIONS=" val
      }
    }
  ' "${ATOP_DEFAULTS}" > "${tmp}"

  if ! cmp -s "${tmp}" "${ATOP_DEFAULTS}"; then
    ${SUDO} install -m 644 "${tmp}" "${ATOP_DEFAULTS}"
    CHANGED=1
  fi

  rm -f "${tmp}"
}

install_managed_file "${JOURNAL_SRC}" "${JOURNAL_DST}" 644
install_managed_file "${COREDUMP_SRC}" "${COREDUMP_DST}" 644
install_managed_file "${LOGROTATE_SRC}" "${LOGROTATE_DST}" 644
configure_atop_generations

# Ensure periodic logrotate is active.
if ${SUDO} systemctl list-unit-files logrotate.timer >/dev/null 2>&1; then
  ${SUDO} systemctl enable --now logrotate.timer >/dev/null 2>&1 || true
fi

# Apply journald settings immediately when config changed.
if [ "${CHANGED}" -eq 1 ]; then
  ${SUDO} systemctl restart systemd-journald.service >/dev/null 2>&1 || true
fi

# Enforce limits immediately.
${SUDO} journalctl --vacuum-size=200M --vacuum-time=14d >/dev/null 2>&1 || true
${SUDO} coredumpctl --vacuum-size=200M >/dev/null 2>&1 || true

# Safety cleanup for old atop archives in case rotate policies were changed.
if [ -d /var/log/atop ]; then
  ${SUDO} find /var/log/atop -maxdepth 1 -type f -name 'atop_*' -mtime +14 -delete 2>/dev/null || true
fi
