#!/usr/bin/env bash
# cachy-mount.sh
# ------------------------------------------------------------------------------
# Dual-disk BTRFS helper:
# - If booted from nvme1n1p1, mount nvme0n1p2 on /cachy
# - If booted from nvme0n1p2, mount nvme1n1p1 on /cachy
# ------------------------------------------------------------------------------

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
if [[ "$SCRIPT_NAME" == "cachy-mount.sh" ]]; then
  SCRIPT_NAME="cachy-mount"
fi

DEFAULT_BASE="/cachy"
PAIR_A="/dev/nvme1n1p1"
PAIR_B="/dev/nvme0n1p2"

# Mount top-level BTRFS tree (subvolid=5) so @, @home, ... are visible.
OPTS_COMMON=("subvolid=5" "noatime" "compress=zstd" "space_cache=v2")

usage() {
  cat <<EOF
Usage:
  sudo ${SCRIPT_NAME} mount   [--base <DIR>] [--device <DEV>]
  sudo ${SCRIPT_NAME} umount  [--base <DIR>]
  sudo ${SCRIPT_NAME} status  [--base <DIR>]
  sudo ${SCRIPT_NAME} chroot  [--base <DIR>] [--root <DIR>]
  sudo ${SCRIPT_NAME} help

Defaults:
  pair A: ${PAIR_A}
  pair B: ${PAIR_B}
  mount point: ${DEFAULT_BASE}
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

need_root() {
  [[ ${EUID:-0} -eq 0 ]] || die "Run as root (use sudo)."
}

normalize_dev() {
  local dev="$1"
  local resolved
  resolved="$(realpath -e "$dev" 2>/dev/null || true)"
  if [[ -n "$resolved" ]]; then
    echo "$resolved"
  else
    echo "$dev"
  fi
}

current_root_device() {
  local src
  src="$(findmnt -rn -o SOURCE / 2>/dev/null || true)"
  [[ -n "$src" ]] || die "Cannot determine root mount source."

  # findmnt output can include BTRFS subvol suffix, e.g. /dev/nvme1n1p1[/@]
  src="${src%%[*}"
  normalize_dev "$src"
}

other_pair_device() {
  local root_dev="$1"
  local a b
  a="$(normalize_dev "$PAIR_A")"
  b="$(normalize_dev "$PAIR_B")"

  if [[ "$root_dev" == "$a" ]]; then
    echo "$b"
  elif [[ "$root_dev" == "$b" ]]; then
    echo "$a"
  else
    die "Root device '$root_dev' is not in pair ($a <-> $b). Use --device."
  fi
}

is_mountpoint_exact() {
  local path="$1"
  local tgt
  tgt="$(findmnt -rn --target "$path" -o TARGET 2>/dev/null || true)"
  [[ "$tgt" == "$path" ]]
}

pick_shell() {
  local root="$1"
  if [[ -x "${root}/bin/bash" ]]; then
    echo "/bin/bash"
  elif [[ -x "${root}/usr/bin/bash" ]]; then
    echo "/usr/bin/bash"
  elif [[ -x "${root}/bin/sh" ]]; then
    echo "/bin/sh"
  else
    return 1
  fi
}

validate_btrfs_device() {
  local dev="$1"
  [[ -b "$dev" ]] || die "Block device not found: $dev"
  local fstype
  fstype="$(lsblk -no FSTYPE "$dev" 2>/dev/null | head -n1 || true)"
  [[ "$fstype" == "btrfs" ]] || die "Device is not btrfs: $dev (found: ${fstype:-unknown})"
}

join_opts() {
  local opts=""
  local o
  for o in "${OPTS_COMMON[@]}"; do
    if [[ -z "$opts" ]]; then
      opts="$o"
    else
      opts="${opts},${o}"
    fi
  done
  echo "$opts"
}

detect_chroot_root() {
  local base="$1"

  if [[ -d "${base}/@" ]]; then
    echo "${base}/@"
    return 0
  fi

  if [[ -d "${base}/root" ]]; then
    echo "${base}/root"
    return 0
  fi

  return 1
}

cmd_mount() {
  local base="$DEFAULT_BASE"
  local dev=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --base)
      base="${2:-}"
      shift 2
      ;;
    --device)
      dev="${2:-}"
      shift 2
      ;;
    *)
      die "Unknown option: $1"
      ;;
    esac
  done

  if [[ -z "$dev" ]]; then
    local root_dev
    root_dev="$(current_root_device)"
    dev="$(other_pair_device "$root_dev")"
  fi

  dev="$(normalize_dev "$dev")"
  validate_btrfs_device "$dev"

  mkdir -p "$base"

  if is_mountpoint_exact "$base"; then
    echo "$base is already mounted."
    findmnt -rn --target "$base" -o TARGET,SOURCE,FSTYPE,OPTIONS
    return 0
  fi

  local opts
  opts="$(join_opts)"
  mount -t btrfs -o "$opts" "$dev" "$base"
  findmnt -rn --target "$base" -o TARGET,SOURCE,FSTYPE,OPTIONS
}

