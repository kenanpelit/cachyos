#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if git -C "${SCRIPT_DIR}" rev-parse --show-toplevel >/dev/null 2>&1; then
  REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel)"
else
  REPO_ROOT="${SCRIPT_DIR}"
fi

readonly REPO_ROOT
readonly HOST_FILE="${REPO_ROOT}/hosts/hay.yaml"
readonly BASE_DESKTOP_PACKAGES_FILE="${REPO_ROOT}/modules/base/packages-desktop.yaml"
readonly GNOME_MODULE_FILE="${REPO_ROOT}/modules/gnome/packages.yaml"
readonly SYSTEM_PACKAGES_FILE="${REPO_ROOT}/modules/system-packages-hay/packages.yaml"
readonly COSMIC_MODULE_DIR="${REPO_ROOT}/modules/cosmic"
readonly LIDM_INSTALL_SCRIPT="${REPO_ROOT}/modules/lidm/scripts/install.sh"

DRY_RUN=0
ASSUME_YES=0
REPO_ONLY=0
SYSTEM_ONLY=0
TARGET=""

readonly -a COSMIC_PACKAGES=(
  cosmic-app-library
  cosmic-applets
  cosmic-bg
  cosmic-comp
  cosmic-files
  cosmic-greeter
  cosmic-icon-theme
  cosmic-idle
  cosmic-initial-setup
  cosmic-launcher
  cosmic-notifications
  cosmic-osd
  cosmic-panel
  cosmic-player
  cosmic-randr
  cosmic-screenshot
  cosmic-session
  cosmic-settings
  cosmic-settings-daemon
  cosmic-store
  cosmic-terminal
  cosmic-text-editor
  cosmic-wallpapers
  cosmic-workspaces
  xdg-desktop-portal-cosmic
)

readonly -a COSMIC_REPO_LINES=(
  "- cosmic-app-library"
  "- cosmic-applets"
  "- cosmic-bg"
  "- cosmic-comp"
  "- cosmic-files"
  "- cosmic-greeter"
  "- cosmic-icon-theme"
  "- cosmic-idle"
  "- cosmic-initial-setup"
  "- cosmic-launcher"
  "- cosmic-notifications"
  "- cosmic-osd"
  "- cosmic-panel"
  "- cosmic-player"
  "- cosmic-randr"
  "- cosmic-screenshot"
  "- cosmic-session"
  "- cosmic-settings"
  "- cosmic-settings-daemon"
  "- cosmic-store"
  "- cosmic-terminal"
  "- cosmic-text-editor"
  "- cosmic-wallpapers"
  "- cosmic-workspaces"
  "- xdg-desktop-portal-cosmic"
)

readonly -a GNOME_REMOVE_PACKAGES=(
  gdm
  gnome-session
  gnome-shell
  gnome-control-center
  gnome-tweaks
  baobab
  decibels
  dconf-editor
  eog
  epiphany
  evince
  file-roller
  gedit
  gnome-calculator
  gnome-calendar
  gnome-characters
  gnome-clocks
  gnome-connections
  gnome-console
  gnome-contacts
  gnome-disk-utility
  gnome-font-viewer
  gnome-logs
  gnome-maps
  gnome-music
  gnome-screenshot
  gnome-software
  gnome-system-monitor
  gnome-terminal
  gnome-text-editor
  gnome-weather
  loupe
  papers
  seahorse
  showtime
  simple-scan
  snapshot
  sushi
  totem
  gnome-extensions-cli
  gnome-monitor-config-git
  gnome-nettool
  gnome-tour
  gnome-usage
  gnome-user-docs
  gnome-user-share
  gnome-remote-desktop
  gnome-power-manager
  gnome-backgrounds
  gnome-color-manager
  gnome-menus
  grilo-plugins
  orca
  rygel
  tecla
  yelp
)

readonly -a GNOME_MODULE_REMOVE_LINES=(
  "  - gnome-shell"
  "  - gnome-control-center"
  "  - gnome-tweaks"
  "  - gnome-terminal"
  "  - gnome-text-editor"
  "  - gnome-calculator"
  "  - gnome-calendar"
  "  - gnome-characters"
  "  - gnome-clocks"
  "  - gnome-contacts"
  "  - gnome-system-monitor"
  "  - gnome-disk-utility"
  "  - gnome-font-viewer"
  "  - gnome-logs"
  "  - gnome-maps"
  "  - gnome-music"
  "  - gnome-weather"
  "  - gnome-screenshot"
  "  - eog"
  "  - loupe"
  "  - totem"
  "  - showtime"
  "  - decibels"
  "  - file-roller"
  "  - seahorse"
  "  - sushi"
  "  - baobab"
  "  - dconf-editor"
)

