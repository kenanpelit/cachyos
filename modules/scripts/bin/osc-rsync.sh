#!/usr/bin/env bash
# ==============================================================================
# Script: osc-rsync.sh
# Description: Unified RSYNC Operations CLI for backup and transfer workflows
# Usage: osc-rsync.sh [command] [options]
# ==============================================================================
# Purpose:
#   Single entrypoint for rsync workflows that used to live in:
#   - osc-rsync.sh
#   - osc-rsync_backup.sh
#   - rsync-retry.sh
#   - rsync-tool.sh
#
# Core capabilities:
#   - Preset transfer modes: std | net | loc | web
#   - Retry loop with configurable retry count + delay
#   - Home backup command (source is always $HOME)
#   - Target health checks (basic network / disk checks)
#   - Profile management (save/load/list/show)
#   - Optional desktop notifications
#
# Quick examples:
#   osc-rsync.sh transfer -t web -s /repo -d user@host:/backup/repo --retries 20
#   osc-rsync.sh backup /mnt/backup --notify
#   osc-rsync.sh profile save my-fast-net
#
# Notes:
#   - Remote targets must use user@host:/path format.
#   - Exclude files are passed directly to rsync --exclude-from.
# =============================================================================
set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
VERSION="2.0.0"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/osc-rsync"
PROFILES_DIR="$CONFIG_DIR/profiles"
DEFAULT_PROFILE_FILE="$CONFIG_DIR/default.profile"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/osc-rsync"
MAX_RETRIES_HARD=200

MODE="std"
SOURCE=""
DEST=""
DELETE=0
RETRIES=1
RETRY_DELAY=5
EXCLUDE_FILE=""
BWLIMIT=0
CHECKSUM=0
SSH_PORT=22
RESUME=1
NOTIFY=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [[ ! -t 1 ]]; then
  RED=""
  GREEN=""
  YELLOW=""
  BLUE=""
  NC=""
fi

log_info() { printf "%b[INFO]%b %s\n" "$BLUE" "$NC" "$*"; }
log_ok() { printf "%b[OK]%b %s\n" "$GREEN" "$NC" "$*"; }
log_warn() { printf "%b[WARN]%b %s\n" "$YELLOW" "$NC" "$*" >&2; }
log_err() { printf "%b[ERR]%b %s\n" "$RED" "$NC" "$*" >&2; }
die() { log_err "$*"; exit 1; }

ensure_dirs() {
  mkdir -p "$CONFIG_DIR" "$PROFILES_DIR" "$STATE_DIR"
}

notify_msg() {
  local title="$1"
  local body="$2"
  if (( NOTIFY )) && command -v notify-send >/dev/null 2>&1; then
    notify-send "$title" "$body" || true
  fi
}

show_help() {
  cat <<USAGE
$SCRIPT_NAME v$VERSION

Usage:
  $SCRIPT_NAME transfer [options]
  $SCRIPT_NAME backup <target_dir> [options]
  $SCRIPT_NAME check <target>
  $SCRIPT_NAME profile <save|load|list|show> [name]
  $SCRIPT_NAME menu

Legacy form (still supported in this single script):
  $SCRIPT_NAME -t <std|net|loc|web> -s <source> -d <dest> [-r]

Transfer options:
  -t, --type <std|net|loc|web>   Transfer mode (default: std)
  -s, --source <path>
  -d, --dest <path>
  -r, --delete                   Delete extras on destination
      --retries <n>              Retry count (default: 1, max: $MAX_RETRIES_HARD)
      --retry-delay <sec>        Delay between retries (default: 5)
      --exclude-file <file>      rsync exclude file
      --bwlimit <kbps>           Bandwidth limit
      --checksum                 Use checksum compare
      --ssh-port <port>          SSH port for remote targets
      --no-resume                Disable append/append-verify
      --notify                   Desktop notifications

Backup options:
  backup <target_dir>            Source is always HOME
      --exclude-file <file>      Default: ~/.rsync-homedir-excludes (if exists)
      --retries <n>
      --retry-delay <sec>
      --notify

Examples:
  $SCRIPT_NAME transfer -t web -s /repo -d user@host:/backup/repo --retries 20
  $SCRIPT_NAME backup /mnt/backup --notify
  $SCRIPT_NAME profile save my-fast-net
USAGE
}

