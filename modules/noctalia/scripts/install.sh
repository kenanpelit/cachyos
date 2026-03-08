#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/modules/base/lib/core.sh"

if command -v systemctl >/dev/null 2>&1; then
  run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true
fi

# Not: settings.json manipülasyonu dosya yapısını bozabileceği ve dcli sync 
# çakışması yaratabileceği için devre dışı bırakılmıştır.
# Ayarlar artık sadece Noctalia UI üzerinden yönetilmelidir.
