#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
MANIFEST="${SCRIPT_DIR}/monitors.yaml"

usage() {
  cat <<'EOF'
Usage: render-monitor-assets.sh [--check]

Without arguments, regenerates shared monitor-derived assets for Niri and
Hyprland from shared/wm/monitors.yaml.
With --check, verifies the generated files match the repository copies.
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

tmp_dir="$(mktemp -d)"

cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

python3 - "${MANIFEST}" "${tmp_dir}" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

import yaml

manifest_path = Path(sys.argv[1])
tmp_root = Path(sys.argv[2])
data = yaml.safe_load(manifest_path.read_text())

if not isinstance(data, dict):
    raise SystemExit("shared/wm/monitors.yaml must decode to a mapping")

monitors = data.get("monitors")
profiles = data.get("profiles")
if not isinstance(monitors, list) or not isinstance(profiles, dict):
    raise SystemExit("shared/wm/monitors.yaml must contain 'monitors' and 'profiles'")

checksum_payload = {
    "monitors": monitors,
    "profiles": profiles,
}
checksum = hashlib.sha256(
    json.dumps(checksum_payload, sort_keys=True, separators=(",", ":")).encode()
).hexdigest()


def niri_name_for_selector(selector: str) -> str:
    if selector.startswith("desc:"):
        return selector.split("desc:", 1)[1]
    return selector


def fmt_number(value) -> str:
    if isinstance(value, int):
        return str(value)
    value = float(value)
    if value.is_integer():
        return str(int(value))
    return f"{value:.3f}"


def fmt_proportion(value) -> str:
    return f"{float(value):.3f}"


def write_file(relative_path: str, content: str) -> None:
    path = tmp_root / relative_path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


monitors_by_id = {}
for monitor in monitors:
    if not isinstance(monitor, dict):
        raise SystemExit("Each monitor entry must be a mapping")
    monitor_id = monitor.get("id")
    selector = monitor.get("selector")
    if not monitor_id or not selector:
        raise SystemExit("Each monitor needs 'id' and 'selector'")
    if monitor_id in monitors_by_id:
        raise SystemExit(f"Duplicate monitor id: {monitor_id}")
    monitor = dict(monitor)
    monitor["wayland_name"] = monitor.get(
        "wayland_name", monitor.get("niri_name", niri_name_for_selector(selector))
    )
    monitor["niri_name"] = monitor.get("niri_name", monitor["wayland_name"])
    monitors_by_id[monitor_id] = monitor


outputs_lines = [
    "// Generated from shared/wm/monitors.yaml.",
    "// Update the shared manifest and rerun shared/wm/render-monitor-assets.sh.",
    f"// Source checksum: {checksum}",
    "",
]

for monitor in monitors:
    monitor = monitors_by_id[monitor["id"]]
    position = monitor.get("position", {})
    layout = monitor.get("layout", {})
    hot_corners = monitor.get("hot_corners", [])

    outputs_lines.append(f'output "{monitor["niri_name"]}" {{')
    outputs_lines.append(f'  mode "{monitor["mode"]}"')
    outputs_lines.append(f'  scale {fmt_number(monitor.get("scale", 1))}')
    outputs_lines.append(f'  position x={position.get("x", 0)} y={position.get("y", 0)}')
    if monitor.get("focus_at_startup"):
        outputs_lines.append("  focus-at-startup")
    variable_refresh_rate = monitor.get("variable_refresh_rate")
    if variable_refresh_rate == "on-demand":
        outputs_lines.append("  variable-refresh-rate on-demand=true")
    elif variable_refresh_rate is True:
        outputs_lines.append("  variable-refresh-rate true")
    backdrop_color = monitor.get("backdrop_color")
    if backdrop_color:
        outputs_lines.append(f'  backdrop-color "{backdrop_color}"')
    outputs_lines.append("")
    outputs_lines.append("  hot-corners {")
    if hot_corners:
        for corner in hot_corners:
            outputs_lines.append(f"    {corner}")
    else:
        outputs_lines.append("    off")
    outputs_lines.append("  }")
    outputs_lines.append("")
    outputs_lines.append("  layout {")
    default_column_width = layout.get("default_column_width")
    if default_column_width is not None:
        outputs_lines.append(
            f"    default-column-width {{ proportion {fmt_proportion(default_column_width)}; }}"
        )
        outputs_lines.append("")
    outputs_lines.append("    preset-column-widths {")
    for width in layout.get("preset_column_widths", []):
        outputs_lines.append(f"      proportion {fmt_proportion(width)}")
    outputs_lines.append("    }")
    outputs_lines.append("  }")
    outputs_lines.append("}")
    outputs_lines.append("")

write_file("modules/niri/dotfiles/niri/outputs.kdl", "\n".join(outputs_lines).rstrip() + "\n")

for profile_name, profile in profiles.items():
    if not isinstance(profile, dict):
        raise SystemExit(f"Profile '{profile_name}' must be a mapping")

    profile_lines = [
        f"# Generated from shared/wm/monitors.yaml ({profile_name}).",
        "# Update the shared manifest and rerun shared/wm/render-monitor-assets.sh.",
        f"# Source checksum: {checksum}",
        "",
    ]

    for output in profile.get("outputs", []):
        if not isinstance(output, dict):
            raise SystemExit(f"Profile '{profile_name}' outputs must be mappings")

        selector = output.get("selector", "")
        mode = output.get("mode")
        position = output.get("position")
        scale = output.get("scale")

        if "monitor" in output:
            monitor = monitors_by_id.get(output["monitor"])
            if monitor is None:
                raise SystemExit(
                    f"Unknown monitor '{output['monitor']}' in profile '{profile_name}'"
                )
            selector = monitor["selector"]
            mode = mode or monitor["mode"]
            position = position or f'{monitor["position"]["x"]}x{monitor["position"]["y"]}'
            scale = scale if scale is not None else monitor.get("scale", 1)

        if mode is None or position is None or scale is None:
            raise SystemExit(
                f"Output entries in profile '{profile_name}' need mode/position/scale"
            )

        profile_lines.append(f"monitor={selector},{mode},{position},{fmt_number(scale)}")

    profile_lines.append("")

    for workspace in profile.get("workspaces", []):
        if not isinstance(workspace, dict):
            raise SystemExit(f"Profile '{profile_name}' workspaces must be mappings")
        workspace_id = workspace.get("id")
        monitor_id = workspace.get("monitor")
        if workspace_id is None or monitor_id is None:
            raise SystemExit(f"Workspace entries in profile '{profile_name}' need id/monitor")
        monitor = monitors_by_id.get(monitor_id)
        if monitor is None:
            raise SystemExit(
                f"Unknown monitor '{monitor_id}' in workspace for profile '{profile_name}'"
            )
        flags = []
        if workspace.get("default"):
            flags.append("default:true")
        if workspace.get("persistent", True):
            flags.append("persistent:true")
        suffix = ""
        if flags:
            suffix = ", " + ", ".join(flags)
        profile_lines.append(
            f'workspace={workspace_id}, monitor:{monitor["selector"]}{suffix}'
        )

    content = "\n".join(profile_lines).rstrip() + "\n"
    write_file(f"modules/hyprland/monitors/profiles/{profile_name}.conf", content)
PY

targets=(
  "modules/niri/dotfiles/niri/outputs.kdl"
  "modules/hyprland/monitors/profiles/desk.conf"
  "modules/hyprland/monitors/profiles/mobile.conf"
  "modules/hyprland/monitors/profiles/single-external.conf"
)

for relative_path in "${targets[@]}"; do
  generated="${tmp_dir}/${relative_path}"
  current="${REPO_ROOT}/${relative_path}"

  if [[ "${mode}" == "check" ]]; then
    diff -u "${current}" "${generated}"
    continue
  fi

  install -D -m 644 "${generated}" "${current}"
done
