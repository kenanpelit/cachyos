#!/usr/bin/env sh
# ==============================================================================
# Script: pm.sh
# Description: Lightweight package manager wrapper (pacman, paru, yay, apt, dnf)
# Usage: pm.sh [command] [package(s)]
# ==============================================================================
# Env:
#   PM           Force package manager selection
#   PM_COLOR     "always" | "never" (default: auto by TTY)
#   PM_SUDO      sudo command (auto-detected)
#   PM_DEVEL_REGEX Regex used to detect development packages
#                  (default: -(git|svn|hg|bzr|darcs|cvs|nightly|daily)$)

# shellcheck disable=SC2064

set -eu

export LC_ALL=C

usage() {
    echo "Package manager wrapper (supports: $PMS)"
    echo
    echo "Usage: $0 <command> [options]"
    echo
    echo "Commands:"
    echo "  i,  install          Interactively select packages to install."
    echo "  i,  install <pkg>... Install one or more packages."
    echo "  r,  remove           Interactively select packages to remove."
    echo "  r,  remove <pkg>...  Remove one or more packages."
    echo "  u,  upgrade [mode]   Upgrade packages. mode: all (default), devel/git."
    echo "  uy, upgrade-yes      Upgrade all packages with auto-confirm."
    echo "  ug, upgrade-git      Upgrade only development packages (*-git, *-svn, ...)."
    echo "  ugy, upgrade-git-yes Upgrade development packages with auto-confirm."
    echo "  f,  fetch            Update local package database."
    echo "  c,  clean            Clean the package cache."
    echo "  o,  orphans          Remove orphaned (unneeded) dependencies."
    echo "  n,  info <pkg>       Print package information."
    echo "  owns <file>          Show which package owns a file."
    echo "  la, list all         List all packages."
    echo "  li, list installed   List installed packages."
    echo "  sa  search all       Interactively search between repo packages."
    echo "  sr  search aur <q>   Search AUR packages by query."
    echo "  si  search installed Interactively search between installed packages."
    echo "  w,  which            Print which package manager is being used."
    echo "  h,  help             Print this help."
    echo
    echo "Options:"
    echo "  -y, --yes, --noconfirm"
    echo "      Auto-confirm install/remove/upgrade operations."
    echo
    echo "Interactive commands can read additional filters from standard input."
    echo "Each line is a regular expression (POSIX extended), matching whole package name."
}

main() {
    if [ $# -eq 0 ]; then
        die_wrong_usage "expected <command> argument"
    fi

    if [ "$1" = h ] || [ "$1" = -h ] || [ "$1" = help ] || [ "$1" = --help ]; then
        usage
        exit
    fi

    # Color policy: auto by TTY unless overridden.
    if [ ! "${PM_COLOR+is_set}" ]; then
        if [ -t 1 ]; then
            PM_COLOR="always"
        else
            PM_COLOR="never"
        fi
    fi

    # Sudo helper detection (disabled for Termux).
    if [ ! "${PM_SUDO+is_set}" ]; then
        PM_SUDO=
        # Termux package installation does not require sudo
        if [ ! "${TERMUX_VERSION-}" ]; then
            for NAME in sudo sudo-rs doas; do
                if is_command "$NAME"; then
                    PM_SUDO="$NAME"
                    break
                fi
            done
        fi
    fi

    # AUR helpers do not accept empty sudo, so fallback to `env`.
    AUR_SUDO=${PM_SUDO:-env}

    # Detect development package names (can be overridden from env).
    PM_DEVEL_REGEX=${PM_DEVEL_REGEX:--(git|svn|hg|bzr|darcs|cvs|nightly|daily)$}
    PM_NOCONFIRM=${PM_NOCONFIRM:-0}

    # Output formatting (colorized table).
    if [ "$PM_COLOR" = always ]; then
        FMT_NAME='"\033[1m"'
        FMT_GROUP='" \033[1;35m"'
        FMT_VERSION='" \033[1;36m"'
        FMT_STATUS='" \033[1;32m"'
        FMT_RESET='"\033[0m"'
    else
        FMT_NAME='""'
        FMT_GROUP='" "'
        FMT_VERSION='" "'
        FMT_STATUS='" "'
        FMT_RESET='""'
    fi

    # Select package manager (unless PM is explicitly set).
    pm_detect

    # Cache used for fetch timestamps and optional indexes.
    PM_CACHE_DIR=${XDG_CACHE_HOME:-$HOME/.cache}/pm/$PM
    mkdir -p "$PM_CACHE_DIR"

    COMMAND=$1
    shift

    case "$COMMAND" in
    i | install) install "$@" ;;
    u | upgrade) upgrade "$@" ;;
    uy | upgrade-yes)
        PM_NOCONFIRM=1
        upgrade all "$@"
        ;;
    ug | upgrade-git | upgrade-devel) upgrade devel "$@" ;;
    ugy | upgrade-git-yes | upgrade-devel-yes)
        PM_NOCONFIRM=1
        upgrade devel "$@"
        ;;
    r | remove) remove "$@" ;;
    n | info) info "$@" ;;
    l | list) list "$@" ;;
    li) list installed ;;
    la) list all ;;
    s | search) search "$@" ;;
    sr) search aur ;;
    si) search installed ;;
    sa) search all ;;
    f | fetch) fetch ;;
    c | clean) clean ;;
    o | orphans | autoremove) orphans "$@" ;;
    owns | own) owns "$@" ;;
    w | which) which ;;
    *) die_wrong_usage "invalid <command> argument '$COMMAND'" ;;
    esac
}

