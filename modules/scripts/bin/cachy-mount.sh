#!/usr/bin/env bash
# ==============================================================================
# Script: cachy-mount.sh
# Description: Dual-disk BTRFS helper to detect and mount other OS partitions.
# Usage: cachy-mount.sh [mount|umount|status|chroot] [options]
# ==============================================================================

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
if [[ "$SCRIPT_NAME" == "cachy-mount.sh" ]]; then
  SCRIPT_NAME="cachy-mount"
fi

DEFAULT_BASE="/cachy"

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
  auto target: btrfs root-like partition on the other disk
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

parent_disk_dev() {
  local dev="$1"
  local pk
  pk="$(lsblk -no PKNAME "$dev" 2>/dev/null | head -n1 || true)"
  [[ -n "$pk" ]] || return 1
  echo "/dev/$pk"
}

is_btrfs_device() {
  local dev="$1"
  local fstype
  fstype="$(lsblk -no FSTYPE "$dev" 2>/dev/null | head -n1 || true)"
  [[ "$fstype" == "btrfs" ]]
}

device_size_bytes() {
  local dev="$1"
  local size
  size="$(lsblk -bno SIZE "$dev" 2>/dev/null | head -n1 || true)"
  [[ "$size" =~ ^[0-9]+$ ]] || return 1
  echo "$size"
}

list_btrfs_partitions() {
  lsblk -pnr -o NAME,TYPE,FSTYPE 2>/dev/null | awk '$2=="part" && $3=="btrfs"{print $1}'
}

probe_os_tree_device() {
  local dev="$1"
  local tmp rc=1

  # Root-only hinting probe; status command can still run as normal user.
  [[ ${EUID:-0} -eq 0 ]] || return 1

  tmp="$(mktemp -d /tmp/cachy-mount.XXXXXX)"
  if mount -t btrfs -o ro,subvolid=5 "$dev" "$tmp" >/dev/null 2>&1; then
    if [[ -f "${tmp}/@/etc/os-release" || -f "${tmp}/root/etc/os-release" || -f "${tmp}/etc/os-release" ]]; then
      rc=0
    fi
    umount "$tmp" >/dev/null 2>&1 || true
  fi
  rmdir "$tmp" >/dev/null 2>&1 || true
  return "$rc"
}

current_root_device() {
  local src
  src="$(findmnt -rn -o SOURCE / 2>/dev/null || true)"
  [[ -n "$src" ]] || die "Cannot determine root mount source."

  # findmnt output can include BTRFS subvol suffix, e.g. /dev/nvme1n1p1[/@]
  src="${src%%[*}"
  normalize_dev "$src"
}

auto_target_device() {
  local root_dev="$1"
  local root_disk root_size
  local candidate candidate_disk candidate_size
  local score best_score best_dev
  local diff best_diff pct seen

  root_dev="$(normalize_dev "$root_dev")"
  root_disk="$(parent_disk_dev "$root_dev" 2>/dev/null || true)"
  root_size="$(device_size_bytes "$root_dev" 2>/dev/null || echo 0)"

  best_score=-1
  best_diff=9223372036854775807
  best_dev=""
  seen=0

  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    candidate="$(normalize_dev "$candidate")"
    [[ "$candidate" == "$root_dev" ]] && continue
    [[ -b "$candidate" ]] || continue

    seen=$((seen + 1))
    score=0
    diff=9223372036854775807

    candidate_disk="$(parent_disk_dev "$candidate" 2>/dev/null || true)"
    if [[ -n "$root_disk" && -n "$candidate_disk" && "$candidate_disk" != "$root_disk" ]]; then
      score=$((score + 100))
    fi

    candidate_size="$(device_size_bytes "$candidate" 2>/dev/null || echo 0)"
    if (( root_size > 0 && candidate_size > 0 )); then
      if (( candidate_size >= root_size )); then
        diff=$((candidate_size - root_size))
      else
        diff=$((root_size - candidate_size))
      fi
      pct=$((diff * 100 / root_size))
      if (( pct <= 5 )); then
        score=$((score + 30))
      elif (( pct <= 20 )); then
        score=$((score + 20))
      elif (( pct <= 50 )); then
        score=$((score + 10))
      fi
    fi

    if probe_os_tree_device "$candidate"; then
      score=$((score + 80))
    fi

    if (( score > best_score )); then
      best_score="$score"
      best_diff="$diff"
      best_dev="$candidate"
    elif (( score == best_score )); then
      if (( diff < best_diff )); then
        best_diff="$diff"
        best_dev="$candidate"
      elif (( diff == best_diff )) && [[ -n "$best_dev" && "$candidate" < "$best_dev" ]]; then
        best_dev="$candidate"
      fi
    fi
  done < <(list_btrfs_partitions)

  (( seen > 0 )) || die "No alternative btrfs partition found (root: $root_dev). Use --device."
  [[ -n "$best_dev" ]] || die "Cannot auto-select target btrfs device. Use --device."
  echo "$best_dev"
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
    dev="$(auto_target_device "$root_dev")"
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

  if target_dev="$(auto_target_device "$root_dev" 2>/dev/null)"; then
    echo "Auto target device : $target_dev"
  else
    echo "Auto target device : (unresolved)"
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
