#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  mango-here <tag> <monitor> <target>
  mango-here all [target,target,...]

If the mapped app is already open, move/focus it on the current workspace.
Otherwise, launch it.

The `all` mode gathers every workspace target marked includeInAll in the shared
workspace manifest, then finishes on Kenp.
EOF
}

declare -A VIEW_PRIMARY=()
declare -A VIEW_ADDITIONAL=()
SELECTED_MONITOR=""

focus_sleep() {
  sleep 0.03
}

selected_monitor() {
  mmsg -g -o 2>/dev/null | awk '$2 == "selmon" && $3 == "1" { print $1; exit }'
}

primary_active_tag() {
  local selected="$1"
  mmsg -g -t 2>/dev/null | awk -v mon="$selected" '$1 == mon && $2 == "tag" && $4 == "1" { print $3; exit }'
}

snapshot_views() {
  local mon active_tag

  VIEW_PRIMARY=()
  VIEW_ADDITIONAL=()
  SELECTED_MONITOR="$(selected_monitor 2>/dev/null || true)"

  while read -r mon active_tag; do
    [[ -n "$mon" && -n "$active_tag" ]] || continue
    if [[ -z "${VIEW_PRIMARY[$mon]+x}" ]]; then
      VIEW_PRIMARY[$mon]="$active_tag"
    else
      VIEW_ADDITIONAL[$mon]="${VIEW_ADDITIONAL[$mon]:-} $active_tag"
    fi
  done < <(
    mmsg -g -t 2>/dev/null | awk '$2 == "tag" && (($4 + 0) % 2) == 1 { print $1, $3 }'
  )
}

restore_views() {
  local skip_monitor="${1:-}"
  local mon active_tag

  for mon in "${!VIEW_PRIMARY[@]}"; do
    if [[ -n "$skip_monitor" && "$mon" == "$skip_monitor" ]]; then
      continue
    fi
    mmsg -s -o "$mon" -t "${VIEW_PRIMARY[$mon]}" >/dev/null 2>&1 || true
    for active_tag in ${VIEW_ADDITIONAL[$mon]:-}; do
      mmsg -s -o "$mon" -t "${active_tag}+" >/dev/null 2>&1 || true
    done
  done

  if [[ -z "$skip_monitor" && -n "${SELECTED_MONITOR:-}" ]]; then
    mmsg -d "focusmon,${SELECTED_MONITOR}" >/dev/null 2>&1 || true
  fi
}

focused_appid_on_monitor() {
  local mon="$1"
  mmsg -g -c 2>/dev/null | awk -v mon="$mon" '
    $1 == mon && $2 == "appid" {
      sub($1 FS $2 FS, "")
      print
      exit
    }
  '
}

focused_title_on_monitor() {
  local mon="$1"
  mmsg -g -c 2>/dev/null | awk -v mon="$mon" '
    $1 == mon && $2 == "title" {
      sub($1 FS $2 FS, "")
      print
      exit
    }
  '
}

clients_in_tag() {
  local mon="$1"
  local active_tag="$2"
  mmsg -g -t 2>/dev/null | awk -v mon="$mon" -v active_tag="$active_tag" '
    $1 == mon && $2 == "tag" && $3 == active_tag { print $5; exit }
  '
}

target_regex() {
  local value="$1"
  local regex=""

  if command -v osc-workspace-launch >/dev/null 2>&1; then
    regex="$(osc-workspace-launch focus-regex "$value" 2>/dev/null || true)"
    if [[ -n "$regex" ]]; then
      printf '%s\n' "$regex"
      return 0
    fi
  fi

  case "$value" in
    Kenp) printf '%s\n' '^Kenp$' ;;
    TmuxKenp) printf '%s\n' '^TmuxKenp$' ;;
    Ai) printf '%s\n' '^Ai$' ;;
    CompecTA) printf '%s\n' '^CompecTA$' ;;
    WebCord) printf '%s\n' '^WebCord$' ;;
    org.telegram.desktop) printf '%s\n' '^(org\.telegram\.desktop|TelegramDesktop)$' ;;
    brave-youtube.com__-Default) printf '%s\n' '^brave-youtube\.com__-Default$' ;;
    spotify) printf '%s\n' '^(spotify|Spotify|com\.spotify\.Client)$' ;;
    ferdium) printf '%s\n' '^(ferdium|Ferdium)$' ;;
    *)
      printf '%s\n' "$value" | sed -E 's/[][(){}.^$*+?|\\]/\\&/g'
      ;;
  esac
}

matches_target() {
  local regex="$1"
  local appid="$2"
  local title="$3"

  [[ "$appid" =~ $regex ]] || [[ "$title" =~ $regex ]]
}

focus_match_on_tag() {
  local mon="$1"
  local active_tag="$2"
  local regex="$3"
  local count appid title

  mmsg -d "focusmon,${mon}" >/dev/null 2>&1 || true
  mmsg -s -o "$mon" -t "$active_tag" >/dev/null 2>&1 || true
  focus_sleep

  count="$(clients_in_tag "$mon" "$active_tag" 2>/dev/null || true)"
  if [[ ! "$count" =~ ^[0-9]+$ || "$count" -lt 1 ]]; then
    count=1
  fi

  while [[ "$count" -gt 0 ]]; do
    appid="$(focused_appid_on_monitor "$mon" 2>/dev/null || true)"
    title="$(focused_title_on_monitor "$mon" 2>/dev/null || true)"
    if matches_target "$regex" "$appid" "$title"; then
      return 0
    fi

    count=$((count - 1))
    if [[ "$count" -gt 0 ]]; then
      mmsg -d "focusstack,next" >/dev/null 2>&1 || true
      focus_sleep
    fi
  done

  return 1
}