cmd_umount() {
  local base="$DEFAULT_BASE"

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --base)
      base="${2:-}"
      shift 2
      ;;
    *)
      die "Unknown option: $1"
      ;;
    esac
  done

  if is_mountpoint_exact "$base"; then
    umount "$base"
    echo "Unmounted: $base"
  else
    echo "Not mounted: $base"
  fi
}

cmd_status() {
  local base="$DEFAULT_BASE"

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --base)
      base="${2:-}"
      shift 2
      ;;
    *)
      die "Unknown option: $1"
      ;;
    esac
  done

  local root_dev target_dev
  root_dev="$(current_root_device)"
  echo "Current root device: $root_dev"

  if target_dev="$(other_pair_device "$root_dev" 2>/dev/null)"; then
    echo "Auto target device : $target_dev"
  else
    echo "Auto target device : (unresolved from pair)"
  fi

  if is_mountpoint_exact "$base"; then
    findmnt -rn --target "$base" -o TARGET,SOURCE,FSTYPE,OPTIONS
  else
    echo "$base : (not mounted)"
  fi
}

cmd_chroot() {
  local base="$DEFAULT_BASE"
  local root=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --base)
      base="${2:-}"
      shift 2
      ;;
    --root)
      root="${2:-}"
      shift 2
      ;;
    *)
      die "Unknown option: $1"
      ;;
    esac
  done

  is_mountpoint_exact "$base" || die "Not mounted: $base (run: sudo ${SCRIPT_NAME} mount)"

  if [[ -z "$root" ]]; then
    root="$(detect_chroot_root "$base" 2>/dev/null || true)"
    [[ -n "$root" ]] || die "Cannot detect chroot root under $base (expected @ or root)."
  fi

  local shell
  shell="$(pick_shell "$root" 2>/dev/null || true)"
  [[ -n "$shell" ]] || die "No shell found inside chroot root: $root"

  mkdir -p "${root}/"{dev,proc,sys,run}
  mount --bind /dev "${root}/dev"
  mount --bind /proc "${root}/proc"
  mount --bind /sys "${root}/sys"
  mount --bind /run "${root}/run"

  echo "Entering chroot: $root ($shell)"
  set +e
  chroot "$root" "$shell" -l
  local rc=$?
  set -e

  umount "${root}/run" 2>/dev/null || true
  umount "${root}/sys" 2>/dev/null || true
  umount "${root}/proc" 2>/dev/null || true
  umount "${root}/dev" 2>/dev/null || true

  exit "$rc"
}

main() {
  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
  mount)
    need_root
    cmd_mount "$@"
    ;;
  umount | unmount)
    need_root
    cmd_umount "$@"
    ;;
  status)
    cmd_status "$@"
    ;;
  chroot)
    need_root
    cmd_chroot "$@"
    ;;
  help | -h | --help)
    usage
    ;;
  *)
    usage
    die "Unknown command: $cmd"
    ;;
  esac
}

main "$@"
