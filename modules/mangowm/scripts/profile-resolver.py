#!/usr/bin/env python3
"""Resolve the best MangoWM monitor profile for connected outputs."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

import yaml


def command_lines(command: list[str]) -> list[str]:
    try:
        output = subprocess.check_output(command, text=True, stderr=subprocess.DEVNULL)
    except Exception:
        return []
    return [line.strip() for line in output.splitlines() if line.strip()]


def connected_outputs_from_system() -> set[str]:
    outputs = set(command_lines(["mmsg", "-O"]))
    if outputs:
        return outputs

    wlr_lines = command_lines(["wlr-randr"])
    return {
        line.split()[0]
        for line in wlr_lines
        if line and not line[0].isspace()
    }


def monitor_name_for_mango(monitor: dict) -> str:
    return monitor.get("mango_name", monitor.get("wayland_name", monitor["id"]))


def profile_output_names(profile: dict, monitors_by_id: dict[str, dict]) -> set[str]:
    names = set()
    for output in profile.get("outputs", []):
        monitor_id = output.get("monitor")
        if not monitor_id:
            continue
        monitor = monitors_by_id.get(monitor_id)
        if monitor is not None:
            names.add(monitor_name_for_mango(monitor))
    return names


def resolve_profile(manifest: dict, requested: str, connected_outputs: set[str]) -> str:
    profiles = manifest.get("profiles", {})
    monitors_by_id = {
        monitor["id"]: monitor for monitor in manifest.get("monitors", [])
    }

    if requested != "auto":
        if requested not in profiles:
            raise SystemExit(f"Unknown MANGO_MONITOR_PROFILE: {requested}")
        return requested

    if not connected_outputs:
        return "desk" if "desk" in profiles else next(iter(profiles), "")

    scored = []
    for candidate_name, candidate_profile in profiles.items():
        names = profile_output_names(candidate_profile, monitors_by_id)
        if not names:
            continue
        matched = len(names & connected_outputs)
        missing = len(names - connected_outputs)
        extra = len(connected_outputs - names)
        exact_subset = 1 if names <= connected_outputs else 0
        scored.append((exact_subset, matched, -missing, -extra, candidate_name))

    if not scored:
        return "desk" if "desk" in profiles else next(iter(profiles), "")

    scored.sort(reverse=True)
    return scored[0][-1]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--profile", default="desk")
    parser.add_argument(
        "--connected",
        default="",
        help="Comma or newline separated output names. If omitted, mmsg/wlr-randr are queried.",
    )
    args = parser.parse_args()

    manifest = yaml.safe_load(args.manifest.read_text())
    connected = {
        item.strip()
        for chunk in args.connected.splitlines()
        for item in chunk.split(",")
        if item.strip()
    }
    if not connected:
        connected = connected_outputs_from_system()

    selected = resolve_profile(manifest, args.profile, connected)
    if not selected:
        print("No Mango monitor profiles are defined", file=sys.stderr)
        return 1

    print(selected)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
