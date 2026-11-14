#!/usr/bin/env bash
# ==============================================================================
# Script: osc-symlink_manager.sh
# Description: Manages symbolic links for configured directories with backup
# Usage: osc-symlink_manager.sh [options]
# ==============================================================================
# Features:
#   - Creates symbolic links from source to target directories
#   - Automatic backup of existing directories
#   - Configurable directory list
#   - Dry-run mode for testing
#   - Color-coded status output
#   - Safety checks and confirmations
#   - Migration: `copy` mirrors real directories in $HOME into their source
#     (rsync -aHAX) while the programs still run; `create` then syncs once
#     more right before moving each one aside and linking it, so nothing
#     written since the copy is lost. Only a source made by `copy` is synced
#     with --delete; any other existing source is merged into, never pruned.
#     A directory some process still uses (cwd or open file) is skipped until
#     that program is closed - or, with --live, linked anyway: the running
#     programs keep writing into the moved-aside copy, and `finish` (once they
#     have exited) carries what they wrote after the switch into the source,
#     keeping both versions of any file changed on both sides.
#
# License: MIT
#
#===============================================================================

# set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Configuration
SOURCE_ROOT="/repo/archive"
TARGET_ROOT="$HOME"

# Directories to link (relative to SOURCE_ROOT -> TARGET_ROOT)
DIRS=(
  "Documents"
  "Downloads"
  "Music"
  "Pictures"
  "Videos"
  "Work"
  "Tmp"
)

# Explicit links: "source|target"
EXTRA_LINKS=(
  "/repo/archive/.anote|$HOME/.anote"
  "/repo/archive/.backups|$HOME/.backups"
  "/repo/archive/.brave|$HOME/.brave"
  "/repo/archive/.chrome|$HOME/.chrome"
  "/repo/archive/.eng|$HOME/.eng"
  "/repo/archive/.helium|$HOME/.helium"
  "/repo/archive/.kenp|$HOME/.kenp"
  "/repo/archive/.keep|$HOME/.keep"
  "/repo/archive/.kod|$HOME/.kod"
  "/repo/archive/.mozilla|$HOME/.mozilla"
  "/repo/archive/.mullvad|$HOME/.mullvad"
  "/repo/archive/.pass|$HOME/.pass"
  "/repo/archive/.passh|$HOME/.passh"
  "/others/tor|$HOME/.tor"
  "/repo/archive/.keyrings|$HOME/.local/share/keyrings"
  # Tool, agent and app homes (2026-11-13). Close the program before `create`:
  # its directory is skipped while a process has it open.
  "/repo/archive/.cachy|$HOME/.cachy"
  "/repo/archive/.hermes|$HOME/.hermes"
  "/repo/archive/.codex|$HOME/.codex"
  "/repo/archive/.gemini|$HOME/.gemini"
  "/repo/archive/.claude|$HOME/.claude"
  "/repo/archive/.anydesk|$HOME/.anydesk"
  "/repo/archive/.site|$HOME/.site"
  "/repo/archive/.podman|$HOME/.podman"
  "/repo/archive/.vpn|$HOME/.vpn"
  "/repo/archive/.x2go|$HOME/.x2go"
  "/repo/archive/.x2goclient|$HOME/.x2goclient"
)

# Sources that `copy` made as mirrors of their home directory: only these may
# be synced with --delete (any other source can hold data of its own).
COPIES_FILE="$SOURCE_ROOT/.osc-symlink-copies"
# Live switches still to reconcile: "source|backup|epoch seconds of the switch".
PENDING_FILE="$SOURCE_ROOT/.osc-symlink-pending"

# Options
DRY_RUN=false
FORCE=false
LIVE=false

# Simple logging
log() {
  local color="${2:-$NC}"
  echo -e "${color}$1${NC}"
}

error() {
  log "HATA: $1" "$RED"
  exit 1
}

# Help
show_help() {
  echo -e "${BLUE}Symlink Yönetici${NC}"
  echo
  echo "Kullanım: $(basename "$0") [KOMUT] [SEÇENEKLER]"
  echo
  echo "Komutlar:"
  echo "  copy                   Gerçek dizinleri kaynağa kopyala (programlar açıkken de olur)"
  echo "  create (varsayılan)    Son kez eşitle, dizini yedeğe al, symlink'i oluştur"
  echo "  finish                 --live geçişlerinden sonra eski kopyaya yazılanları kaynağa taşı"
  echo "  remove                 Symlink'leri kaldır"
  echo "  status                 Durumu göster"
  echo
  echo "Seçenekler:"
  echo "  -d, --dry-run         Test modu"
  echo "  -f, --force           Onay isteme"
  echo "  -l, --live            Kullanımdaki dizini de bağla (sonra: finish)"
  echo "  -h, --help            Yardım"
  echo
  echo "Örnekler:"
  echo "  $(basename "$0")                    # Symlink'leri oluştur"
  echo "  $(basename "$0") copy               # Önce kopyala"
  echo "  $(basename "$0") create --live      # Kullanımdakileri de bağla"
  echo "  $(basename "$0") finish             # Programlar kapanınca uzlaştır"
  echo "  $(basename "$0") status             # Durumu göster"
  echo "  $(basename "$0") remove --dry-run   # Kaldırma testi"
  echo
}

