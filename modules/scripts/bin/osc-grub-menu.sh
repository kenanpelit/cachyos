#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
GRUB_CFG="/boot/grub/grub.cfg"
SUDO_MODE="auto" # auto|always|never
PLAIN=false

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS] [GRUB_CFG]

List GRUB menu entries with stable index paths.

Options:
  -c, --config PATH   GRUB config file (default: ${GRUB_CFG})
      --sudo          Always read with sudo
      --no-sudo       Never use sudo
      --plain         Print only menu lines (no header)
  -h, --help          Show this help

Examples:
  ${SCRIPT_NAME}
  ${SCRIPT_NAME} --sudo
  ${SCRIPT_NAME} -c /mnt/boot/grub/grub.cfg
  ${SCRIPT_NAME} /boot/grub/grub.cfg
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

info() {
  "$PLAIN" || echo "$*"
}

parse_args() {
  while (($#)); do
    case "$1" in
      -c|--config)
        (($# >= 2)) || die "--config requires a path"
        GRUB_CFG="$2"
        shift 2
        ;;
      --sudo)
        SUDO_MODE="always"
        shift
        ;;
      --no-sudo)
        SUDO_MODE="never"
        shift
        ;;
      --plain)
        PLAIN=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        die "Unknown option: $1 (use --help)"
        ;;
      *)
        GRUB_CFG="$1"
        shift
        ;;
    esac
  done
}

run_menu_parser() {
  local reader="$1"

  if [[ "$reader" == "sudo" ]]; then
    sudo awk '
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
      }' "$GRUB_CFG"
  else
    awk '
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
      }' "$GRUB_CFG"
  fi
}

main() {
  parse_args "$@"

  command -v awk >/dev/null 2>&1 || die "awk not found"
  [[ -e "$GRUB_CFG" ]] || die "GRUB config not found: $GRUB_CFG"

  local reader="direct"
  case "$SUDO_MODE" in
    always)
      command -v sudo >/dev/null 2>&1 || die "sudo not found"
      reader="sudo"
      ;;
    never)
      [[ -r "$GRUB_CFG" ]] || die "No read permission for: $GRUB_CFG (rerun with --sudo)"
      reader="direct"
      ;;
    auto)
      if [[ -r "$GRUB_CFG" ]]; then
        reader="direct"
      else
        command -v sudo >/dev/null 2>&1 || die "No read permission for: $GRUB_CFG and sudo not found"
        reader="sudo"
      fi
      ;;
    *)
      die "Invalid sudo mode: $SUDO_MODE"
      ;;
  esac

  info "GRUB menu: $GRUB_CFG"
  info "reader: $reader"
  info "----------------------------------------"
  run_menu_parser "$reader"
}

main "$@"
