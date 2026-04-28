#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
MANIFEST="${MANGO_WINDOW_RULES_MANIFEST:-${MODULE_DIR}/rules/window-rules.json}"
OUTPUT_DIR="${MANGO_OUTPUT_DIR:-${MODULE_DIR}/dotfiles/mango/generated}"
RULES_OUT="${MANGO_WINDOW_RULES_OUT:-${OUTPUT_DIR}/window-rules.conf}"

usage() {
	cat <<'EOF'
Usage: render-window-rules.sh [--check] [--out-dir DIR]

Render generated MangoWM window rules from modules/mangowm/rules/window-rules.json.
EOF
}

mode="write"
while (($#)); do
	case "$1" in
	--check)
		mode="check"
		shift
		;;
	--out-dir | --runtime-dir)
		OUTPUT_DIR="$2"
		RULES_OUT="${OUTPUT_DIR}/window-rules.conf"
		shift 2
		;;
	--write)
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		usage >&2
		exit 2
		;;
	esac
done

[[ -r "${MANIFEST}" ]] || {
	echo "Window rules manifest not found: ${MANIFEST}" >&2
	exit 1
}
command -v python3 >/dev/null 2>&1 || {
	echo "python3 is required" >&2
	exit 1
}

tmp_rules="$(mktemp)"
cleanup() {
	rm -f "${tmp_rules}"
}
trap cleanup EXIT

python3 - "${MANIFEST}" "${tmp_rules}" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])
data = json.loads(manifest_path.read_text())

ALLOWED_KEYS = {
    "appid",
    "title",
    "isfloating",
    "isfullscreen",
    "isfakefullscreen",
    "isglobal",
    "isoverlay",
    "isopensilent",
    "istagsilent",
    "force_fakemaximize",
    "ignore_maximize",
    "ignore_minimize",
    "force_tiled_state",
    "noopenmaximized",
    "single_scratchpad",
    "allow_shortcuts_inhibit",
    "indleinhibit_when_focus",
    "width",
    "height",
    "offsetx",
    "offsety",
    "monitor",
    "tags",
    "no_force_center",
    "isnosizehint",
    "noblur",
    "isnoborder",
    "isnoshadow",
    "isnoradius",
    "isnoanimation",
    "focused_opacity",
    "unfocused_opacity",
    "allow_csd",
    "scroller_proportion",
    "scroller_proportion_single",
    "animation_type_open",
    "animation_type_close",
    "nofadein",
    "nofadeout",
    "isterm",
    "noswallow",
    "globalkeybinding",
    "isunglobal",
    "isnamedscratchpad",
    "force_tearing",
}


def normalize_value(value):
    if isinstance(value, bool):
        return str(int(value))
    if isinstance(value, float):
        return f"{value:.3f}".rstrip("0").rstrip(".")
    return str(value)


sections = data.get("sections")
if not isinstance(sections, list):
    raise SystemExit("window-rules.json must contain a top-level 'sections' array")

checksum = hashlib.sha256(
    json.dumps(data, sort_keys=True, separators=(",", ":")).encode()
).hexdigest()

lines = [
    "# Generated from modules/mangowm/rules/window-rules.json.",
    "# Update the manifest and rerun modules/mangowm/scripts/render-window-rules.sh.",
    f"# Source checksum: {checksum}",
    "",
]

for section_index, section in enumerate(sections, start=1):
    if not isinstance(section, dict):
        raise SystemExit(f"section {section_index} must be an object")
    comment = section.get("comment", "")
    if comment:
        lines.append(f"# {comment}")
    rules = section.get("rules", [])
    if not isinstance(rules, list):
        raise SystemExit(f"section {section_index} rules must be an array")
    for rule_index, rule in enumerate(rules, start=1):
        if not isinstance(rule, dict):
            raise SystemExit(f"section {section_index} rule {rule_index} must be an object")
        unknown = sorted(set(rule) - ALLOWED_KEYS)
        if unknown:
            raise SystemExit(
                f"section {section_index} rule {rule_index} has unknown keys: {', '.join(unknown)}"
            )
        if not ("appid" in rule or "title" in rule):
            raise SystemExit(f"section {section_index} rule {rule_index} must match appid or title")
        parts = [f"{key}:{normalize_value(value)}" for key, value in rule.items()]
        lines.append("windowrule=" + ",".join(parts))
    lines.append("")

out_path.write_text("\n".join(lines).rstrip() + "\n")
PY

if [[ "${mode}" == "check" ]]; then
	diff -u "${RULES_OUT}" "${tmp_rules}"
	exit 0
fi

install -D -m 644 "${tmp_rules}" "${RULES_OUT}"