# Check prerequisites
check_setup() {
  command -v rsync >/dev/null || error "rsync gerekli"
  [[ -d "$SOURCE_ROOT" ]] || error "Kaynak dizin bulunamadı: $SOURCE_ROOT"
  [[ -w "$TARGET_ROOT" ]] || error "Hedef dizine yazma izni yok: $TARGET_ROOT"
}

iter_links() {
  local dir
  for dir in "${DIRS[@]}"; do
    printf '%s|%s|%s\n' "$dir" "$SOURCE_ROOT/$dir" "$TARGET_ROOT/$dir"
  done

  local entry source target name
  for entry in "${EXTRA_LINKS[@]}"; do
    source="${entry%%|*}"
    target="${entry#*|}"
    name="$(basename "$target")"
    printf '%s|%s|%s\n' "$name" "$source" "$target"
  done
}

# Show current status
show_status() {
  echo -e "\n${BLUE}=== Symlink Durumu ===${NC}"

  local linked=0 missing=0

  while IFS='|' read -r name source target; do
    if [[ -L "$target" ]]; then
      local link_target="$(readlink "$target" || echo "ERROR")"
      if [[ "$link_target" == "$source" ]]; then
        echo -e "${GREEN}✓${NC} $name"
        ((linked++)) || true
      else
        echo -e "${YELLOW}⚠${NC} $name -> $link_target (farklı hedef)"
      fi
    elif [[ -d "$target" && -d "$source" ]]; then
      echo -e "${YELLOW}✗${NC} $name (kopyası var, henüz link değil: create)"
      ((missing++)) || true
    elif [[ -e "$target" ]]; then
      echo -e "${RED}✗${NC} $name (dosya var, link değil)"
      ((missing++)) || true
    else
      echo -e "${RED}✗${NC} $name (link yok)"
      ((missing++)) || true
    fi

    # Check source
    if [[ ! -d "$source" ]]; then
      echo -e "  ${YELLOW}⚠ Kaynak yok: $source${NC}"
    fi
  done < <(iter_links)

  if [[ -s "$PENDING_FILE" ]]; then
    echo -e "\n${YELLOW}Uzlaştırılmayı bekleyen canlı geçişler (finish):${NC}"
    cut -d'|' -f2 "$PENDING_FILE" | sed 's/^/  /'
  fi

  local total=$((${#DIRS[@]} + ${#EXTRA_LINKS[@]}))
  echo -e "\n${BLUE}Toplam: ${total} | Bağlı: $linked | Eksik: $missing${NC}"
}

# Processes that still use a directory (cwd, executable or an open file under
# it), as "name(pid)" words. find matches the /proc links in C: a bash loop
# over every open file of every process took ~20 s per directory.
users_of() {
  local dir="$1" pid
  find /proc/[0-9]*/cwd /proc/[0-9]*/exe /proc/[0-9]*/fd -maxdepth 1 \
    \( -lname "$dir" -o -lname "$dir/*" \) -print 2>/dev/null |
    cut -d/ -f3 | sort -un | while read -r pid; do
      [[ "$pid" == "$$" ]] && continue
      printf '%s(%s) ' "$(cat "/proc/$pid/comm" 2>/dev/null)" "$pid"
    done
}

is_copy() { [[ -f "$COPIES_FILE" ]] && grep -qxF "$1" "$COPIES_FILE"; }
forget_copy() {
  [[ -f "$COPIES_FILE" ]] || return 0
  grep -vxF "$1" "$COPIES_FILE" >"$COPIES_FILE.tmp"; mv "$COPIES_FILE.tmp" "$COPIES_FILE"
}

# Mirror every real home directory into its source, recording it as a copy.
copy_dirs() {
  [[ "$DRY_RUN" == "true" ]] && log "=== TEST MODU ===" "$YELLOW"
  log "\n=== Kopyalama ===" "$BLUE"
  while IFS='|' read -r name source target; do
    [[ -d "$target" && ! -L "$target" ]] || continue
    if [[ -e "$source" ]] && ! is_copy "$source" && [[ -n "$(ls -A "$source" 2>/dev/null)" ]]; then
      log "Atlandı: $name - $source dolu ve bir kopya değil (create birleştirir, silmez)" "$YELLOW"
      continue
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
      log "[TEST] Kopyala: $target/ -> $source/" "$YELLOW"
      continue
    fi
    mkdir -p "$source" && rsync -aHAX --numeric-ids --delete "$target/" "$source/" || {
      log "HATA: $name kopyalanamadı" "$RED"
      continue
    }
    is_copy "$source" || echo "$source" >>"$COPIES_FILE"
    log "Kopyalandı: $name ($(du -sh "$source" 2>/dev/null | cut -f1))" "$GREEN"
  done < <(iter_links)
  log "\nTamamlandı! Programları kapatıp: $(basename "$0") create" "$GREEN"
}

# Move a real directory aside and bring its contents to the source first.
# Returns 1 when the entry must be skipped (in use, or the sync failed).
backup_dir() {
  local name="$1"
  local source="$2"
  local target="$3"

  [[ -d "$target" && ! -L "$target" ]] || return 0

  local busy
  busy="$(users_of "$target")"
  if [[ -n "$busy" && "$LIVE" != "true" ]]; then
    log "Atlandı: $name kullanımda: $busy- programı kapatın ya da --live kullanın" "$RED"
    return 1
  fi
  # Taken before the last sync: anything written from here on is looked at
  # again by `finish`, also a write that lands while rsync runs.
  local since
  since="$(date +%s)"

  # The home copy is the current one: bring every change (and deletion) since
  # an earlier copy into the source before the link replaces it.
  local delete=()
  is_copy "$source" && delete=(--delete)
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[TEST] Eşitle: $target/ -> $source/ ${delete[*]}" "$YELLOW"
  else
    mkdir -p "$source" || return 1
    # --checksum: a file changed within the same second as the copy, at the
    # same size, would pass rsync's size+mtime check and be left stale.
    if ! rsync -aHAX --numeric-ids --checksum "${delete[@]}" "$target/" "$source/"; then
      log "Atlandı: $name eşitlenemedi (rsync hatası), hiçbir şey taşınmadı" "$RED"
      return 1
    fi
    log "Eşitlendi: $target -> $source" "$BLUE"
  fi

  local backup="${target}_backup_$(date +%Y%m%d_%H%M%S)"
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[TEST] Yedek: $name -> $(basename "$backup")${busy:+ (canlı: $busy)}" "$YELLOW"
    return 0
  fi
  if [[ -n "$busy" ]]; then
    # Live: the link is made first under a temporary name, so the path is
    # missing only between two renames, not while a new link is written.
    local tmp="${target}.osc-link-$$"
    ln -s "$source" "$tmp" || return 1
    mv "$target" "$backup" || { rm -f "$tmp"; return 1; }
    mv -T "$tmp" "$target" || { mv "$backup" "$target"; rm -f "$tmp"; return 1; }
    printf '%s|%s|%s\n' "$source" "$backup" "$since" >>"$PENDING_FILE"
    forget_copy "$source"
    log "Canlı bağlandı: $name (eski kopya $(basename "$backup") hâlâ kullanımda: $busy)" "$YELLOW"
    log "  Bu programları yeniden başlatın, sonra: $(basename "$0") finish" "$YELLOW"
    return 2
  fi
  mv "$target" "$backup" || return 1
  forget_copy "$source"
  log "Yedeklendi: $(basename "$backup")" "$YELLOW"
}

# After a live switch: once nothing uses the moved-aside copy any more, copy
# into the source every file the old programs wrote there after the switch.
# A file the new side changed too keeps the source version, and the old one is
# kept next to it as <file>.osc-old-<time>, so neither side's write is lost.
finish_links() {
  [[ "$DRY_RUN" == "true" ]] && log "=== TEST MODU ===" "$YELLOW"
  log "\n=== Uzlaştırma ===" "$BLUE"
  [[ -s "$PENDING_FILE" ]] || { log "Bekleyen canlı geçiş yok." "$GREEN"; return; }

  local source backup since keep=() busy rel copied conflicts stamp list
  while IFS='|' read -r source backup since; do
    [[ -n "$source" ]] || continue
    if [[ ! -d "$backup" ]]; then
      log "Eski kopya yok, atlandı: $backup" "$YELLOW"
      continue
    fi
    busy="$(users_of "$backup")"
    if [[ -n "$busy" ]]; then
      log "Bekliyor: $(basename "$backup") hâlâ kullanımda: $busy" "$YELLOW"
      keep+=("$source|$backup|$since")
      continue
    fi
    copied=0 conflicts=0 stamp="$(date +%Y%m%d_%H%M%S)"
    list="$(mktemp)"
    while IFS= read -r -d '' rel; do
      rel="${rel#./}"
      if [[ -e "$source/$rel" ]] && cmp -s "$backup/$rel" "$source/$rel"; then
        continue
      fi
      if [[ -e "$source/$rel" && "$(stat -c %Y "$source/$rel")" -ge "$since" ]]; then
        ((conflicts++)) || true
        if [[ "$DRY_RUN" == "true" ]]; then
          log "  [TEST] iki tarafta da değişmiş: $rel" "$YELLOW"
        else
          cp -a "$backup/$rel" "$source/$rel.osc-old-$stamp"
          log "  İki tarafta da değişmiş, eskisi yanında: $rel.osc-old-$stamp" "$YELLOW"
        fi
      else
        printf '%s\0' "$rel" >>"$list"
        ((copied++)) || true
      fi
    done < <(cd "$backup" && find . \( -type f -o -type l \) -newermt "@$since" -print0)
    if [[ "$DRY_RUN" != "true" && -s "$list" ]]; then
      rsync -aHAX --numeric-ids --from0 --files-from="$list" "$backup/" "$source/" || {
        log "HATA: $(basename "$backup") taşınamadı, bekletiliyor" "$RED"
        keep+=("$source|$backup|$since")
        rm -f "$list"
        continue
      }
    fi
    rm -f "$list"
    log "Uzlaştırıldı: $(basename "$backup") -> $source ($copied dosya taşındı, $conflicts çakışma)" "$GREEN"
    log "  Kontrol edip silebilirsiniz: $backup" "$BLUE"
  done <"$PENDING_FILE"

  [[ "$DRY_RUN" == "true" ]] && return
  if ((${#keep[@]})); then printf '%s\n' "${keep[@]}" >"$PENDING_FILE"; else rm -f "$PENDING_FILE"; fi
}

# Create single symlink
create_link() {
  local name="$1"
  local source="$2"
  local target="$3"

  # Create source if missing
  if [[ ! -d "$source" ]]; then
    if [[ "$FORCE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
      if [[ "$DRY_RUN" == "true" ]]; then
        log "[TEST] Kaynak oluştur: $source" "$YELLOW"
      else
        mkdir -p "$source"
        log "Kaynak oluşturuldu: $source" "$BLUE"
      fi
    else
      read -p "Kaynak dizin oluşturulsun mu ($source)? (e/h): " -n 1 -r
      echo
      if [[ $REPLY =~ ^[Ee]$ ]]; then
        mkdir -p "$source"
      else
        log "Atlandı: $name" "$YELLOW"
        return
      fi
    fi
  fi

  # Check existing link
  if [[ -L "$target" ]]; then
    if [[ "$(readlink "$target")" == "$source" ]]; then
      log "Zaten var: $name" "$GREEN"
      return
    else
      [[ "$FORCE" == "true" ]] && rm "$target" || return
    fi
  fi

  # Create link
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[TEST] Link: $name" "$YELLOW"
  else
    ln -s "$source" "$target"
    log "Oluşturuldu: $name" "$GREEN"
  fi
}

# Create all links
create_links() {
  [[ "$DRY_RUN" == "true" ]] && log "=== TEST MODU ===" "$YELLOW"

  log "\n=== Link Oluşturma ===" "$BLUE"

  local rc
  while IFS='|' read -r name source target; do
    backup_dir "$name" "$source" "$target"
    rc=$?
    ((rc == 2)) && continue # linked live already
    ((rc == 0)) || continue
    create_link "$name" "$source" "$target"
  done < <(iter_links)
  [[ -s "$PENDING_FILE" ]] && log "\nCanlı geçişler var: programlar kapanınca $(basename "$0") finish" "$YELLOW"

  log "\nTamamlandı!" "$GREEN"
}

# Remove all links
remove_links() {
  [[ "$DRY_RUN" == "true" ]] && log "=== TEST MODU ===" "$YELLOW"

  log "\n=== Link Kaldırma ===" "$BLUE"

  while IFS='|' read -r name source target; do
    if [[ -L "$target" ]]; then
      if [[ "$DRY_RUN" == "true" ]]; then
        log "[TEST] Kaldır: $name" "$YELLOW"
      else
        rm "$target"
        log "Kaldırıldı: $name" "$GREEN"
      fi
    else
      log "Link değil: $name" "$YELLOW"
    fi
  done < <(iter_links)

  log "\nTamamlandı!" "$GREEN"
}

# Main
main() {
  local command="create"

  # Parse arguments directly in main
  while [[ $# -gt 0 ]]; do
    case $1 in
    copy | create | finish | remove | status)
      command="$1"
      shift
      ;;
    -d | --dry-run)
      DRY_RUN=true
      shift
      ;;
    -f | --force)
      FORCE=true
      shift
      ;;
    -l | --live)
      LIVE=true
      shift
      ;;
    -h | --help)
      show_help
      exit 0
      ;;
    *)
      error "Bilinmeyen parametre: $1"
      ;;
    esac
  done

  check_setup

  case "$command" in
  "copy") copy_dirs ;;
  "create") create_links ;;
  "finish") finish_links ;;
  "remove") remove_links ;;
  "status") show_status ;;
  esac
}

main "$@"