save_profile() {
  local name="$1"
  local file="$PROFILES_DIR/${name}.profile"
  cat >"$file" <<EOF_PROFILE
MODE=$MODE
DELETE=$DELETE
RETRIES=$RETRIES
RETRY_DELAY=$RETRY_DELAY
EXCLUDE_FILE=$EXCLUDE_FILE
BWLIMIT=$BWLIMIT
CHECKSUM=$CHECKSUM
SSH_PORT=$SSH_PORT
RESUME=$RESUME
NOTIFY=$NOTIFY
EOF_PROFILE
  log_ok "Profile saved: $file"
}

load_profile() {
  local name="$1"
  local file="$PROFILES_DIR/${name}.profile"
  [[ -f "$file" ]] || die "Profile not found: $name"

  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" == \#* ]] && continue
    case "$key" in
      MODE|EXCLUDE_FILE) printf -v "$key" '%s' "$value" ;;
      DELETE|RETRIES|RETRY_DELAY|BWLIMIT|CHECKSUM|SSH_PORT|RESUME|NOTIFY)
        printf -v "$key" '%s' "$value"
        ;;
    esac
  done <"$file"

  log_ok "Profile loaded: $name"
}

list_profiles() {
  local found=0
  for p in "$PROFILES_DIR"/*.profile; do
    [[ -e "$p" ]] || continue
    found=1
    basename "$p" .profile
  done
  (( found )) || echo "(no profiles)"
}

show_current_settings() {
  cat <<EOF_SETTINGS
MODE=$MODE
DELETE=$DELETE
RETRIES=$RETRIES
RETRY_DELAY=$RETRY_DELAY
EXCLUDE_FILE=$EXCLUDE_FILE
BWLIMIT=$BWLIMIT
CHECKSUM=$CHECKSUM
SSH_PORT=$SSH_PORT
RESUME=$RESUME
NOTIFY=$NOTIFY
EOF_SETTINGS
}

validate_mode() {
  case "$MODE" in
    std|net|loc|web) ;;
    *) die "Invalid mode: $MODE (use std|net|loc|web)" ;;
  esac
}

validate_retries() {
  [[ "$RETRIES" =~ ^[0-9]+$ ]] || die "retries must be numeric"
  [[ "$RETRY_DELAY" =~ ^[0-9]+$ ]] || die "retry-delay must be numeric"
  (( RETRIES >= 1 )) || die "retries must be >= 1"
  (( RETRIES <= MAX_RETRIES_HARD )) || die "retries must be <= $MAX_RETRIES_HARD"
}

validate_source_dest() {
  [[ -n "$SOURCE" ]] || die "source is required"
  [[ -n "$DEST" ]] || die "dest is required"
  [[ -e "$SOURCE" ]] || die "source not found: $SOURCE"
}

check_target_health() {
  local target="$1"

  if [[ "$target" == *:* ]]; then
    local host="${target%%:*}"
    log_info "Remote target detected: $host"
    if command -v ping >/dev/null 2>&1; then
      if ping -c 1 -W 2 "$host" >/dev/null 2>&1; then
        log_ok "Host reachable: $host"
      else
        log_warn "Host not reachable: $host"
      fi
    fi
    return 0
  fi

  local parent
  parent="$(dirname "$target")"
  [[ -d "$parent" ]] || die "destination parent does not exist: $parent"
  local free_mb
  free_mb="$(df -Pm "$parent" | awk 'NR==2 {print $4}')"
  log_info "Local free space ($parent): ${free_mb:-unknown}MB"
}

build_rsync_cmd() {
  local src="$1"
  local dst="$2"
  local -n out_cmd_ref=$3

  out_cmd_ref=(rsync)

  case "$MODE" in
    std)
      out_cmd_ref+=(-avzPh)
      ;;
    net)
      out_cmd_ref+=(-axAXvzE --compress-level=9 --numeric-ids)
      ;;
    loc)
      out_cmd_ref+=(-avxHAXW --no-compress --numeric-ids)
      ;;
    web)
      out_cmd_ref+=(-avzP --compress-level=9 --partial-dir=.rsync-partial --timeout=120)
      ;;
  esac

  out_cmd_ref+=(--info=progress2 --stats --partial)

  (( DELETE )) && out_cmd_ref+=(--delete)
  (( CHECKSUM )) && out_cmd_ref+=(--checksum)
  (( BWLIMIT > 0 )) && out_cmd_ref+=(--bwlimit="$BWLIMIT")
  (( RESUME )) && out_cmd_ref+=(--append --append-verify)

  if [[ -n "$EXCLUDE_FILE" ]]; then
    [[ -f "$EXCLUDE_FILE" ]] || die "exclude file not found: $EXCLUDE_FILE"
    out_cmd_ref+=(--exclude-from="$EXCLUDE_FILE")
  fi

  if [[ "$dst" == *:* ]]; then
    out_cmd_ref+=(-e "ssh -p $SSH_PORT -T -c aes128-gcm@openssh.com -o Compression=no -x")
  fi

  out_cmd_ref+=("$src" "$dst")
}

run_with_retries() {
  local -a cmd=("$@")
  local attempt=1
  local rc=0

  while (( attempt <= RETRIES )); do
    log_info "Attempt $attempt/$RETRIES"
    if "${cmd[@]}"; then
      return 0
    fi
    rc=$?
    if (( attempt == RETRIES )); then
      break
    fi
    log_warn "Transfer failed (rc=$rc). Retrying in ${RETRY_DELAY}s..."
    sleep "$RETRY_DELAY"
    attempt=$((attempt + 1))
  done

  return "$rc"
}

cmd_transfer() {
  validate_mode
  validate_retries
  validate_source_dest
  check_target_health "$DEST"

  local -a cmd=()
  build_rsync_cmd "$SOURCE" "$DEST" cmd

  log_info "Transfer: $SOURCE -> $DEST"
  log_info "Mode=$MODE Delete=$DELETE Retries=$RETRIES"

  notify_msg "RSYNC" "Transfer started: $SOURCE -> $DEST"
  if run_with_retries "${cmd[@]}"; then
    log_ok "Transfer completed"
    notify_msg "RSYNC" "Transfer completed"
  else
    local rc=$?
    log_err "Transfer failed (rc=$rc)"
    notify_msg "RSYNC" "Transfer failed (rc=$rc)"
    return "$rc"
  fi
}

cmd_backup() {
  local target="$1"
  [[ -d "$target" ]] || die "backup target not found: $target"

  SOURCE="$HOME"
  DEST="$target"
  MODE="std"
  DELETE=1
  validate_retries

  if [[ -z "$EXCLUDE_FILE" && -f "$HOME/.rsync-homedir-excludes" ]]; then
    EXCLUDE_FILE="$HOME/.rsync-homedir-excludes"
  fi

  local log_file="$STATE_DIR/backup-$(date +%Y%m%d_%H%M%S).log"
  local start_ts
  start_ts="$(date '+%Y-%m-%d %H:%M:%S')"

  notify_msg "Backup" "Backup started: $SOURCE -> $DEST"

  {
    echo "[$start_ts] Backup started: $SOURCE -> $DEST"
    cmd_transfer
    local end_ts
    end_ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$end_ts] Backup completed"
  } 2>&1 | tee -a "$log_file"

  log_ok "Backup log: $log_file"
}

cmd_check() {
  local target="$1"
  [[ -n "$target" ]] || die "check requires a target"
  check_target_health "$target"
}

cmd_profile() {
  local action="${1:-}"
  case "$action" in
    save)
      [[ -n "${2:-}" ]] || die "profile save <name>"
      save_profile "$2"
      ;;
    load)
      [[ -n "${2:-}" ]] || die "profile load <name>"
      load_profile "$2"
      ;;
    list)
      list_profiles
      ;;
    show)
      show_current_settings
      ;;
    *)
      die "profile usage: profile <save|load|list|show> [name]"
      ;;
  esac
}

menu() {
  while true; do
    echo
    echo "== osc-rsync menu =="
    echo "1) transfer"
    echo "2) backup"
    echo "3) check"
    echo "4) profile list"
    echo "5) profile load"
    echo "6) profile save"
    echo "q) quit"
    read -r -p "choice: " choice
    case "$choice" in
      1)
        read -r -p "mode (std/net/loc/web) [std]: " MODE
        MODE="${MODE:-std}"
        read -r -p "source: " SOURCE
        read -r -p "dest: " DEST
        read -r -p "delete extraneous files? (y/N): " yn
        [[ "${yn,,}" == "y" ]] && DELETE=1 || DELETE=0
        cmd_transfer
        ;;
      2)
        read -r -p "backup target dir: " target
        cmd_backup "$target"
        ;;
      3)
        read -r -p "target path/host: " target
        cmd_check "$target"
        ;;
      4)
        cmd_profile list
        ;;
      5)
        read -r -p "profile name: " name
        cmd_profile load "$name"
        ;;
      6)
        read -r -p "profile name: " name
        cmd_profile save "$name"
        ;;
      q|Q)
        break
        ;;
      *)
        log_warn "invalid choice"
        ;;
    esac
  done
}

parse_transfer_flags() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -t|--type)
        MODE="$2"; shift 2 ;;
      -s|--source)
        SOURCE="$2"; shift 2 ;;
      -d|--dest)
        DEST="$2"; shift 2 ;;
      -r|--delete)
        DELETE=1; shift ;;
      --retries)
        RETRIES="$2"; shift 2 ;;
      --retry-delay)
        RETRY_DELAY="$2"; shift 2 ;;
      --exclude-file)
        EXCLUDE_FILE="$2"; shift 2 ;;
      --bwlimit)
        BWLIMIT="$2"; shift 2 ;;
      --checksum)
        CHECKSUM=1; shift ;;
      --ssh-port)
        SSH_PORT="$2"; shift 2 ;;
      --notify)
        NOTIFY=1; shift ;;
      --no-resume)
        RESUME=0; shift ;;
      --profile)
        load_profile "$2"; shift 2 ;;
      -h|--help)
        show_help; exit 0 ;;
      --)
        shift; break ;;
      *)
        die "unknown transfer option: $1" ;;
    esac
  done
}

main() {
  if [[ $# -gt 0 ]]; then
    case "$1" in
      -h|--help)
        show_help
        exit 0
        ;;
    esac
  fi

  ensure_dirs

  if [[ -f "$DEFAULT_PROFILE_FILE" ]]; then
    while IFS='=' read -r key value; do
      [[ -z "$key" || "$key" == \#* ]] && continue
      case "$key" in
        MODE|EXCLUDE_FILE) printf -v "$key" '%s' "$value" ;;
        DELETE|RETRIES|RETRY_DELAY|BWLIMIT|CHECKSUM|SSH_PORT|RESUME|NOTIFY)
          printf -v "$key" '%s' "$value" ;;
      esac
    done <"$DEFAULT_PROFILE_FILE"
  fi

  if [[ $# -eq 0 ]]; then
    menu
    exit 0
  fi

  case "$1" in
    transfer)
      shift
      parse_transfer_flags "$@"
      cmd_transfer
      ;;
    backup)
      shift
      [[ -n "${1:-}" ]] || die "backup requires target_dir"
      local target="$1"
      shift
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --exclude-file) EXCLUDE_FILE="$2"; shift 2 ;;
          --retries) RETRIES="$2"; shift 2 ;;
          --retry-delay) RETRY_DELAY="$2"; shift 2 ;;
          --notify) NOTIFY=1; shift ;;
          -h|--help) show_help; exit 0 ;;
          *) die "unknown backup option: $1" ;;
        esac
      done
      cmd_backup "$target"
      ;;
    check)
      shift
      [[ -n "${1:-}" ]] || die "check requires target"
      cmd_check "$1"
      ;;
    profile)
      shift
      cmd_profile "$@"
      ;;
    menu)
      menu
      ;;
    -t|-s|-d|-r|--type|--source|--dest|--delete)
      parse_transfer_flags "$@"
      cmd_transfer
      ;;
    *)
      die "unknown command: $1 (use --help)"
      ;;
  esac
}

main "$@"
