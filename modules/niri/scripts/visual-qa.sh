#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ARTIFACT_DIR="${NIRI_VISUAL_QA_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/niri-visual-qa}"
capture=false

usage() {
  cat <<'EOF'
Usage: visual-qa.sh [--capture]

Run Niri visual guardrails for effect readability. With --capture and a live
Wayland session, also stores a current-screen screenshot for manual comparison.
EOF
}

while (($#)); do
  case "$1" in
    --capture)
      capture=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

"${SCRIPT_DIR}/render-theme.sh" --check
"${SCRIPT_DIR}/render-background-effects.sh" --check

python3 - "${MODULE_DIR}/dotfiles/niri/generated/theme.kdl" "${MODULE_DIR}/dotfiles/niri/conf/41-background-effects.kdl" <<'PY'
import re
import sys
from pathlib import Path

theme = Path(sys.argv[1]).read_text()
effects = Path(sys.argv[2]).read_text()

zoom = float(re.search(r"(?m)^\s*zoom\s+([0-9.]+)\s*$", theme).group(1))
if zoom > 0.35:
    raise SystemExit(f"overview zoom should stay compact for current UX profile, got {zoom}")

for namespace in ("niri-overview-launcher", "noctalia-launcher-overlay", "noctalia-osd", "noctalia-region-selector"):
    pos = effects.find(namespace)
    if pos < 0:
        raise SystemExit(f"missing crisp namespace guard: {namespace}")
    block_start = effects.rfind("layer-rule", 0, pos)
    block_end = effects.find("layer-rule", pos + 1)
    block = effects[block_start:block_end if block_end != -1 else len(effects)]
    if "blur true" in block or "blur false" not in block:
        raise SystemExit(f"namespace is not forced crisp: {namespace}")
PY

if [[ "${capture}" == "true" ]]; then
  mkdir -p "${ARTIFACT_DIR}"
  if command -v grim >/dev/null 2>&1 && [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    grim "${ARTIFACT_DIR}/screen-$(date +%Y%m%d-%H%M%S).png"
    printf 'visual QA screenshot: %s\n' "${ARTIFACT_DIR}"
  else
    printf 'visual QA capture skipped: grim or WAYLAND_DISPLAY missing\n' >&2
  fi
fi

printf 'Niri visual QA guardrails passed.\n'
