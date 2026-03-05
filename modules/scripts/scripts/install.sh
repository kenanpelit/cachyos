#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# copy-scripts-to-local-bin
# ------------------------------------------------------------------------------
# Copies module scripts (*.sh, *.py) into ~/.local/bin as extensionless executables.
# Ensures files remain owned by the real user even when run under sudo.
#
# Key guarantees:
#   - foo.sh -> ~/.local/bin/foo   (NEVER keeps .sh)
#   - bar.py -> ~/.local/bin/bar   (NEVER keeps .py)
#   - Atomic updates (write to temp, then rename)
#   - User ownership (prevents `dcli sync` permission issues)
# ==============================================================================

module_root="$(cd "$(dirname "$0")/.." && pwd)"
system_bin_dir="/usr/local/bin"

# Resolve target user + home
if [[ -n "${SUDO_USER:-}" ]]; then
  TARGET_USER="$SUDO_USER"
  USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
else
  TARGET_USER="$(id -un)"
  USER_HOME="$HOME"
fi

bin_dir="$USER_HOME/.local/bin"

target_uid="$(id -u "$TARGET_USER")"
target_gid="$(id -g "$TARGET_USER")"
is_root=false
[[ "$(id -u)" -eq 0 ]] && is_root=true

die() {
  echo "ERROR: $*" >&2
  exit 1
}

should_install() {
  case "$1" in
  osc-fiup)
    return 1
    ;;
  *)
    return 0
    ;;
  esac
}

resolve_script_source() {
  local name="$1"
  local src_dir="$2"

  if [[ -f "${src_dir}/${name}" ]]; then
    echo "${src_dir}/${name}"
    return 0
  fi

  if [[ -f "${src_dir}/${name}.sh" ]]; then
    echo "${src_dir}/${name}.sh"
    return 0
  fi

  if [[ -f "${src_dir}/${name}.py" ]]; then
    echo "${src_dir}/${name}.py"
    return 0
  fi

  return 1
}

ensure_bin_dir() {
  mkdir -p "$bin_dir"
  chmod 0755 "$bin_dir" || true
  if $is_root; then
    chown "$target_uid:$target_gid" "$bin_dir" || true
  fi
}

# Atomic copy: write to a temp file in the same dir, then rename over destination.
atomic_install() {
  local src="$1"
  local dst="$2"
  local tmp

  # Use a temp file in the same directory for atomic rename.
  tmp="$bin_dir/.${dst##*/}.tmp.$$"

  # Create/overwrite temp with correct mode.
  if command -v install >/dev/null 2>&1; then
    install -m 0755 "$src" "$tmp"
  else
    cp -f "$src" "$tmp"
    chmod 0755 "$tmp" || true
  fi

  # Ensure ownership before final placement when running as root.
  if $is_root; then
    chown "$target_uid:$target_gid" "$tmp" || true
  fi

  # Replace destination atomically.
  # If this fails with EPERM, it's usually: root-owned dir, immutable flag, or FS perms.
  mv -f "$tmp" "$dst" || {
    rm -f "$tmp" || true
    die "Failed to install '$dst' (check ownership, permissions, or immutable flag with: lsattr '$dst')"
  }

  # Final ownership enforcement (belt + suspenders).
  if $is_root; then
    chown "$target_uid:$target_gid" "$dst" || true
  fi
}

install_from_dir() {
  local src_dir="$1"
  shopt -s nullglob

  for f in "$src_dir"/*.sh "$src_dir"/*.py; do
    local name dst
    name="$(basename "$f")"
    name="${name%.sh}"
    name="${name%.py}"
    dst="$bin_dir/$name"

    should_install "$name" || continue

    # Ensure source is executable (helpful for direct use too).
    chmod +x "$f" || true

    atomic_install "$f" "$dst"
  done
}

install_privileged_system_bins() {
  local privileged_bins=(
    cachy-mount
  )

  # sudo uses secure_path; install root-required scripts into /usr/local/bin.
  $is_root || return 0

  mkdir -p "$system_bin_dir"
  chmod 0755 "$system_bin_dir" || true

  local name src dst
  for name in "${privileged_bins[@]}"; do
    src="$(resolve_script_source "$name" "$module_root/bin" 2>/dev/null || true)"
    if [[ -z "$src" ]]; then
      echo "WARN: privileged script source not found: $name" >&2
      continue
    fi

    dst="$system_bin_dir/$name"
    if command -v install >/dev/null 2>&1; then
      install -m 0755 "$src" "$dst"
    else
      cp -f "$src" "$dst"
      chmod 0755 "$dst" || true
    fi
  done
}

cleanup_legacy_bins() {
  local legacy_bins=(
    hypr-set
    niri-set
    niri-flow
    niri-keybinds
    osc-perf-mode
    rofi-performance
  )

  local b p
  for b in "${legacy_bins[@]}"; do
    p="$bin_dir/$b"
    [[ -e "$p" ]] || continue
    rm -f "$p" || true
  done
}

main() {
  ensure_bin_dir

  install_from_dir "$module_root/bin"
  install_from_dir "$module_root/start"
  install_privileged_system_bins
  cleanup_legacy_bins
}

main "$@"