# =============================================================================
# Commands (user-facing)
# =============================================================================

install() {
    while [ $# -gt 0 ]; do
        case "$1" in
        -y | --yes | --noconfirm)
            PM_NOCONFIRM=1
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
        esac
    done

    if [ ! -f "$PM_CACHE_DIR/last-fetch" ] || [ "$(cat "$PM_CACHE_DIR/last-fetch")" != "$(current_date)" ]; then
        pm_fetch
    fi
    if [ $# -eq 0 ]; then
        search all | PM=$PM PM_COLOR=$PM_COLOR xargs_self install
    else
        pm_install "$@"
    fi
}

remove() {
    while [ $# -gt 0 ]; do
        case "$1" in
        -y | --yes | --noconfirm)
            PM_NOCONFIRM=1
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
        esac
    done

    if [ $# -eq 0 ]; then
        search installed | PM=$PM PM_COLOR=$PM_COLOR xargs_self remove
    else
        pm_remove "$@"
    fi
}

upgrade() {
    MODE=all
    MODE_SET=0
    while [ $# -gt 0 ]; do
        case "$1" in
        -y | --yes | --noconfirm)
            PM_NOCONFIRM=1
            ;;
        all | devel | git)
            if [ "$MODE_SET" -eq 1 ]; then
                die_wrong_usage "multiple upgrade modes provided"
            fi
            MODE="$1"
            MODE_SET=1
            ;;
        *)
            die_wrong_usage "invalid upgrade argument '$1' (expected mode: all|devel|git or -y|--yes)"
            ;;
        esac
        shift
    done

    case "$MODE" in
    all)
        pm_fetch
        pm_upgrade
        ;;
    devel | git)
        pm_fetch
        pm_upgrade_devel
        ;;
    *)
        die_wrong_usage "invalid upgrade mode '$MODE' (expected: all|devel|git)"
        ;;
    esac
}

fetch() {
    pm_fetch
}

info() {
    if [ $# -eq 0 ]; then
        die_wrong_usage "expected <package> argument"
    fi
    pm_info "$1"
}

list() {
    check_source "$@"
    if [ "$1" = aur ]; then
        die_wrong_usage "use 'search aur <query>' for AUR"
    fi
    pm_list "$1" | pm_format "$1"
}

search() {
    check_source "$@"

    if [ "$1" = aur ]; then
        shift
        aur_search "$@" | interactive_filter_aur
        return
    fi

    if [ -t 0 ]; then
        pm_list "$1" | pm_format "$1" | interactive_filter
    else
        FILTER_FILE=$(mktemp)
        trap "rm -f -- '$FILTER_FILE'" EXIT
        compile_stdin_filter >"$FILTER_FILE"
        pm_list "$1" | grep -Ef "$FILTER_FILE" | pm_format "$1" | interactive_filter
    fi
}

which() {
    echo "$PM"
}

clean() {
    pm_clean
}

orphans() {
    while [ $# -gt 0 ]; do
        case "$1" in
        -y | --yes | --noconfirm)
            PM_NOCONFIRM=1
            shift
            ;;
        *)
            break
            ;;
        esac
    done
    pm_orphans
}

