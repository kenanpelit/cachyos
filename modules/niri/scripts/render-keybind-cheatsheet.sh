#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${NIRI_CONFIG_SOURCE:-${MODULE_DIR}/dotfiles/niri/config.kdl}"
OUTPUT_DIR="${NIRI_OUTPUT_DIR:-${MODULE_DIR}/dotfiles/niri/generated}"
CHEATSHEET_OUT="${NIRI_KEYBIND_CHEATSHEET_OUT:-${OUTPUT_DIR}/keybind-cheatsheet.conf}"

usage() {
  cat <<'EOF'
Usage: render-keybind-cheatsheet.sh [--check] [--out-dir DIR] [--runtime-dir DIR]

Render a Niri keybind cheatsheet in the same Hyprland-style format used by the
Noctalia keybind-cheatsheet plugin. The live plugin can parse Niri KDL directly,
but this generated artifact gives the Niri module the same drift/metadata guard
that the Mango module already has.
EOF
}

mode="write"
while (($#)); do
  case "$1" in
    --check)
      mode="check"
      shift
      ;;
    --out-dir)
      OUTPUT_DIR="$2"
      CHEATSHEET_OUT="${OUTPUT_DIR}/keybind-cheatsheet.conf"
      shift 2
      ;;
    --runtime-dir)
      OUTPUT_DIR="$2"
      CHEATSHEET_OUT="${OUTPUT_DIR}/keybind-cheatsheet.conf"
      shift 2
      ;;
    --config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    --write)
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

[[ -r "${CONFIG_FILE}" ]] || {
  echo "Niri config file not found: ${CONFIG_FILE}" >&2
  exit 1
}
command -v python3 >/dev/null 2>&1 || {
  echo "python3 is required for render-keybind-cheatsheet.sh" >&2
  exit 1
}

tmp_cheatsheet="$(mktemp)"
cleanup() {
  rm -f "${tmp_cheatsheet}"
}
trap cleanup EXIT

python3 - "${CONFIG_FILE}" "${tmp_cheatsheet}" <<'PY'
import re
import sys
from collections import OrderedDict
from pathlib import Path

config_path = Path(sys.argv[1]).resolve()
out_path = Path(sys.argv[2])

category_order = [
    "Workspaces",
    "Navigation",
    "Window Management",
    "Layout",
    "Scratchpad",
    "Noctalia",
    "Applications",
    "Monitors",
    "Media",
    "Screenshots",
    "Cast",
    "System",
    "Other",
]

sections = OrderedDict((category, []) for category in category_order)
seen_entries = set()
parsed_files = set()


def resolve_include(base: Path, raw_path: str) -> Path:
    expanded = raw_path.replace("~", str(Path.home()), 1) if raw_path.startswith("~/") else raw_path
    path = Path(expanded)
    if path.is_absolute():
        return path
    return (base.parent / path).resolve()


def collect_file(path: Path) -> list[tuple[Path, str]]:
    if path in parsed_files or not path.exists() or not path.is_file():
        return []
    parsed_files.add(path)
    text = path.read_text(errors="replace")
    collected = [(path, text)]
    for match in re.finditer(r'^\s*include(?:\s+optional=true)?\s+"([^"]+)"', text, re.MULTILINE):
        include_path = resolve_include(path, match.group(1))
        collected.extend(collect_file(include_path))
    return collected


def display_key_part(part: str) -> str:
    mapping = {
        "Mod": "SUPER",
        "Alt": "ALT",
        "Ctrl": "CTRL",
        "Control": "CTRL",
        "Shift": "SHIFT",
        "Return": "ENTER",
        "BackSpace": "BACKSPACE",
        "Escape": "ESC",
        "Delete": "DEL",
        "Page_Up": "PRIOR",
        "Page_Down": "NEXT",
        "Slash": "slash",
        "Comma": "comma",
        "Space": "space",
        "WheelScrollDown": "WheelDown",
        "WheelScrollUp": "WheelUp",
        "WheelScrollLeft": "WheelLeft",
        "WheelScrollRight": "WheelRight",
        "MouseMiddle": "MouseMiddle",
    }
    return mapping.get(part, part)


def split_combo(combo: str) -> tuple[str, str]:
    parts = [display_key_part(part) for part in combo.split("+") if part]
    if not parts:
        return "", combo
    if len(parts) == 1:
        return "", parts[0]
    return "+".join(part.upper() for part in parts[:-1]), parts[-1]


