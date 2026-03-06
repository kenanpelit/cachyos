#!/usr/bin/env bash
# ==============================================================================
# DCLI Systemd Template Generator (modules/base/lib/systemd-template.sh)
# Generates standardized user service units for Wayland/Niri/Hyprland.
# ==============================================================================

generate_user_service() {
  local name="$1"
  local description="$2"
  local exec_cmd="$3"
  local wm_guard="${4:-niri}" # niri, hyprland, or all
  local type="${5:-simple}"
  
  local out_file="dotfiles/systemd/user/${name}.service"
  mkdir -p "$(dirname "$out_file")"

  cat > "$out_file" <<EOF
[Unit]
Description=${description}
EOF

  if [[ "$wm_guard" == "niri" ]]; then
    cat >> "$out_file" <<EOF
ConditionEnvironment=XDG_CURRENT_DESKTOP=niri
After=niri-ready.service
EOF
  elif [[ "$wm_guard" == "hyprland" ]]; then
    cat >> "$out_file" <<EOF
ConditionEnvironment=XDG_CURRENT_DESKTOP=Hyprland
After=hyprland-session.target
EOF
  fi

  cat >> "$out_file" <<EOF
PartOf=graphical-session.target

[Service]
Type=${type}
ExecStart=${exec_cmd}
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF

  echo "✅ Generated $out_file"
}
