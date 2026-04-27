#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
POLICY_FILE="${NIRI_BACKGROUND_POLICY_FILE:-${MODULE_DIR}/effects/background-policy.json}"
EFFECTS_OUT="${NIRI_BACKGROUND_EFFECTS_OUT:-${MODULE_DIR}/dotfiles/niri/conf/41-background-effects.kdl}"

usage() {
  cat <<'EOF'
Usage: render-background-effects.sh [--check]

Render compositor-side Niri background effects from effects/background-policy.json.
The policy keeps overview, launcher, OSD, and screenshot overlays crisp while
allowing blur only for explicitly listed popup/control surfaces.
EOF
}

mode="write"
case "${1:-}" in
  ""|--write)
    ;;
  --check)
    mode="check"
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

[[ -r "${POLICY_FILE}" ]] || {
  echo "Background policy file not found: ${POLICY_FILE}" >&2
  exit 1
}
command -v python3 >/dev/null 2>&1 || {
  echo "python3 is required for render-background-effects.sh" >&2
  exit 1
}

tmp_effects="$(mktemp)"
cleanup() {
  rm -f "${tmp_effects}"
}
trap cleanup EXIT

python3 - "${POLICY_FILE}" "${tmp_effects}" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

policy_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])
policy = json.loads(policy_path.read_text())

checksum = hashlib.sha256(policy_path.read_bytes()).hexdigest()
blur = policy.get("blur", {})


def require_list(name):
    value = policy.get(name, [])
    if not isinstance(value, list) or not value or not all(isinstance(item, str) and item for item in value):
        raise SystemExit(f"{name} must be a non-empty array of regex strings")
    return value


wallpapers = require_list("wallpaperBackdropNamespaces")
blur_namespaces = require_list("blurNamespaces")
crisp_namespaces = require_list("crispNamespaces")

for key in ("passes", "offset"):
    if not isinstance(blur.get(key), int):
        raise SystemExit(f"blur.{key} must be an integer")
for key in ("noise", "saturation"):
    if not isinstance(blur.get(key), (int, float)):
        raise SystemExit(f"blur.{key} must be numeric")

lines = [
    "// Generated from modules/niri/effects/background-policy.json.",
    "// Update the policy and rerun modules/niri/scripts/render-background-effects.sh.",
    f"// Source checksum: {checksum}",
    "",
    "// Niri 26.04 background effects. Keep this conservative: xray blur is cheap,",
    "// while non-xray blur is still experimental and intentionally not enabled.",
    "",
    "blur {",
    f"  passes {blur['passes']}",
    f"  offset {blur['offset']}",
    f"  noise {blur['noise']}",
    f"  saturation {blur['saturation']}",
    "}",
    "",
    "// Integrate static and Noctalia-backed wallpapers into the overview backdrop.",
    "layer-rule {",
]

for namespace in wallpapers:
    lines.append(f'  match namespace=r#"{namespace}"#')

lines.extend(
    [
        "  place-within-backdrop true",
        "}",
        "",
        "// Noctalia shell surfaces that are allowed to use compositor-side blur.",
        "// Overview, launcher, OSD, and capture overlays are intentionally excluded.",
        "layer-rule {",
    ]
)

for namespace in blur_namespaces:
    lines.append(f'  match namespace=r#"{namespace}"#')

lines.extend(
    [
        "",
        "  geometry-corner-radius 14",
        "",
        "  background-effect {",
        "    blur true",
        "  }",
        "",
        "  popups {",
        "    geometry-corner-radius 12",
        "",
        "    background-effect {",
        "      blur true",
        "    }",
        "  }",
        "}",
        "",
        "// Transient feedback and capture surfaces must stay readable.",
        "layer-rule {",
    ]
)

for namespace in crisp_namespaces:
    lines.append(f'  match namespace=r#"{namespace}"#')

lines.extend(
    [
        "",
        "  background-effect {",
        "    blur false",
        "  }",
        "",
        "  popups {",
        "    background-effect {",
        "      blur false",
        "    }",
        "  }",
        "}",
        "",
    ]
)

out_path.write_text("\n".join(lines))
PY

if [[ "${mode}" == "check" ]]; then
  diff -u "${EFFECTS_OUT}" "${tmp_effects}"
  exit 0
fi

install -D -m 644 "${tmp_effects}" "${EFFECTS_OUT}"
