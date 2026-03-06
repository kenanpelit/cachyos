#!/usr/bin/env bash
# ==============================================================================
# Script: osc-grub.sh
# Description: Unified GRUB helper for listing menu entries and theme cleanup.
# Usage: osc-grub.sh [menu|cleanup] [options]
# ==============================================================================

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
DEFAULT_GRUB_CFG="/boot/grub/grub.cfg"

MENU_SUDO_MODE="auto" # auto|always|never
MENU_PLAIN=false
MENU_CFG="$DEFAULT_GRUB_CFG"

CLEANUP_SUDO_MODE="auto" # auto|always|never
CLEANUP_DRY_RUN=false
CLEANUP_DIRS=(
  "/boot/theme"
  "/boot/grub/themes"
  "/boot/grub/fonts"
)

die() {
  echo "ERROR: $*" >&2
  exit 1
}

show_help() {
  cat <<EOF
Usage: ${SCRIPT_NAME} <menu|cleanup> [OPTIONS]

Subcommands:
  menu      List GRUB menu entries with stable index paths.
  cleanup   Remove GRUB theme-related directories.

menu options:
  -c, --config PATH   GRUB config file (default: ${DEFAULT_GRUB_CFG})
      --sudo          Always read with sudo
      --no-sudo       Never use sudo
      --plain         Print only menu lines (no header)

cleanup options:
      --sudo          Always remove with sudo
      --no-sudo       Never use sudo
      --dry-run       Show what would be removed

General options:
  -h, --help          Show this help

Examples:
  ${SCRIPT_NAME} menu
  ${SCRIPT_NAME} menu --sudo
  ${SCRIPT_NAME} menu -c /mnt/boot/grub/grub.cfg
  ${SCRIPT_NAME} cleanup
  ${SCRIPT_NAME} cleanup --sudo
  ${SCRIPT_NAME} cleanup --dry-run
EOF
}

show_menu_help() {
  cat <<EOF
Usage: ${SCRIPT_NAME} menu [OPTIONS] [GRUB_CFG]

Options:
  -c, --config PATH   GRUB config file (default: ${DEFAULT_GRUB_CFG})
      --sudo          Always read with sudo
      --no-sudo       Never use sudo
      --plain         Print only menu lines (no header)
  -h, --help          Show this help
EOF
}

show_cleanup_help() {
  cat <<EOF
Usage: ${SCRIPT_NAME} cleanup [OPTIONS]

Options:
      --sudo          Always remove with sudo
      --no-sudo       Never use sudo
      --dry-run       Show what would be removed
  -h, --help          Show this help
EOF
}

parse_menu_args() {
  while (($#)); do
    case "$1" in
      -c|--config)
        (($# >= 2)) || die "--config requires a path"
        MENU_CFG="$2"
        shift 2
        ;;
      --sudo)
        MENU_SUDO_MODE="always"
        shift
        ;;
      --no-sudo)
        MENU_SUDO_MODE="never"
        shift
        ;;
      --plain)
        MENU_PLAIN=true
        shift
        ;;
      -h|--help)
        show_menu_help
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        die "Unknown menu option: $1"
        ;;
      *)
        MENU_CFG="$1"
        shift
        ;;
    esac
  done
}

menu_info() {
  "$MENU_PLAIN" || echo "$*"
}

run_menu_parser() {
  local reader="$1"
  local awk_script='
    BEGIN{depth=0;sp=0}
    function path(d,leaf, i,p){p=""; for(i=0;i<d;i++) p=p (i?">":"") cur[i]; return d ? p ">" leaf : leaf}
    {
      kind=""; title=""
      if (match($0,/^[[:space:]]*(menuentry|submenu)[[:space:]]+\047([^\047]+)\047/,m)) {kind=m[1]; title=m[2]}
      else if (match($0,/^[[:space:]]*(menuentry|submenu)[[:space:]]+"([^"]+)"/,m)) {kind=m[1]; title=m[2]}
      if (kind!="") {
        idx=cnt[depth]++; cur[depth]=idx
        printf "%-8s : %s%s\n", path(depth,idx), (kind=="submenu"?"[submenu] ":""), title
        stack[++sp]=kind
        if (kind=="submenu") {depth++; cnt[depth]=0}
        next
      }
      if ($0 ~ /^[[:space:]]*}[[:space:]]*$/ && sp>0) {
        if (stack[sp--]=="submenu" && depth>0) depth--
      }
    }'

  if [[ "$reader" == "sudo" ]]; then
    sudo awk "$awk_script" "$MENU_CFG"
  else
    awk "$awk_script" "$MENU_CFG"
  fi
}

