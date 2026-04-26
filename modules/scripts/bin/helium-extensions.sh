#!/usr/bin/env bash
# ==============================================================================
# Script: helium-extensions.sh
# Description: Manual Helium extension installer from a donor isolated profile.
# Usage: helium-extensions.sh [missing|all|status|list|interactive] [options]
# ==============================================================================

set -uo pipefail

readonly STORE_URL="https://chromewebstore.google.com/detail"
readonly SCRIPT_VERSION="1.0"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

ISOLATED_ROOT="${HELIUM_ISOLATED_ROOT:-$HOME/.helium/isolated}"
SOURCE_PROFILE="${HELIUM_EXTENSIONS_SOURCE_PROFILE:-Kenp}"
TARGET_PROFILE="${HELIUM_EXTENSIONS_TARGET_PROFILE:-Kenp}"
SOURCE_DIR="${HELIUM_EXTENSIONS_SOURCE_DIR:-}"
TARGET_DIR="${HELIUM_EXTENSIONS_TARGET_DIR:-}"
OPEN_DELAY="${HELIUM_EXTENSIONS_OPEN_DELAY:-1.5}"

declare -a EXTENSIONS=()

usage() {
  cat <<EOF
Usage: helium-extensions [command] [options]

Commands:
  missing       Open only extensions missing from the target profile
  all           Open every donor extension in the target Helium profile
  status        Show target profile install status
  list          List extensions discovered from the source profile
  interactive   Pick extensions interactively

Options:
  --source-profile NAME   Donor profile name (default: ${SOURCE_PROFILE})
  --target-profile NAME   Target profile name (default: ${TARGET_PROFILE})
  --source-dir DIR        Donor Extensions directory override
  --target-dir DIR        Target Extensions directory override
  --delay SECONDS         Delay between opened Web Store pages (default: ${OPEN_DELAY})
  -h, --help              Show this help
EOF
}

print_banner() {
  echo -e "${CYAN}${BOLD}"
  cat <<EOF
Helium Extensions Installer v${SCRIPT_VERSION}
Source: ${SOURCE_PROFILE}
Target: ${TARGET_PROFILE}
EOF
  echo -e "${NC}"
}

print_separator() {
  echo -e "${CYAN}===================================================================${NC}"
}

die() {
  echo -e "${RED}ERROR:${NC} $*" >&2
  exit 1
}

resolve_extensions_dir() {
  local profile="$1"
  local override="$2"
  local root="${ISOLATED_ROOT}/${profile}"
  local candidate=""

  if [[ -n "$override" ]]; then
    printf '%s\n' "$override"
    return 0
  fi

  if [[ -d "$root" ]]; then
    while IFS= read -r candidate; do
      [[ -n "$candidate" ]] || continue
      printf '%s\n' "$candidate"
      return 0
    done < <(find "$root" -mindepth 2 -maxdepth 2 -type d -name Extensions 2>/dev/null | sort)
  fi

  printf '%s\n' "${root}/Default/Extensions"
}

latest_version() {
  local ext_root="$1"
  find "$ext_root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort -V | tail -n1
}