readonly -a GNOME_REPO_REMOVE_LINES=(
  "- gdm"
  "- baobab"
  "- decibels"
  "- eog"
  "- epiphany"
  "- evince"
  "- file-roller"
  "- gedit"
  "- gnome-backgrounds"
  "- gnome-color-manager"
  "- gnome-control-center"
  "- gnome-extensions-cli"
  "- gnome-menus"
  "- gnome-nettool"
  "- gnome-power-manager"
  "- gnome-remote-desktop"
  "- gnome-session"
  "- gnome-shell"
  "- gnome-tour"
  "- gnome-tweaks"
  "- gnome-usage"
  "- gnome-user-docs"
  "- gnome-user-share"
  "- gnome-calculator"
  "- gnome-calendar"
  "- gnome-characters"
  "- gnome-clocks"
  "- gnome-connections"
  "- gnome-console"
  "- gnome-contacts"
  "- gnome-disk-utility"
  "- gnome-font-viewer"
  "- gnome-logs"
  "- gnome-maps"
  "- gnome-music"
  "- gnome-screenshot"
  "- gnome-software"
  "- gnome-system-monitor"
  "- gnome-terminal"
  "- gnome-text-editor"
  "- gnome-weather"
  "- grilo-plugins"
  "- loupe"
  "- orca"
  "- papers"
  "- rygel"
  "- showtime"
  "- simple-scan"
  "- snapshot"
  "- sushi"
  "- tecla"
  "- totem"
  "- yelp"
)

readonly -a GNOME_BASE_REPO_REMOVE_LINES=(
  "  - gnome-monitor-config-git"
)

usage() {
  cat <<'EOF'
Usage:
  cleanup.sh [--dry-run] [--yes] [--repo-only|--system-only] cosmic
  cleanup.sh [--dry-run] [--yes] [--repo-only|--system-only] gnome

Targets:
  cosmic  Remove COSMIC packages, clean repo package lists, and remove modules/cosmic.
  gnome   Switch GDM to LiDM, remove GNOME packages that were cleaned manually,
          keep nautilus + xdg-desktop-portal-gnome for screen sharing, and
          update repo files accordingly.

Options:
  --dry-run     Print planned commands and file edits without changing anything.
  --yes, -y     Skip the top-level confirmation prompt and pass --noconfirm to pacman.
  --repo-only   Only edit repo files; do not touch system packages or services.
  --system-only Only remove system packages/services; do not edit repo files.
  --help, -h    Show this help.
EOF
}

log() {
  printf '==> %s\n' "$*"
}

