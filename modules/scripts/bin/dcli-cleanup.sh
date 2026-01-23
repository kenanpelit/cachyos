#!/usr/bin/env bash
# dcli-cleanup.sh - Cleans up empty directories and unused structures in ~/.cachy

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CACHY_DIR="$HOME/.cachy"
DRY_RUN=0

usage() {
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo
    echo "Options:"
    echo "  --dry-run, -n   Show what would be deleted without actually deleting"
    echo "  --help, -h      Show this help message"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run|-n)
            DRY_RUN=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

if [[ $DRY_RUN -eq 1 ]]; then
    warn "Running in DRY RUN mode. No files will be deleted."
fi

log "Scanning $CACHY_DIR for empty directories..."

# 1. Empty 'dotfiles' and 'scripts' dirs in modules
EMPTY_SUBDIRS=$(find "$CACHY_DIR/modules" -type d \( -name "dotfiles" -o -name "scripts" \) -empty)

if [[ -n "$EMPTY_SUBDIRS" ]]; then
    echo "$EMPTY_SUBDIRS" | while read -r dir; do
        if [[ $DRY_RUN -eq 1 ]]; then
            echo "Would delete: $dir"
        else
            rmdir "$dir"
            echo "Deleted: $dir"
        fi
    done
else
    log "No empty module subdirectories found."
fi

# 2. Completely empty directories (excluding .git)
# -not -path "*/.git/*" protects git internals
# -not -path "*/target/*" protects rust build artifacts (if any)
EMPTY_DIRS=$(find "$CACHY_DIR" -type d -empty -not -path "*/.git/*" -not -path "*/target/*" -not -path "*/node_modules/*")

if [[ -n "$EMPTY_DIRS" ]]; then
    echo "$EMPTY_DIRS" | while read -r dir; do
        # Double check existence (it might have been a parent of a previously deleted dir)
        if [[ -d "$dir" ]]; then
            if [[ $DRY_RUN -eq 1 ]]; then
                echo "Would delete: $dir"
            else
                rmdir "$dir" 2>/dev/null || true # Ignore if not empty anymore
                if [[ ! -d "$dir" ]]; then
                    echo "Deleted: $dir"
                fi
            fi
        fi
    done
else
    log "No other empty directories found."
fi

if [[ $DRY_RUN -eq 0 ]]; then
    success "Cleanup complete."
else
    success "Dry run complete."
fi