message_from_locale() {
  local version_dir="$1"
  local key="$2"
  local locale_file=""
  local value=""

  for locale_file in \
    "${version_dir}/_locales/en/messages.json" \
    "${version_dir}/_locales/en_US/messages.json" \
    "${version_dir}/_locales/tr/messages.json" \
    "${version_dir}"/_locales/*/messages.json; do
    [[ -f "$locale_file" ]] || continue
    value="$(jq -r --arg key "$key" '.[$key].message // empty' "$locale_file" 2>/dev/null || true)"
    if [[ -n "$value" && "$value" != "null" ]]; then
      printf '%s\n' "$value"
      return 0
    fi
  done

  return 1
}

extension_name() {
  local ext_id="$1"
  local ext_root="$2"
  local version=""
  local version_dir=""
  local manifest=""
  local raw_name=""
  local msg_key=""

  version="$(latest_version "$ext_root")"
  [[ -n "$version" ]] || {
    printf '%s\n' "$ext_id"
    return 0
  }

  version_dir="${ext_root}/${version}"
  manifest="${version_dir}/manifest.json"
  [[ -f "$manifest" ]] || {
    printf '%s\n' "$ext_id"
    return 0
  }

  raw_name="$(jq -r '.name // empty' "$manifest" 2>/dev/null || true)"
  if [[ "$raw_name" =~ ^__MSG_(.+)__$ ]]; then
    msg_key="${BASH_REMATCH[1]}"
    message_from_locale "$version_dir" "$msg_key" || printf '%s\n' "$ext_id"
    return 0
  fi

  [[ -n "$raw_name" && "$raw_name" != "null" ]] && printf '%s\n' "$raw_name" || printf '%s\n' "$ext_id"
}

load_extensions() {
  local ext_dir="$1"
  local ext_root=""
  local ext_id=""
  local ext_name=""

  EXTENSIONS=()

  [[ -d "$ext_dir" ]] || die "source Extensions directory not found: $ext_dir"
  command -v jq >/dev/null 2>&1 || die "jq is required"

  while IFS= read -r ext_root; do
    [[ -d "$ext_root" ]] || continue
    ext_id="$(basename "$ext_root")"
    [[ "$ext_id" =~ ^[a-z]{32}$ ]] || continue
    ext_name="$(extension_name "$ext_id" "$ext_root")"
    EXTENSIONS+=("${ext_id}"$'\t'"${ext_name}")
  done < <(find "$ext_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

  ((${#EXTENSIONS[@]} > 0)) || die "no extensions found in: $ext_dir"
}

extension_url() {
  printf '%s/%s\n' "$STORE_URL" "$1"
}

is_installed() {
  local target_dir="$1"
  local ext_id="$2"
  [[ -d "${target_dir}/${ext_id}" ]]
}

installed_version() {
  local target_dir="$1"
  local ext_id="$2"
  latest_version "${target_dir}/${ext_id}"
}

open_extension() {
  local profile="$1"
  local ext_id="$2"
  local ext_name="$3"
  local url=""

  url="$(extension_url "$ext_id")"
  echo -e "${BLUE}OPEN${NC} ${YELLOW}${ext_name}${NC}"
  echo -e "     ${CYAN}${url}${NC}"

  if command -v profile_helium >/dev/null 2>&1; then
    profile_helium "$profile" "$url" >/dev/null 2>&1 &
  elif command -v helium-browser >/dev/null 2>&1; then
    helium-browser "$url" >/dev/null 2>&1 &
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 &
  else
    echo -e "     ${RED}No browser command found; open manually.${NC}"
    return 1
  fi

  sleep "$OPEN_DELAY"
}

install_entries() {
  local mode="$1"
  local source_dir="$2"
  local target_dir="$3"
  local total=0
  local opened=0
  local skipped=0
  local entry=""
  local ext_id=""
  local ext_name=""
  local version=""

  load_extensions "$source_dir"
  total="${#EXTENSIONS[@]}"

  echo -e "${BOLD}Source:${NC} ${source_dir}"
  echo -e "${BOLD}Target:${NC} ${target_dir}"
  echo ""

  for entry in "${EXTENSIONS[@]}"; do
    ext_id="${entry%%$'\t'*}"
    ext_name="${entry#*$'\t'}"

    if [[ "$mode" == "missing" ]] && is_installed "$target_dir" "$ext_id"; then
      version="$(installed_version "$target_dir" "$ext_id")"
      echo -e "${GREEN}SKIP${NC} ${ext_name} ${CYAN}(v${version:-?})${NC}"
      ((skipped++))
      continue
    fi

    open_extension "$TARGET_PROFILE" "$ext_id" "$ext_name"
    ((opened++))
  done

  echo ""
  print_separator
  echo -e "${BOLD}Total:${NC} ${total}  ${GREEN}Opened:${NC} ${opened}  ${YELLOW}Skipped:${NC} ${skipped}"
  print_separator
}

show_status() {
  local source_dir="$1"
  local target_dir="$2"
  local entry=""
  local ext_id=""
  local ext_name=""
  local installed=0
  local version=""

  load_extensions "$source_dir"

  echo -e "${BOLD}Source:${NC} ${source_dir}"
  echo -e "${BOLD}Target:${NC} ${target_dir}"
  echo ""

  for entry in "${EXTENSIONS[@]}"; do
    ext_id="${entry%%$'\t'*}"
    ext_name="${entry#*$'\t'}"
    printf "%-42s " "$ext_name"
    if is_installed "$target_dir" "$ext_id"; then
      version="$(installed_version "$target_dir" "$ext_id")"
      echo -e "${GREEN}installed${NC} ${CYAN}(v${version:-?})${NC}"
      ((installed++))
    else
      echo -e "${RED}missing${NC}"
    fi
  done

  echo ""
  echo -e "${BOLD}Installed:${NC} ${installed}/${#EXTENSIONS[@]}"
}

show_list() {
  local source_dir="$1"
  local entry=""
  local ext_id=""
  local ext_name=""

  load_extensions "$source_dir"

  printf "${GREEN}%-42s ${BLUE}%-32s${NC}\n" "Extension" "ID"
  print_separator
  for entry in "${EXTENSIONS[@]}"; do
    ext_id="${entry%%$'\t'*}"
    ext_name="${entry#*$'\t'}"
    printf "%-42s ${BLUE}%-32s${NC}\n" "$ext_name" "$ext_id"
  done
}

interactive_install() {
  local source_dir="$1"
  local target_dir="$2"
  local entry=""
  local ext_id=""
  local ext_name=""
  local status=""
  local selection=""
  local -a selected=()
  local -a parts=()
  local part=""
  local start=""
  local end=""
  local n=0
  local idx=0
  local i=1

  load_extensions "$source_dir"

  for entry in "${EXTENSIONS[@]}"; do
    ext_id="${entry%%$'\t'*}"
    ext_name="${entry#*$'\t'}"
    if is_installed "$target_dir" "$ext_id"; then
      status="${GREEN}[installed]${NC}"
    else
      status="${RED}[missing]${NC}"
    fi
    printf "${CYAN}%2d)${NC} %-42s %s\n" "$i" "$ext_name" "$status"
    ((i++))
  done

  echo ""
  echo "Selection examples: 5, 1,3,5, 1-5, all"
  read -r -p "Selection: " selection

  if [[ "$selection" == "all" ]]; then
    install_entries all "$source_dir" "$target_dir"
    return
  fi

  IFS=',' read -ra parts <<<"$selection"
  for part in "${parts[@]}"; do
    part="${part//[[:space:]]/}"
    if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      start="${BASH_REMATCH[1]}"
      end="${BASH_REMATCH[2]}"
      for ((n = start; n <= end; n++)); do
        selected+=("$n")
      done
    elif [[ "$part" =~ ^[0-9]+$ ]]; then
      selected+=("$part")
    fi
  done

  for n in "${selected[@]}"; do
    if ((n < 1 || n > ${#EXTENSIONS[@]})); then
      continue
    fi
    idx=$((n - 1))
    entry="${EXTENSIONS[$idx]}"
    ext_id="${entry%%$'\t'*}"
    ext_name="${entry#*$'\t'}"
    open_extension "$TARGET_PROFILE" "$ext_id" "$ext_name"
  done
}

show_menu() {
  echo ""
  print_separator
  echo -e "${YELLOW}${BOLD}Install options:${NC}"
  print_separator
  echo -e "${CYAN}1)${NC} Open all donor extensions"
  echo -e "${CYAN}2)${NC} Open only missing extensions"
  echo -e "${CYAN}3)${NC} Show target status"
  echo -e "${CYAN}4)${NC} List donor extensions"
  echo -e "${CYAN}5)${NC} Interactive selection"
  echo -e "${CYAN}0)${NC} Exit"
  print_separator
  echo ""
}

parse_args() {
  COMMAND="menu"

  while (($#)); do
    case "$1" in
      missing|install-missing) COMMAND="missing"; shift ;;
      all|install-all) COMMAND="all"; shift ;;
      status) COMMAND="status"; shift ;;
      list) COMMAND="list"; shift ;;
      interactive|select) COMMAND="interactive"; shift ;;
      --source-profile)
        SOURCE_PROFILE="${2:-}"
        [[ -n "$SOURCE_PROFILE" ]] || die "--source-profile requires a value"
        shift 2
        ;;
      --target-profile|--profile)
        TARGET_PROFILE="${2:-}"
        [[ -n "$TARGET_PROFILE" ]] || die "--target-profile requires a value"
        shift 2
        ;;
      --source-dir)
        SOURCE_DIR="${2:-}"
        [[ -n "$SOURCE_DIR" ]] || die "--source-dir requires a value"
        shift 2
        ;;
      --target-dir)
        TARGET_DIR="${2:-}"
        [[ -n "$TARGET_DIR" ]] || die "--target-dir requires a value"
        shift 2
        ;;
      --delay)
        OPEN_DELAY="${2:-}"
        [[ -n "$OPEN_DELAY" ]] || die "--delay requires a value"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
  done
}

main() {
  local choice=""

  parse_args "$@"

  SOURCE_DIR="$(resolve_extensions_dir "$SOURCE_PROFILE" "$SOURCE_DIR")"
  TARGET_DIR="$(resolve_extensions_dir "$TARGET_PROFILE" "$TARGET_DIR")"

  print_banner

  case "$COMMAND" in
    missing) install_entries missing "$SOURCE_DIR" "$TARGET_DIR" ;;
    all) install_entries all "$SOURCE_DIR" "$TARGET_DIR" ;;
    status) show_status "$SOURCE_DIR" "$TARGET_DIR" ;;
    list) show_list "$SOURCE_DIR" ;;
    interactive) interactive_install "$SOURCE_DIR" "$TARGET_DIR" ;;
    menu)
      while true; do
        show_menu
        read -r -p "Choice: " choice
        case "$choice" in
          1) install_entries all "$SOURCE_DIR" "$TARGET_DIR" ;;
          2) install_entries missing "$SOURCE_DIR" "$TARGET_DIR" ;;
          3) show_status "$SOURCE_DIR" "$TARGET_DIR" ;;
          4) show_list "$SOURCE_DIR" ;;
          5) interactive_install "$SOURCE_DIR" "$TARGET_DIR" ;;
          0) exit 0 ;;
          *) echo -e "${RED}Invalid choice${NC}" ;;
        esac
      done
      ;;
  esac
}

main "$@"