def action_text(raw: str) -> str:
    compact = " ".join(raw.replace("\n", " ").split())
    compact = re.sub(r";\s*}\s*$", "", compact)
    compact = compact.rstrip(";").strip()
    compact = compact.replace('"', "")
    return compact


def category_for(title: str, action: str, key: str) -> str:
    probe = f"{title} {action} {key}".lower()
    if "workspace" in probe or title.startswith("Here:"):
        return "Workspaces"
    if any(token in probe for token in ("focus left", "focus right", "focus up", "focus down", "focus-column", "focus-window", "switch windows")):
        return "Navigation"
    if any(token in probe for token in ("scratch", "mark:", "dropdown terminal")):
        return "Scratchpad"
    if any(token in probe for token in ("layout", "preset", "width", "height", "center column", "tabbed", "maximize column", "max to edges")):
        return "Layout"
    if any(token in probe for token in ("close window", "fullscreen", "float", "pin window", "opacity", "consume", "expel", "windowed fullscreen")):
        return "Window Management"
    if any(token in probe for token in ("osc-shell", "launcher", "control center", "notifications", "settings", "dash", "noctalia", "widget:", "keybind")):
        return "Noctalia"
    if any(token in probe for token in ("monitor", "move window next monitor")):
        return "Monitors"
    if any(token in probe for token in ("audio", "volume", "spotify", "mpv", "vlc", "brightness", "wiremix", "media")):
        return "Media"
    if "screenshot" in probe or "print" in key.lower():
        return "Screenshots"
    if "cast" in probe or "pipewire" in probe:
        return "Cast"
    if any(token in probe for token in ("lock", "power", "emergency", "reload config", "session", "doctor", "vpn", "bluetooth")):
        return "System"
    if action.startswith("spawn"):
        return "Applications"
    return "Other"


def add_entry(combo: str, title: str, action: str) -> None:
    mods, key = split_combo(combo)
    description = title or action_text(action)
    if not description:
        return
    category = category_for(description, action, key)
    entry_key = (mods.upper(), key.upper(), description)
    if entry_key in seen_entries:
        return
    seen_entries.add(entry_key)
    sections[category].append((mods.upper(), key, description))


def parse_binds(text: str) -> None:
    in_binds = False
    depth = 0
    pending_key = ""
    pending_attrs = ""
    pending_action = []
    pending_depth = 0

    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("//"):
            continue

        if not in_binds:
            if re.match(r"^binds\s*\{", line):
                in_binds = True
                depth = line.count("{") - line.count("}")
            continue

        if pending_key:
            pending_action.append(line)
            pending_depth += line.count("{") - line.count("}")
            if pending_depth <= 0:
                title_match = re.search(r'hotkey-overlay-title="([^"]+)"', pending_attrs)
                add_entry(pending_key, title_match.group(1) if title_match else "", " ".join(pending_action))
                pending_key = ""
                pending_attrs = ""
                pending_action = []
            continue

        match = re.match(r'^([A-Za-z0-9_+]+)\s*([^{]*)\{(.*)$', line)
        if match:
            key, attrs, action = match.groups()
            local_depth = 1 + action.count("{") - action.count("}")
            if local_depth <= 0:
                title_match = re.search(r'hotkey-overlay-title="([^"]+)"', attrs)
                add_entry(key, title_match.group(1) if title_match else "", action)
            else:
                pending_key = key
                pending_attrs = attrs
                pending_action = [action]
                pending_depth = local_depth

        depth += line.count("{") - line.count("}")
        if depth <= 0:
            in_binds = False


for _, file_text in collect_file(config_path):
    parse_binds(file_text)

lines = [
    "# Generated from modules/niri/dotfiles/niri/config.kdl.",
    "# Parsed recursive includes and rendered in Noctalia's Hyprland-style cheatsheet format.",
    "",
]

category_index = 1
for category, binds in sections.items():
    if not binds:
        continue
    lines.append(f"# {category_index}. {category}")
    for mods, key, description in binds:
        safe_description = description.replace('"', "'")
        lines.append(f'bind = {mods}, {key}, exec, noop #"{safe_description}"')
    lines.append("")
    category_index += 1

out_path.write_text("\n".join(lines).rstrip() + "\n")
PY

if [[ "${mode}" == "check" ]]; then
  diff -u "${CHEATSHEET_OUT}" "${tmp_cheatsheet}"
  exit 0
fi

install -D -m 644 "${tmp_cheatsheet}" "${CHEATSHEET_OUT}"
