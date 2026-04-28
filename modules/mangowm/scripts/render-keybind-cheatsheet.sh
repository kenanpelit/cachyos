#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${MODULE_DIR}/../.." && pwd)"
source "${REPO_ROOT}/modules/base/lib/core.sh"

BINDS_FILE="${MANGO_BINDS_FILE:-${MODULE_DIR}/dotfiles/mango/conf.d/50-binds.conf}"
PROFILE_MANIFEST="${MANGO_PROFILE_MANIFEST:-${MODULE_DIR}/profiles/profile.env}"
SHARED_MONITOR_MANIFEST="${MANGO_SHARED_MONITOR_MANIFEST:-${REPO_ROOT}/shared/wm/monitors.yaml}"
WORKSPACE_MAP_FILE="${MANGO_WORKSPACE_MAP_FILE:-${REPO_ROOT}/shared/wm/workspaces.json}"
OUTPUT_DIR="${MANGO_OUTPUT_DIR:-${MODULE_DIR}/dotfiles/mango/generated}"
CHEATSHEET_OUT="${MANGO_KEYBIND_CHEATSHEET_OUT:-${OUTPUT_DIR}/keybind-cheatsheet.conf}"
PROFILE_RESOLVER="${MODULE_DIR}/scripts/profile-resolver.py"

