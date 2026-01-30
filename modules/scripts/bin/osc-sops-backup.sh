#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  osc-sops-backup backup [path] [output.enc]
  osc-sops-backup restore <input.enc> [dest_dir]

Defaults:
  backup path:   ~/.config/sops/age
  backup output: ~/.backups/<name>-backup.tar.gz.enc
  restore dest: ~/.config/sops

Notes:
  - Can backup any file or directory.
  - Uses OpenSSL AES-256-CBC with PBKDF2.
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }

command -v openssl >/dev/null 2>&1 || die "openssl not found"
command -v tar >/dev/null 2>&1 || die "tar not found"

action="${1:-}"
shift || true

case "$action" in
  backup)
    src="${1:-$HOME/.config/sops/age}"
    [[ -e "$src" ]] || die "missing: $src"

    name="$(basename "$src")"
    out="${2:-$HOME/.backups/${name}-backup.tar.gz.enc}"
    tmp="/tmp/sops-age-backup.tar.gz"

    mkdir -p "$(dirname "$out")"
    if [[ -d "$src" ]]; then
      tar -czf "$tmp" -C "$(dirname "$src")" "$name"
    else
      tar -czf "$tmp" -C "$(dirname "$src")" "$name"
    fi
    openssl enc -aes-256-cbc -salt -pbkdf2 -in "$tmp" -out "$out"
    rm -f "$tmp"
    echo "Backup written: $out"
    ;;

  restore)
    enc="${1:-}"
    [[ -n "$enc" ]] || { usage; exit 1; }
    [[ -f "$enc" ]] || die "missing: $enc"

    dest="${2:-$HOME/.config/sops}"
    tmp="/tmp/sops-age-backup.tar.gz"

    mkdir -p "$dest"
    openssl enc -d -aes-256-cbc -salt -pbkdf2 -in "$enc" -out "$tmp"
    tar -xzf "$tmp" -C "$dest"
    rm -f "$tmp"
    echo "Restored to: $dest/age"
    ;;

  ""|-h|--help)
    usage
    ;;

  *)
    usage
    exit 1
    ;;
esac