owns() {
    if [ $# -eq 0 ]; then
        die_wrong_usage "expected <file> argument"
    fi
    pm_owns "$@"
}

# =============================================================================
# Utils
# =============================================================================

die() {
    echo >&2 "$0: $1"
    exit 1
}

die_wrong_usage() {
    die "$1, run '$0 help' for usage"
}

is_command() {
    [ -x "$(command -v "$1")" ]
}

current_date() {
    date -u +%Y-%m-%d
}

check_source() {
    if [ $# -eq 0 ]; then
        die_wrong_usage "expected <source> argument"
    elif [ "$1" != installed ] && [ "$1" != all ] && [ "$1" != aur ]; then
        die_wrong_usage "invalid <source> argument '$1'"
    fi
}

compile_stdin_filter() {
    # 1) Remove comments
    # 2) Trim
    # 3) Drop empty lines
    # 4) Anchor to whole package name
    sed -E 's/#.*//;s/^\s+//;s/\s+$//' |
        { grep . || die "empty stdin filter"; } |
        awk '{ print "^" $1 "($|\\s)" }'
}

interactive_filter() {
    if [ ! "${COLUMNS-}" ] && is_command tput; then
        COLUMNS=$(tput cols)
    fi

    if [ "${COLUMNS:-80}" -lt 80 ]; then
        PREVIEW_WINDOW='down:50%'
    else
        PREVIEW_WINDOW='right:50%'
    fi

    if is_command fzf; then
        fzf --exit-0 \
            --multi \
            --no-sort \
            --ansi \
            --layout=reverse \
            --exact \
            --cycle \
            --preview="PM=$PM PM_COLOR=$PM_COLOR $0 info {1}" \
            --preview-window "$PREVIEW_WINDOW" |
            cut -d" " -f1
    else
        die "fzf is not available, run '$0 install fzf' first"
    fi
}

interactive_filter_aur() {
    if is_command fzf; then
        fzf --exit-0 \
            --multi \
            --no-sort \
            --ansi \
            --layout=reverse \
            --exact \
            --cycle |
            cut -d" " -f1
    else
        die "fzf is not available, run '$0 install fzf' first"
    fi
}

aur_search() {
    local query
    if [ $# -gt 0 ]; then
        query=$*
    else
        printf "AUR query: " >/dev/tty
        read -r query </dev/tty
    fi
    [ -n "${query:-}" ] || die "empty AUR query"

    # Prefer AUR helper search to avoid network + keep parity with paru/yay output.
    if is_command paru; then
        if paru --aur -Ss --color=never "$query" 2>/dev/null | awk '
            BEGIN { name=""; ver=""; desc="" }
            /^aur\// {
                # format: aur/pkgname version (votes) [out-of-date]
                split($1, a, "/"); name=a[2]; ver=$2; next
            }
            name != "" {
                desc=$0; sub(/^[[:space:]]+/, "", desc);
                print name " aur " ver " " desc;
                name=""; ver=""; desc="";
            }
        '; then
            return 0
        fi
    fi

    if is_command yay; then
        if yay --aur -Ss --color=never "$query" 2>/dev/null | awk '
            BEGIN { name=""; ver=""; desc="" }
            /^aur\// {
                split($1, a, "/"); name=a[2]; ver=$2; next
            }
            name != "" {
                desc=$0; sub(/^[[:space:]]+/, "", desc);
                print name " aur " ver " " desc;
                name=""; ver=""; desc="";
            }
        '; then
            return 0
        fi
    fi

    # Fallback to AUR RPC over HTTPS (python is required).
    if is_command python3; then
        python3 - "$query" <<'PY'
import json
import sys
import urllib.parse
import urllib.request

query = " ".join(sys.argv[1:]).strip()
if not query:
    raise SystemExit("empty query")

params = urllib.parse.urlencode({"v": "5", "type": "search", "arg": query})
url = "https://aur.archlinux.org/rpc/?" + params

with urllib.request.urlopen(url, timeout=10) as resp:
    body = resp.read().decode("utf-8", errors="replace")

data = json.loads(body)
for r in data.get("results", []):
    name = r.get("Name","")
    ver = r.get("Version","")
    desc = (r.get("Description","") or "").replace("\t"," ")
    print(f"{name} aur {ver} {desc}")
PY
    elif is_command python; then
        python - "$query" <<'PY'
import json
import sys
import urllib.parse
import urllib.request

query = " ".join(sys.argv[1:]).strip()
if not query:
    raise SystemExit("empty query")

params = urllib.parse.urlencode({"v": "5", "type": "search", "arg": query})
url = "https://aur.archlinux.org/rpc/?" + params

with urllib.request.urlopen(url, timeout=10) as resp:
    body = resp.read().decode("utf-8", errors="replace")

data = json.loads(body)
for r in data.get("results", []):
    name = r.get("Name","")
    ver = r.get("Version","")
    desc = (r.get("Description","") or "").replace("\t"," ")
    print(f"{name} aur {ver} {desc}")
PY
    else
        die "python3/python is required for AUR search"
    fi
}

xargs_self() {
    # Some older xargs implementations (busybox < 1.36) do not support `-o` option to reopen /dev/tty as stdin.
    # This is a workaround suggested by `man xargs`.
    # shellcheck disable=SC2016
    xargs -r sh -c '"$0" "$@" </dev/tty' "$0" "$@"
}

with_sudo() {
    if [ "$PM_SUDO" ]; then
        "$PM_SUDO" "$@"
    else
        "$@"
    fi
}

is_noconfirm() {
    [ "${PM_NOCONFIRM:-0}" = "1" ]
}

# =============================================================================
# PM wrapper
# =============================================================================

# Package managers are detected in this order
PMS="paru yay pacman apt dnf"

pm_detect() {
    if [ ! "${PM-}" ]; then
        for NAME in $PMS; do
            if is_command "$NAME"; then
                PM=$NAME
                break
            fi
        done
        if [ ! "${PM-}" ]; then
            die "no supported package manager found ($PMS)"
        fi
    fi
}

pm_install() {
    "${PM}_install" "$@"
}

pm_remove() {
    "${PM}_remove" "$@"
}

pm_upgrade() {
    "${PM}_upgrade"
}

pm_upgrade_devel() {
    "${PM}_upgrade_devel"
}

pm_fetch() {
    "${PM}_fetch"
    current_date >"$PM_CACHE_DIR/last-fetch"
}

pm_info() {
    "${PM}_info" "$1"
}

pm_list() {
    "${PM}_list_$1"
}

pm_format() {
    "${PM}_format_$1"
}

pm_clean() {
    "${PM}_clean"
}

pm_orphans() {
    "${PM}_orphans"
}

pm_owns() {
    "${PM}_owns" "$@"
}

# =============================================================================
# Pacman
# =============================================================================

pacman_install() {
    for PKG in "$@"; do
        if aur_helpers_contain "$PKG"; then
            # Custom install procedure for AUR helpers
            aur_helpers_install "$PKG"
            # Re-run the installation for the remaining packages (should use the installed helper as PM)
            printf "%s\n" "$@" | grep -Fv "$PKG" | xargs_self install
            return
        fi
    done
    if is_noconfirm; then
        with_sudo pacman -S --needed --noconfirm "$@"
    else
        with_sudo pacman -S --needed "$@"
    fi
}

pacman_remove() {
    if is_noconfirm; then
        with_sudo pacman -Rsc --noconfirm "$@"
    else
        with_sudo pacman -Rsc "$@"
    fi
}

pacman_upgrade() {
    if is_noconfirm; then
        with_sudo pacman -Su --noconfirm
    else
        with_sudo pacman -Su
    fi
}

pacman_fetch() {
    with_sudo pacman -Sy
}

pacman_info() {
    if aur_helpers_contain "$1"; then
        aur_helpers_info "$1"
    else
        pacman -Si --color="$PM_COLOR" "$1"
    fi
}

pacman_list_all() {
    pacman -Sl --color=never | awk '{ print $2 " " $1 " " $3 " " $4 }'
    aur_helpers_list
}

pacman_list_installed() {
    pacman -Q --color=never
}

pacman_format_all() {
    awk "{ print $FMT_NAME \$1 $FMT_GROUP \$2 $FMT_VERSION \$3 $FMT_STATUS \$4 $FMT_RESET }"
}

pacman_format_installed() {
    awk "{ print $FMT_NAME \$1 $FMT_VERSION \$2 $FMT_RESET }"
}

pacman_clean() {
    if is_noconfirm; then
        with_sudo pacman -Sc --noconfirm
    else
        with_sudo pacman -Sc
    fi
}

pacman_orphans() {
    ORPHANS=$(pacman -Qtdq 2>/dev/null || true)
    if [ -z "$ORPHANS" ]; then
        echo "No orphan packages to remove"
        return 0
    fi
    echo "Removing orphan packages:"
    printf "%s\n" "$ORPHANS"
    # shellcheck disable=SC2086
    if is_noconfirm; then
        with_sudo pacman -Rns --noconfirm $ORPHANS
    else
        with_sudo pacman -Rns $ORPHANS
    fi
}

pacman_owns() {
    pacman -Qo "$@"
}

# =============================================================================
# AUR helpers
# =============================================================================

AUR_HELPERS="paru paru-bin yay yay-bin"

aur_helpers_contain() {
    for NAME in $AUR_HELPERS; do
        if [ "$1" = "$NAME" ]; then
            return 0
        fi
    done
    return 1
}

aur_helpers_install() {
    if is_noconfirm; then
        with_sudo pacman -S --needed --noconfirm git base-devel
    else
        with_sudo pacman -S --needed git base-devel
    fi
    AUR_DIR=$(mktemp -d)
    trap "rm -rf -- '$AUR_DIR'" EXIT
    git clone "https://aur.archlinux.org/$1.git" "$AUR_DIR"
    cd "$AUR_DIR"
    if is_noconfirm; then
        makepkg -si --noconfirm
    else
        makepkg -si
    fi
}

aur_helpers_info() {
    printf "\e[1mRepository  :\e[0m aur\n"
    printf "\e[1mName        :\e[0m %s\n" "$1"
    printf "\e[1mDescription :\e[0m AUR helper\n"
}

aur_helpers_list() {
    # shellcheck disable=SC2086
    printf "%s aur\n" $AUR_HELPERS
}

# =============================================================================
# Paru
# =============================================================================

paru_install() {
    if is_noconfirm; then
        paru --sudo "$AUR_SUDO" -S --needed --noconfirm "$@"
    else
        paru --sudo "$AUR_SUDO" -S --needed "$@"
    fi
}

paru_remove() {
    if is_noconfirm; then
        paru --sudo "$AUR_SUDO" -Rsc --noconfirm "$@"
    else
        paru --sudo "$AUR_SUDO" -Rsc "$@"
    fi
}

paru_upgrade() {
    if is_noconfirm; then
        paru --sudo "$AUR_SUDO" -Su --noconfirm
    else
        paru --sudo "$AUR_SUDO" -Su
    fi
}

paru_upgrade_devel() {
    # Ensure devel DB is initialized when available.
    paru --gendb >/dev/null 2>&1 || true

    PARU_DEVEL_UPDATES=$(
        paru -Qua --devel --color=never 2>/dev/null |
            awk -v re="$PM_DEVEL_REGEX" '$1 ~ re { print $1 }' |
            sort -u
    )

    if [ -z "$PARU_DEVEL_UPDATES" ]; then
        echo "No development package upgrades available"
        return 0
    fi

    echo "Upgrading development packages:"
    printf "%s\n" "$PARU_DEVEL_UPDATES"
    # shellcheck disable=SC2086
    if is_noconfirm; then
        # shellcheck disable=SC2086
        paru --sudo "$AUR_SUDO" -S --needed --devel --noconfirm $PARU_DEVEL_UPDATES
    else
        # shellcheck disable=SC2086
        paru --sudo "$AUR_SUDO" -S --needed --devel $PARU_DEVEL_UPDATES
    fi
}

paru_fetch() {
    paru --sudo "$AUR_SUDO" -Sy
}

paru_info() {
    paru -Si --color="$PM_COLOR" "$1"
}

paru_list_all() {
    # Use pacman for repo listing to avoid occasional alpm.rs panics in paru.
    pacman -Sl --color=never | awk '{ print $2 " " $1 " " $3 " " $4 }'
}

paru_list_installed() {
    paru -Q --color=never
}

paru_format_all() {
    awk "{ print $FMT_NAME \$1 $FMT_GROUP \$2 $FMT_VERSION \$3 $FMT_STATUS \$4 $FMT_RESET }"
}

paru_format_installed() {
    awk "{ print $FMT_NAME \$1 $FMT_VERSION \$2 $FMT_RESET }"
}

paru_clean() {
    if is_noconfirm; then
        paru --sudo "$AUR_SUDO" -Sc --noconfirm
    else
        paru --sudo "$AUR_SUDO" -Sc
    fi
}

paru_orphans() {
    pacman_orphans
}

paru_owns() {
    pacman -Qo "$@"
}

# =============================================================================
# Yay
# =============================================================================

yay_install() {
    if is_noconfirm; then
        yay --sudo "$AUR_SUDO" -S --needed --noconfirm "$@"
    else
        yay --sudo "$AUR_SUDO" -S --needed "$@"
    fi
}

yay_remove() {
    if is_noconfirm; then
        yay --sudo "$AUR_SUDO" -Rsc --noconfirm "$@"
    else
        yay --sudo "$AUR_SUDO" -Rsc "$@"
    fi
}

yay_upgrade() {
    if is_noconfirm; then
        yay --sudo "$AUR_SUDO" -Su --noconfirm
    else
        yay --sudo "$AUR_SUDO" -Su
    fi
}

yay_upgrade_devel() {
    YAY_DEVEL_UPDATES=$(
        yay -Qua --devel --color=never 2>/dev/null |
            awk -v re="$PM_DEVEL_REGEX" '$1 ~ re { print $1 }' |
            sort -u
    )

    if [ -z "$YAY_DEVEL_UPDATES" ]; then
        echo "No development package upgrades available"
        return 0
    fi

    echo "Upgrading development packages:"
    printf "%s\n" "$YAY_DEVEL_UPDATES"
    # shellcheck disable=SC2086
    if is_noconfirm; then
        # shellcheck disable=SC2086
        yay --sudo "$AUR_SUDO" -S --needed --devel --noconfirm $YAY_DEVEL_UPDATES
    else
        # shellcheck disable=SC2086
        yay --sudo "$AUR_SUDO" -S --needed --devel $YAY_DEVEL_UPDATES
    fi
}

yay_fetch() {
    yay --sudo "$AUR_SUDO" -Sy
}

yay_info() {
    yay -Si --color="$PM_COLOR" "$1"
}

yay_list_all() {
    # We want non-AUR results first and pacman is also much faster than yay here.
    {
        pacman -Sl --color=never
        yay -Sla --color=never
    } | awk '{ print $2 " " $1 " " $3 " " $4 }'
}

yay_list_installed() {
    yay -Q --color=never
}

yay_format_all() {
    awk "{ print $FMT_NAME \$1 $FMT_GROUP \$2 $FMT_VERSION \$3 $FMT_STATUS \$4 $FMT_RESET }"
}

yay_format_installed() {
    awk "{ print $FMT_NAME \$1 $FMT_VERSION \$2 $FMT_RESET }"
}

yay_clean() {
    if is_noconfirm; then
        yay --sudo "$AUR_SUDO" -Sc --noconfirm
    else
        yay --sudo "$AUR_SUDO" -Sc
    fi
}

yay_orphans() {
    pacman_orphans
}

yay_owns() {
    pacman -Qo "$@"
}

# =============================================================================
# Apt
# =============================================================================

apt_install() {
    if is_noconfirm; then
        with_sudo apt install -y "$@"
    else
        with_sudo apt install "$@"
    fi
}

apt_remove() {
    if is_noconfirm; then
        with_sudo apt remove -y "$@"
    else
        with_sudo apt remove "$@"
    fi
}

apt_upgrade() {
    if is_noconfirm; then
        with_sudo apt upgrade -y
    else
        with_sudo apt upgrade
    fi
}

apt_upgrade_devel() {
    die "development-only upgrades are not supported for apt"
}

apt_fetch() {
    with_sudo apt update
}

apt_info() {
    # Using `apt show` is not recommended due to unstable CLI
    apt-cache show "$1"
}

apt_list_all() {
    INSTALLED_PKGS_FILE=$(mktemp)
    trap "rm -f -- '$INSTALLED_PKGS_FILE'" EXIT
    dpkg-query --show -f '${package} [installed]\n' >"$INSTALLED_PKGS_FILE"
    apt-cache pkgnames | sort | join -j1 -a1 - "$INSTALLED_PKGS_FILE"
}

apt_list_installed() {
    dpkg-query --show
}

apt_format_all() {
    awk "{ print $FMT_NAME \$1 $FMT_STATUS \$2 $FMT_RESET }"
}

apt_format_installed() {
    awk "{ print $FMT_NAME \$1 $FMT_VERSION \$2 $FMT_RESET }"
}

apt_clean() {
    with_sudo apt clean
    with_sudo apt autoclean
}

apt_orphans() {
    if is_noconfirm; then
        with_sudo apt autoremove -y
    else
        with_sudo apt autoremove
    fi
}

apt_owns() {
    dpkg -S "$@"
}

# =============================================================================
# Dnf
# =============================================================================

dnf_install() {
    if is_noconfirm; then
        with_sudo dnf install -y "$@"
    else
        with_sudo dnf install "$@"
    fi
}

dnf_remove() {
    if is_noconfirm; then
        with_sudo dnf remove -y "$@"
    else
        with_sudo dnf remove "$@"
    fi
}

dnf_fetch() {
    # dnf exists with code 100 in distrobox https://github.com/fedora-cloud/docker-brew-fedora/issues/46
    with_sudo dnf check-update || true
}

dnf_upgrade() {
    if is_noconfirm; then
        with_sudo dnf upgrade -y
    else
        with_sudo dnf upgrade
    fi
}

dnf_upgrade_devel() {
    die "development-only upgrades are not supported for dnf"
}

pacman_upgrade_devel() {
    PACMAN_DEVEL_UPDATES=$(
        pacman -Qu --color=never 2>/dev/null |
            awk -v re="$PM_DEVEL_REGEX" '$1 ~ re { print $1 }' |
            sort -u
    )

    if [ -z "$PACMAN_DEVEL_UPDATES" ]; then
        echo "No development package upgrades available"
        return 0
    fi

    echo "Upgrading development packages:"
    printf "%s\n" "$PACMAN_DEVEL_UPDATES"
    # shellcheck disable=SC2086
    if is_noconfirm; then
        # shellcheck disable=SC2086
        with_sudo pacman -S --needed --noconfirm $PACMAN_DEVEL_UPDATES
    else
        # shellcheck disable=SC2086
        with_sudo pacman -S --needed $PACMAN_DEVEL_UPDATES
    fi
}

dnf_info() {
    # Skip the first header line
    dnf info -q --color="$PM_COLOR" "$1" | grep :
}

dnf_list_all() {
    INSTALLED_PKGS_FILE=$(mktemp)
    trap "rm -f -- '$INSTALLED_PKGS_FILE'" EXIT
    dnf repoquery -q --installed --qf '%{name} [installed]' >"$INSTALLED_PKGS_FILE"
    dnf repoquery -q --qf='%{name} %{repoid} %{evr}' | join -j1 -a1 - "$INSTALLED_PKGS_FILE"
}

dnf_list_installed() {
    dnf repoquery -q --installed --qf '%{name} %{evr}'
}

dnf_format_all() {
    awk "{ print $FMT_NAME \$1 $FMT_GROUP \$2 $FMT_VERSION \$3 $FMT_STATUS \$4 $FMT_RESET }"
}

dnf_format_installed() {
    awk "{ print $FMT_NAME \$1 $FMT_VERSION \$2 $FMT_RESET }"
}

dnf_clean() {
    with_sudo dnf clean all
}

dnf_orphans() {
    if is_noconfirm; then
        with_sudo dnf autoremove -y
    else
        with_sudo dnf autoremove
    fi
}

dnf_owns() {
    dnf provides "$@"
}

# =============================================================================
# Run
# =============================================================================

main "$@"