usage() {
	cat <<'EOF'
Usage: render-keybind-cheatsheet.sh [--check] [--out-dir DIR]

Render a MangoWM keybind cheatsheet in a Hyprland-style format that the
Noctalia keybind-cheatsheet plugin can parse while running under Mango.
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

[[ -r "${BINDS_FILE}" ]] || die "Bind file not found: ${BINDS_FILE}"
[[ -r "${PROFILE_MANIFEST}" ]] || die "Profile manifest not found: ${PROFILE_MANIFEST}"
[[ -r "${SHARED_MONITOR_MANIFEST}" ]] || die "Shared monitor manifest not found: ${SHARED_MONITOR_MANIFEST}"
[[ -r "${WORKSPACE_MAP_FILE}" ]] || die "Workspace map not found: ${WORKSPACE_MAP_FILE}"
command -v python3 >/dev/null 2>&1 || die "python3 is required"
[[ -x "${PROFILE_RESOLVER}" ]] || die "Profile resolver not executable: ${PROFILE_RESOLVER}"

# shellcheck source=/dev/null
source "${PROFILE_MANIFEST}"

: "${MANGO_MONITOR_PROFILE:=desk}"

selected_profile_name="$("${PROFILE_RESOLVER}" --manifest "${SHARED_MONITOR_MANIFEST}" --profile "${MANGO_MONITOR_PROFILE}")"

tmp_cheatsheet="$(mktemp)"
cleanup() {
	rm -f "${tmp_cheatsheet}"
}
trap cleanup EXIT

python3 - "${BINDS_FILE}" "${SHARED_MONITOR_MANIFEST}" "${WORKSPACE_MAP_FILE}" "${selected_profile_name}" "${tmp_cheatsheet}" <<'PY'
import json
import sys
from collections import OrderedDict
from pathlib import Path

import yaml

binds_path = Path(sys.argv[1])
monitors_path = Path(sys.argv[2])
workspace_path = Path(sys.argv[3])
profile_name = sys.argv[4]
out_path = Path(sys.argv[5])

monitor_manifest = yaml.safe_load(monitors_path.read_text())
workspace_manifest = json.loads(workspace_path.read_text())
monitors_by_id = {
    monitor["id"]: monitor for monitor in monitor_manifest.get("monitors", [])
}
workspaces_by_id = {
    str(workspace["id"]): workspace for workspace in workspace_manifest.get("workspaces", [])
}
profiles = monitor_manifest.get("profiles", {})


def monitor_name_for_mango(monitor):
    return monitor.get("mango_name", monitor.get("wayland_name", monitor["id"]))


profile = profiles.get(profile_name)
if profile is None:
    raise SystemExit(f"Unknown MANGO_MONITOR_PROFILE: {profile_name}")

category_order = [
    "Modes",
    "Workspaces",
    "Navigation",
    "Window Management",
    "Layout",
    "Layout Mode",
    "Noctalia",
    "Applications",
    "Monitors",
    "Monitor Mode",
    "Media",
    "Screenshots",
    "System",
    "Other",
]

sections = OrderedDict((category, []) for category in category_order)
seen_entries = set()


def display_key(key: str) -> str:
    code_map = {
        "code:10": "1",
        "code:11": "2",
        "code:12": "3",
        "code:13": "4",
        "code:14": "5",
        "code:15": "6",
        "code:16": "7",
        "code:17": "8",
        "code:18": "9",
        "slash": "/",
        "comma": ",",
        "space": "SPACE",
        "Return": "ENTER",
        "BackSpace": "BACKSPACE",
        "Escape": "ESC",
        "Delete": "DEL",
        "Page_Up": "PRIOR",
        "Page_Down": "NEXT",
        "minus": "-",
        "equal": "=",
        "grave": "`",
        "shift_l": "SHIFT",
    }
    return code_map.get(key, key)


def normalize_mode(mode: str) -> str:
    normalized = (mode or "default").strip().lower()
    return normalized or "default"


def format_mode_name(mode: str) -> str:
    return mode.replace("_", " ").title()


def scoped_category(category: str, mode: str) -> str:
    normalized_mode = normalize_mode(mode)
    if normalized_mode in {"default", "common"}:
        return category
    mode_category = f"{format_mode_name(normalized_mode)} Mode"
    return mode_category if mode_category in sections else "Other"


def add_entry(category: str, mods: str, key: str, description: str, mode: str = "default") -> None:
    category = category if category in sections else "Other"
    rendered_key = display_key(key)
    normalized = (normalize_mode(mode).upper(), mods.upper(), rendered_key.upper())
    if normalized in seen_entries:
        return
    seen_entries.add(normalized)
    sections[category].append((mods.upper(), rendered_key, description))


for workspace_ref in sorted(profile.get("workspaces", []), key=lambda item: int(item["id"])):
    workspace_id = str(workspace_ref["id"])
    workspace = workspaces_by_id.get(workspace_id)
    monitor = monitors_by_id.get(workspace_ref["monitor"])
    if workspace is None or monitor is None:
        continue
    monitor_name = monitor_name_for_mango(monitor)
    here = workspace.get("here", {})
    here_label = here.get("label") or workspace.get("hereLabel") or workspace["name"]
    add_entry(
        "Workspaces",
        "SUPER",
        workspace_id,
        f"Switch to Tag {workspace_id}: {workspace['name']} ({monitor_name})",
    )
    add_entry(
        "Workspaces",
        "SUPER+SHIFT",
        workspace_id,
        f"Move to Tag {workspace_id}: {workspace['name']} ({monitor_name})",
    )
    add_entry("Workspaces", "ALT", workspace_id, f"Here: {here_label}")


spawn_map = {
    "uwsm stop": ("System", "Stop UWSM Session"),
    "mango-monitor-smart focus-next": ("Monitors", "Focus Next Monitor"),
    "mango-monitor-smart move-next": ("Monitors", "Move Window to Next Monitor"),
    "osc-shell ipc call launcher toggle": ("Noctalia", "Launcher"),
    "osc-shell ipc call settings toggle": ("Noctalia", "Settings"),
    "osc-shell ipc call control-center toggle": ("Noctalia", "Control Center"),
    "osc-shell ipc call dash toggle overview": ("Noctalia", "Dash Overview"),
    "handyctl toggle": ("Noctalia", "Handy: Toggle Recording"),
    "handyctl post": ("Noctalia", "Handy: Post Process"),
    "handyctl cancel": ("Noctalia", "Handy: Cancel Recording"),
    "osc-shell ipc call notifications toggleHistory": ("Noctalia", "Notification History"),
    "copyq toggle": ("Applications", "CopyQ Toggle"),
    "osc-shell ipc call launcher windows": ("Noctalia", "Window Switcher"),
    "osc-shell ipc call systemMonitor toggle": ("Noctalia", "System Monitor"),
    "osc-shell ipc call plugin:notes togglePanel": ("Noctalia", "Notes"),
    "osc-shell ipc call plugin:assistant-panel toggle": ("Noctalia", "Assistant Panel"),
    "osc-shell ipc call bar toggle": ("Noctalia", "Toggle Bar"),
    "osc-shell ipc call dock toggle": ("Noctalia", "Toggle Dock"),
    "osc-shell ipc call bar toggleAutoHide": ("Noctalia", "Bar Auto-Hide"),
    "osc-shell ipc call sessionMenu toggle": ("Noctalia", "Session Menu"),
    "osc-shell ipc call idleInhibitor toggle": ("Noctalia", "Idle Inhibitor"),
    "osc-shell ipc call lockScreen lock": ("Noctalia", "Lock Screen"),
    "kitty": ("Applications", "Terminal"),
    "uwsm app -a kitty -- /usr/bin/kitty": ("Applications", "Terminal"),
    "semsumo-daily": ("Applications", "SemsuMo Daily"),
    "uwsm app -a semsumo-daily -- semsumo-daily": ("Applications", "SemsuMo Daily"),
    "nemo": ("Applications", "File Manager"),
    "uwsm app -a nemo -- /usr/bin/nemo": ("Applications", "File Manager"),
    "kitty -e yazi": ("Applications", "Yazi"),
    "uwsm app -a yazi -- /usr/bin/kitty -e yazi": ("Applications", "Yazi"),
    "rofi-launcher": ("Applications", "Rofi Launcher"),
    "uwsm app -a rofi-launcher -- rofi-launcher": ("Applications", "Rofi Launcher"),
    "osc-shell ipc call plugin:custom-commands toggle": ("Noctalia", "Custom Commands"),
    "start-kkenp": ("Applications", "Start KKENP"),
    "uwsm app -a start-kkenp -- start-kkenp": ("Applications", "Start KKENP"),
    "anotes": ("Applications", "Anotes"),
    "uwsm app -a anotes -- anotes": ("Applications", "Anotes"),
    "osc-shell ipc call wallpaper toggle": ("Noctalia", "Wallpaper Panel"),
    "osc-shell ipc call wallpaper next": ("Noctalia", "Next Wallpaper"),
    "osc-shell ipc call wallpaper prev": ("Noctalia", "Previous Wallpaper"),
    "osc-shell ipc call darkMode toggle": ("Noctalia", "Toggle Dark Mode"),
    "osc-shell ipc call nightLight toggle": ("Noctalia", "Toggle Night Light"),
    "osc-shell ipc call plugin:keybind-cheatsheet toggle": ("Noctalia", "Keybind Cheatsheet"),
    "osc-soundctl switch": ("Media", "Switch Audio Output"),
    "osc-soundctl switch-mic": ("Media", "Switch Mic Input"),
    "osc-media spotify toggle": ("Media", "Spotify Toggle"),
    "osc-media spotify next": ("Media", "Spotify Next"),
    "osc-media spotify prev": ("Media", "Spotify Previous"),
    "osc-media mpc toggle": ("Media", "MPC Toggle"),
    "osc-media browser toggle": ("Media", "Browser Media Toggle"),
    "osc-media mpv toggle": ("Media", "MPV Toggle"),
    "mpv-manager play-yt": ("Media", "Play YouTube in MPV"),
    "mpv-manager stick": ("Media", "Stick MPV"),
    "mpv-manager move": ("Media", "Move MPV"),
    "mpv-manager save-yt": ("Media", "Save YouTube to MPV"),
    "mpv-manager wallpaper": ("Media", "Use MPV as Wallpaper"),
    "power-profile": ("System", "Cycle Power Profile"),
    "osc-wiremix": ("Media", "Wiremix"),
    "osc-shell ipc call plugin:clipper toggle": ("Noctalia", "Clipboard History"),
    "uwsm app -a clipse -- /usr/bin/kitty --class clipse -e clipse": ("Applications", "Clipse"),
    "screenshot pick": ("Screenshots", "Color Picker"),
    "bluetooth_toggle": ("System", "Bluetooth Toggle"),
    "osc-mullvad toggle --with-blocky": ("System", "VPN Toggle"),
    "osc-mullvad slot --hold recycle": ("System", "VPN Slot Recycle"),
    "mango-session-refresh": ("System", "Refresh Session"),
    "uwsm app -a mango-doctor -- /usr/bin/kitty --class mango-doctor -e mango-session-doctor": ("System", "Open Session Doctor"),
    "mango-layer-audit --watch --duration 20": ("System", "Layer Audit"),
    "mango-performance-mode gaming": ("System", "Gaming Mode"),
    "mango-performance-mode normal": ("System", "Normal Mode"),
    "mango-performance-mode battery": ("System", "Battery Mode"),
    "mango-overview toggle": ("Window Management", "Toggle Overview"),
    "mango-overview open": ("Window Management", "Open Overview"),
    "mango-overview close": ("Window Management", "Close Overview"),
    "mango-profile-select": ("Monitors", "Detect Monitor Profile"),
    "mango-virtual-output start": ("Monitors", "Start Virtual Output"),
    "mango-virtual-output stop": ("Monitors", "Stop Virtual Output"),
    "mango-virtual-output status": ("Monitors", "Virtual Output Status"),
    "osc-shell ipc call volume increase": ("Media", "Volume Up"),
    "osc-shell ipc call volume decrease": ("Media", "Volume Down"),
    "osc-shell ipc call volume muteOutput": ("Media", "Mute Output"),
    "osc-shell ipc call volume muteInput": ("Media", "Mute Input"),
    "osc-shell ipc call brightness increase": ("System", "Brightness Up"),
    "osc-shell ipc call brightness decrease": ("System", "Brightness Down"),
    "screenshot rec": ("Screenshots", "Screenshot Recorder"),
    "screenshot area": ("Screenshots", "Screenshot Area"),
    "screenshot screen": ("Screenshots", "Screenshot Screen"),
    "screenshot window": ("Screenshots", "Screenshot Window"),
}


def label_for_action(action, args):
    if action == "spawn":
        command = ",".join(args).strip()
        if command in spawn_map:
            return spawn_map[command]
        if command.startswith("mango-tag-smart "):
            return "Workspaces", f"Move to Tag {command.rsplit(' ', 1)[-1]}"
        if command.startswith("mango-workspace-smart "):
            return "Workspaces", f"Switch to Tag {command.split()[1]}"
        if command.startswith("mango-here "):
            return "Workspaces", f"Here: {command.split()[-1]}"
        return "Applications", f"Run: {command}"

    if action == "focusdir":
        return "Navigation", f"Focus {args[0].title()}"
    if action == "focusstack":
        direction = args[0].title() if args else "Next"
        return "Navigation", f"Cycle Window {direction}"
    if action == "focuslast":
        return "Navigation", "Focus Last Window"
    if action == "exchange_client":
        return "Navigation", f"Swap {args[0].title()}"
    if action == "killclient":
        return "Window Management", "Close Window"
    if action == "togglefullscreen":
        return "Window Management", "Toggle Fullscreen"
    if action == "togglefakefullscreen":
        return "Window Management", "Toggle Fake Fullscreen"
    if action == "togglefloating":
        return "Window Management", "Toggle Floating"
    if action == "togglemaximizescreen":
        return "Window Management", "Toggle Maximize"
    if action == "toggleoverlay":
        return "Window Management", "Toggle Overlay"
    if action == "centerwin":
        return "Window Management", "Center Window"
    if action == "toggle_render_border":
        return "Window Management", "Toggle Border"
    if action == "toggle_all_floating":
        return "Window Management", "Toggle All Floating"
    if action == "toggleoverview":
        return "Window Management", "Toggle Overview"
    if action == "toggleglobal":
        return "Window Management", "Toggle Global"
    if action == "toggle_scratchpad":
        return "Window Management", "Toggle Scratchpad"
    if action == "restore_minimized":
        return "Window Management", "Restore Minimized"
    if action == "minimized":
        return "Window Management", "Minimize Focused Window"
    if action == "switch_proportion_preset":
        return "Layout", "Next Proportion Preset"
    if action == "smartmovewin":
        direction = args[0].title() if args else "Window"
        return "Layout", f"Move Floating {direction}"
    if action == "smartresizewin":
        direction = args[0].title() if args else "Window"
        return "Layout", f"Resize Floating {direction}"
    if action == "scroller_stack":
        direction = args[0].title() if args else "Next"
        return "Layout", f"Scroller Stack {direction}"
    if action == "zoom":
        return "Layout", "Zoom Master"
    if action == "set_proportion":
        return "Layout", f"Set Proportion {args[0]}"
    if action == "setmfact":
        return "Layout", f"Adjust Master Width {args[0]}"
    if action == "incnmaster":
        return "Layout", f"Adjust Master Count {args[0]}"
    if action == "setlayout":
        return "Layout", f"Layout: {args[0].replace('_', ' ').title()}"
    if action == "switch_layout":
        return "Layout", "Next Layout"
    if action == "setkeymode":
        target = args[0].replace("_", " ").title() if args else "Default"
        if args and args[0] == "default":
            return "Modes", "Return to Default Mode"
        return "Modes", f"Enter {target} Mode"
    if action == "togglegaps":
        return "Layout", "Toggle Gaps"
    if action == "incgaps":
        return "Layout", f"Adjust Gaps {args[0]}"
    if action == "resizewin":
        return "Layout", f"Resize Window {args[0]}x{args[1]}"
    if action == "spawn_on_empty":
        tag = args[1] if len(args) > 1 else "Tag"
        return "Applications", f"Spawn on Empty Tag {tag}"
    if action == "reload_config":
        return "System", "Reload Mango Config"
    if action == "viewtoleft":
        return "Workspaces", "View Left"
    if action == "viewtoright":
        return "Workspaces", "View Right"
    if action == "viewtoleft_have_client":
        return "Workspaces", "View Left (Occupied)"
    if action == "viewtoright_have_client":
        return "Workspaces", "View Right (Occupied)"
    if action == "tagtoleft":
        return "Workspaces", "Move Tag Left"
    if action == "tagtoright":
        return "Workspaces", "Move Tag Right"
    if action == "focusmon":
        return "Monitors", f"Focus Monitor {args[0].title()}"
    if action == "tagmon":
        return "Monitors", f"Move to Monitor {args[0].title()}"
    if action == "toggle_monitor":
        target = args[0] if args else "Monitor"
        return "Monitors", f"Toggle Monitor {target}"
    if action == "toggle_named_scratchpad":
        scratchpad = args[0].replace("-", " ").title() if args else "Scratchpad"
        return "Applications", f"Toggle {scratchpad}"
    if action == "switch_keyboard_layout":
        return "System", "Switch Keyboard Layout"
    if action == "toggle_trackpad_enable":
        return "System", "Toggle Trackpad"

    return "Other", action.replace("_", " ").title()


current_mode = "default"

for raw_line in binds_path.read_text().splitlines():
    line = raw_line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue

    if line.startswith("keymode="):
        current_mode = normalize_mode(line.split("=", 1)[1])
        continue

    kind, payload = line.split("=", 1)
    if kind not in {"bind", "binds"}:
        continue

    parts = [part.strip() for part in payload.split(",")]
    if len(parts) < 3:
        continue

    mods = parts[0]
    key = parts[1]
    action = parts[2]
    args = parts[3:]
    category, description = label_for_action(action, args)
    add_entry(scoped_category(category, current_mode), mods, key, description, current_mode)


lines = [
    "# Generated from modules/mangowm/dotfiles/mango/conf.d/50-binds.conf.",
    "# Workspace labels come from shared/wm/workspaces.json and shared/wm/monitors.yaml.",
    "# Parsed by the Noctalia keybind-cheatsheet plugin via its Hyprland-style reader.",
    "",
]

category_index = 1
for category, binds in sections.items():
    if not binds:
        continue
    lines.append(f"# {category_index}. {category}")
    for mods, key, description in binds:
        lines.append(f'bind = {mods}, {key}, exec, noop #"{description}"')
    lines.append("")
    category_index += 1

out_path.write_text("\n".join(lines).rstrip() + "\n")
PY

if [[ "${mode}" == "check" ]]; then
	diff -u "${CHEATSHEET_OUT}" "${tmp_cheatsheet}"
	exit 0
fi

run_as_user install -D -m 644 "${tmp_cheatsheet}" "${CHEATSHEET_OUT}"