launch_candidates() {
  if command -v osc-workspace-launch >/dev/null 2>&1; then
    osc-workspace-launch candidates "${target}" 2>/dev/null || true
    return 0
  fi

  case "${target}" in
    discord) printf '%s\n' "start-discord" ;;
    kitty) printf '%s\n' "kitty" ;;
    *) printf '%s\n' "${target}" ;;
  esac
}

run_detached_cmd() {
  local cmd="$1"
  local bin=""
  local launch_path=""

  if bin="$(command -v "$cmd" 2>/dev/null)"; then
    :
  elif [[ -x "$HOME/.local/bin/$cmd" ]]; then
    bin="$HOME/.local/bin/$cmd"
  else
    return 1
  fi

  launch_path="$HOME/.local/bin:$HOME/bin:/usr/local/bin:/usr/bin:${PATH:-}"
  PATH="$launch_path" "$bin" >/dev/null 2>&1 &
  disown || true
  return 0
}

launch_target() {
  local candidate=""
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    if run_detached_cmd "$candidate"; then
      return 0
    fi
  done < <(launch_candidates)

  return 1
}

default_all_targets() {
  printf '%s\n' \
    "Kenp" \
    "TmuxKenp" \
    "Ai" \
    "CompecTA" \
    "WebCord" \
    "brave-youtube.com__-Default" \
    "spotify" \
    "ferdium"
}

gather_all_targets() {
  local list="${1:-}"
  local gathered=""

  if [[ -n "${list}" ]]; then
    printf '%s\n' "${list}" | tr ',' '\n' | awk 'NF { print }'
    return 0
  fi

  if command -v osc-workspace-launch >/dev/null 2>&1; then
    gathered="$(osc-workspace-launch gather-targets 2>/dev/null || true)"
  fi

  if [[ -n "${gathered//[[:space:]]/}" ]]; then
    printf '%s\n' "${gathered}"
  else
    default_all_targets
  fi
}

run_single_target() {
  target="$1"

  local current_monitor current_tag regex found scan_monitor scan_tag client_count

  current_monitor="$(selected_monitor 2>/dev/null || true)"
  current_tag="$(primary_active_tag "${current_monitor:-}" 2>/dev/null || true)"
  regex="$(target_regex "${target}")"

  if [[ -n "${current_monitor:-}" && -n "${current_tag:-}" ]]; then
    if focus_match_on_tag "$current_monitor" "$current_tag" "$regex"; then
      return 0
    fi

    snapshot_views

    found=0
    while read -r scan_monitor scan_tag client_count; do
      [[ -n "$scan_monitor" && -n "$scan_tag" ]] || continue
      if [[ "$scan_monitor" == "$current_monitor" && "$scan_tag" == "$current_tag" ]]; then
        continue
      fi
      if focus_match_on_tag "$scan_monitor" "$scan_tag" "$regex"; then
        found=1
        break
      fi
    done < <(
      mmsg -g -t 2>/dev/null | awk '$2 == "tag" && $5 > 0 { print $1, $3, $5 }'
    )

    if [[ "$found" -eq 1 ]]; then
      mmsg -d "tagcrossmon,${current_tag},${current_monitor}" >/dev/null 2>&1 || true
      restore_views "$current_monitor"
      mmsg -d "focusmon,${current_monitor}" >/dev/null 2>&1 || true
      return 0
    fi

    restore_views
  fi

  if launch_target; then
    return 0
  fi

  echo "unable to find or launch target: ${target}" >&2
  return 1
}

run_all_targets() {
  local list="${1:-}"
  local app=""
  local status=0

  while IFS= read -r app; do
    [[ -n "${app}" ]] || continue
    [[ "${app}" == "Kenp" ]] && continue
    run_single_target "${app}" || status=1
  done < <(gather_all_targets "${list}")

  run_single_target "Kenp" || status=1
  return "${status}"
}

case "${1:-}" in
  -h|--help|help|"")
    usage
    ;;
  all)
    command -v mmsg >/dev/null 2>&1 || {
      echo "mmsg is required" >&2
      exit 1
    }
    [[ $# -le 2 ]] || {
      usage >&2
      exit 2
    }
    run_all_targets "${2:-}"
    ;;
  *)
    command -v mmsg >/dev/null 2>&1 || {
      echo "mmsg is required" >&2
      exit 1
    }
    [[ $# -eq 3 ]] || {
      usage >&2
      exit 2
    }
    tag="$1"
    monitor="$2"
    target="$3"
    [[ "${tag}" =~ ^[1-9]$ ]] || {
      echo "tag must be between 1 and 9" >&2
      exit 2
    }
    [[ -n "${monitor}" ]] || {
      echo "monitor is required" >&2
      exit 2
    }
    run_single_target "${target}"
    ;;
esac
