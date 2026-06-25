#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# copy-scripts-to-local-bin
# ==============================================================================

module_root="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$module_root/../.." && pwd)"
source "$repo_root/modules/base/lib/core.sh"

system_bin_dir="/usr/local/bin"
bin_dir="$USER_HOME/.local/bin"

target_uid="$(id -u "$REAL_USER")"
target_gid="$(id -g "$REAL_USER")"
is_root=false
installed_count=0
skipped_count=0
[[ "$(id -u)" -eq 0 ]] && is_root=true

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

is_unchanged_install() {
  local src="$1"
  local dst="$2"

  [[ -f "$dst" ]] || return 1
  cmp -s "$src" "$dst" || return 1
  [[ "$(stat -c '%a' "$dst" 2>/dev/null || echo "")" == "755" ]] || return 1
  return 0
}

# Atomic copy: write to a temp file in the same dir, then rename over destination.
atomic_install() {
  local src="$1"
  local dst="$2"
  local tmp

  if is_unchanged_install "$src" "$dst"; then
    ((skipped_count += 1))
    if $is_root; then
      chown "$target_uid:$target_gid" "$dst" || true
    fi
    return 0
  fi

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

  ((installed_count += 1))
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

install_named_script() {
  local src="$1"
  local dst_name="$2"
  local dst="$bin_dir/$dst_name"

  [[ -f "$src" ]] || return 0
  chmod +x "$src" || true
  atomic_install "$src" "$dst"
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
    hypr-session-route
    niri-set
    niri-flow
    niri-keybinds
    osc-perf-mode
    rofi-performance
    start-wkenp
    brave-ext-copy
    brave_killer
    cleanup_brave_profiles
    brave-kenp-default
    brave-extensions
    brave-launcher
    profile_chrome
    chrome-launcher
    start-chrome-kenp
    start-chrome-ai
    start-chrome-compecta
    start-chrome-whats
    cleanup_helium_profiles
    helium-extensions
    helium-kenp-default
    # WM helpers removed on the margo-only branch (niri/hyprland/mango dropped)
    niri-arrange
    niri-bootstrap
    niri-desktop-settings
    niri-float-sticky
    niri-osc
    niri-post-bootstrap
    niri-session-common
    niri-session-init
    niri-snapper-tools-check
    niri-start
    niri-status-notifier-ready
    niri-two-column-layout
    niri-workspace-smart
    hypr-blueman-applet
    hypr-bootstrap
    hypr-desktop-settings
    hypr-expo
    hypr-osc
    hypr-post-bootstrap
    hypr-scroll
    hypr-session-common
    hypr-session-init
    hypr-status-notifier-ready
    mango-arrange
    mango-blueman-applet
    mango-bootstrap
    mango-desktop-settings
    mango-here
    mango-layer-audit
    mango-lid-watch
    mango-monitor-smart
    mango-overview
    mango-performance-mode
    mango-post-bootstrap
    mango-profile-select
    mango-session-common
    mango-session-doctor
    mango-session-init
    mango-session-refresh
    mango-state-bridge
    mango-status-notifier-ready
    mango-tag-smart
    mango-virtual-output
    mango-workspace-smart
    wm-workspace
    osc-here-hypr
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
  # brave / profile_brave / bravectl are owned by modules/brave now.
  install_privileged_system_bins
  cleanup_legacy_bins

  echo "Scripts install summary: $installed_count updated, $skipped_count unchanged"
  
  # Auto-generate documentation
  if [[ -x "$module_root/bin/dcli-docgen" ]]; then
    echo "Generating script documentation..."
    "$module_root/bin/dcli-docgen" || true
  fi
}

main "$@"