cmd_menu() {
  parse_menu_args "$@"

  command -v awk >/dev/null 2>&1 || die "awk not found"
  [[ -e "$MENU_CFG" ]] || die "GRUB config not found: $MENU_CFG"

  local reader="direct"
  case "$MENU_SUDO_MODE" in
    always)
      command -v sudo >/dev/null 2>&1 || die "sudo not found"
      reader="sudo"
      ;;
    never)
      [[ -r "$MENU_CFG" ]] || die "No read permission for: $MENU_CFG (rerun with --sudo)"
      ;;
    auto)
      if [[ ! -r "$MENU_CFG" ]]; then
        command -v sudo >/dev/null 2>&1 || die "No read permission for: $MENU_CFG and sudo not found"
        reader="sudo"
      fi
      ;;
    *)
      die "Invalid sudo mode: $MENU_SUDO_MODE"
      ;;
  esac

  menu_info "GRUB menu: $MENU_CFG"
  menu_info "reader: $reader"
  menu_info "----------------------------------------"
  run_menu_parser "$reader"
}

parse_cleanup_args() {
  while (($#)); do
    case "$1" in
      --sudo)
        CLEANUP_SUDO_MODE="always"
        shift
        ;;
      --no-sudo)
        CLEANUP_SUDO_MODE="never"
        shift
        ;;
      --dry-run)
        CLEANUP_DRY_RUN=true
        shift
        ;;
      -h|--help)
        show_cleanup_help
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        die "Unknown cleanup option: $1"
        ;;
      *)
        die "cleanup does not accept positional args: $1"
        ;;
    esac
  done
}

cmd_cleanup() {
  parse_cleanup_args "$@"

  local runner="direct"
  case "$CLEANUP_SUDO_MODE" in
    always)
      command -v sudo >/dev/null 2>&1 || die "sudo not found"
      runner="sudo"
      ;;
    never)
      [[ $EUID -eq 0 ]] || die "cleanup --no-sudo requires root"
      ;;
    auto)
      if [[ $EUID -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 || die "cleanup requires root or sudo"
        runner="sudo"
      fi
      ;;
    *)
      die "Invalid sudo mode: $CLEANUP_SUDO_MODE"
      ;;
  esac

  echo "Starting GRUB theme cleanup..."
  echo "runner: $runner"
  echo "----------------------------------------"

  local dir
  for dir in "${CLEANUP_DIRS[@]}"; do
    if [[ -d "$dir" ]]; then
      if "$CLEANUP_DRY_RUN"; then
        echo "[dry-run] would remove: $dir"
      else
        echo "Removing: $dir"
        if [[ "$runner" == "sudo" ]]; then
          sudo rm -rf -- "$dir"
        else
          rm -rf -- "$dir"
        fi
        echo "✓ removed: $dir"
      fi
    else
      echo "! missing, skipped: $dir"
    fi
  done

  echo "----------------------------------------"
  "$CLEANUP_DRY_RUN" && echo "Dry-run completed." || echo "Cleanup completed successfully."
}

main() {
  local cmd="${1:-menu}"
  case "$cmd" in
    -*)
      cmd_menu "$@"
      ;;
    menu)
      shift || true
      cmd_menu "$@"
      ;;
    cleanup)
      shift || true
      cmd_cleanup "$@"
      ;;
    -h|--help|help)
      show_help
      ;;
    *)
      die "Unknown subcommand: $cmd (use: menu|cleanup)"
      ;;
  esac
}

main "$@"