warn() {
  printf 'WARNING: %s\n' "$*" >&2
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

run_cmd() {
  if (( DRY_RUN )); then
    printf '+'
    for arg in "$@"; do
      printf ' %q' "${arg}"
    done
    printf '\n'
    return 0
  fi
  "$@"
}

run_root() {
  if (( DRY_RUN )); then
    printf '+'
    if (( EUID != 0 )); then
      printf ' sudo'
    fi
    for arg in "$@"; do
      printf ' %q' "${arg}"
    done
    printf '\n'
    return 0
  fi

  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

confirm() {
  local prompt="$1"
  if (( DRY_RUN || ASSUME_YES )); then
    return 0
  fi
  read -r -p "${prompt} [y/N] " reply
  [[ "${reply}" =~ ^[Yy]$ ]]
}

git_available() {
  git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

stage_paths() {
  if ! git_available; then
    return 0
  fi
  run_cmd git -C "${REPO_ROOT}" add -- "$@"
}

remove_repo_path() {
  local path="$1"

  if [[ ! -e "${path}" ]]; then
    return 0
  fi

  if git_available && git -C "${REPO_ROOT}" ls-files -- "${path}" | grep -q .; then
    run_cmd git -C "${REPO_ROOT}" rm -r -f -- "${path}"
  else
    run_cmd rm -rf -- "${path}"
  fi
}

remove_exact_lines() {
  local file="$1"
  shift

  [[ -f "${file}" ]] || die "Missing file: ${file}"

  if (( DRY_RUN )); then
    log "Would edit ${file}"
    for line in "$@"; do
      printf '  - remove: %s\n' "${line}"
    done
    return 0
  fi

  python3 - "$file" "$@" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
needles = set(sys.argv[2:])
text = path.read_text()
lines = text.splitlines()
new_lines = [line for line in lines if line not in needles]

if lines != new_lines:
    path.write_text("\n".join(new_lines) + ("\n" if text.endswith("\n") else ""))
PY
}

replace_exact_line() {
  local file="$1"
  local old_line="$2"
  local new_line="$3"

  [[ -f "${file}" ]] || die "Missing file: ${file}"

  if (( DRY_RUN )); then
    log "Would edit ${file}"
    printf '  - replace: %s\n' "${old_line}"
    printf '  - with   : %s\n' "${new_line}"
    return 0
  fi

  python3 - "$file" "$old_line" "$new_line" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
old_line = sys.argv[2]
new_line = sys.argv[3]
text = path.read_text()
lines = text.splitlines()
changed = False

for idx, line in enumerate(lines):
    if line == old_line:
        lines[idx] = new_line
        changed = True

if changed:
    path.write_text("\n".join(lines) + ("\n" if text.endswith("\n") else ""))
PY
}

package_installed() {
  pacman -Qq "$1" >/dev/null 2>&1
}

remove_installed_packages() {
  local -a installed=()
  local pkg
  local -a cmd=(pacman -Rns)

  for pkg in "$@"; do
    if package_installed "${pkg}"; then
      installed+=("${pkg}")
    fi
  done

  if (( ${#installed[@]} == 0 )); then
    log "No matching installed packages to remove."
    return 0
  fi

  if (( ASSUME_YES )); then
    cmd+=(--noconfirm)
  fi
  cmd+=("${installed[@]}")

  log "Removing ${#installed[@]} installed packages."
  run_root "${cmd[@]}"
}

ensure_lidm_available() {
  if ! package_installed lidm-git || ! package_installed lidm-systemd-git; then
    die "LiDM packages are not installed. Install lidm-git and lidm-systemd-git first."
  fi
  [[ -x "${LIDM_INSTALL_SCRIPT}" ]] || die "Missing LiDM install helper: ${LIDM_INSTALL_SCRIPT}"
}

cleanup_cosmic_repo() {
  log "Cleaning COSMIC repo references."
  remove_exact_lines "${SYSTEM_PACKAGES_FILE}" "${COSMIC_REPO_LINES[@]}"
  remove_repo_path "${COSMIC_MODULE_DIR}"
  stage_paths "${SYSTEM_PACKAGES_FILE}"
}

cleanup_cosmic_system() {
  log "Removing COSMIC packages from the system."
  remove_installed_packages "${COSMIC_PACKAGES[@]}"
}

cleanup_gnome_repo() {
  log "Cleaning GNOME repo references."
  replace_exact_line "${HOST_FILE}" "- gdm" "- lidm"
  replace_exact_line "${HOST_FILE}" "  pdf: org.gnome.Evince.desktop" "  pdf: org.pwmt.zathura.desktop"
  replace_exact_line "${HOST_FILE}" "  archive: org.gnome.FileRoller.desktop" "  archive: nemo.desktop"
  replace_exact_line "${HOST_FILE}" "    application/pdf: org.gnome.Evince.desktop" "    application/pdf: org.pwmt.zathura.desktop"

  remove_exact_lines "${GNOME_MODULE_FILE}" "${GNOME_MODULE_REMOVE_LINES[@]}"
  remove_exact_lines "${SYSTEM_PACKAGES_FILE}" "${GNOME_REPO_REMOVE_LINES[@]}"
  remove_exact_lines "${BASE_DESKTOP_PACKAGES_FILE}" "${GNOME_BASE_REPO_REMOVE_LINES[@]}"

  stage_paths "${HOST_FILE}" "${GNOME_MODULE_FILE}" "${SYSTEM_PACKAGES_FILE}" "${BASE_DESKTOP_PACKAGES_FILE}"
}

cleanup_gnome_system() {
  log "Switching display manager from GDM to LiDM."
  ensure_lidm_available
  run_root bash "${LIDM_INSTALL_SCRIPT}"

  log "Removing GNOME packages while keeping nautilus + xdg-desktop-portal-gnome."
  remove_installed_packages "${GNOME_REMOVE_PACKAGES[@]}"
}

main() {
  local arg

  while (( $# > 0 )); do
    arg="$1"
    case "${arg}" in
      cosmic|gnome)
        if [[ -n "${TARGET}" ]]; then
          die "Only one target may be specified."
        fi
        TARGET="${arg}"
        ;;
      --dry-run)
        DRY_RUN=1
        ;;
      --yes|-y)
        ASSUME_YES=1
        ;;
      --repo-only)
        REPO_ONLY=1
        ;;
      --system-only)
        SYSTEM_ONLY=1
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: ${arg}"
        ;;
    esac
    shift
  done

  [[ -n "${TARGET}" ]] || {
    usage
    exit 1
  }

  if (( REPO_ONLY && SYSTEM_ONLY )); then
    die "--repo-only and --system-only cannot be used together."
  fi

  command -v pacman >/dev/null 2>&1 || die "pacman is required."
  command -v python3 >/dev/null 2>&1 || die "python3 is required."

  cd "${REPO_ROOT}"

  case "${TARGET}" in
    cosmic)
      confirm "This will remove COSMIC packages and repo references. Continue?" || exit 1
      if (( ! REPO_ONLY )); then
        cleanup_cosmic_system
      fi
      if (( ! SYSTEM_ONLY )); then
        cleanup_cosmic_repo
      fi
      ;;
    gnome)
      confirm "This will switch to LiDM and remove the GNOME packages cleaned in the manual run. Continue?" || exit 1
      if (( ! REPO_ONLY )); then
        cleanup_gnome_system
      fi
      if (( ! SYSTEM_ONLY )); then
        cleanup_gnome_repo
      fi
      ;;
  esac

  log "Done."
  if (( DRY_RUN )); then
    log "Dry run only; nothing was changed."
  fi
}

main "$@"
