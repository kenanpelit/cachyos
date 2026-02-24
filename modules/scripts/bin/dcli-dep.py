#!/usr/bin/env python3
import yaml
import os
import sys
from pathlib import Path

CONFIG_DIR = Path.home() / ".config/arch-config"
if "ARCH_CONFIG_DIR" in os.environ:
    CONFIG_DIR = Path(os.environ["ARCH_CONFIG_DIR"])

def load_yaml(path):
    if not path.exists(): return None
    with open(path) as f:
        return yaml.safe_load(f)

def get_module_deps(module_name):
    # Try directory module first
    mod_dir = CONFIG_DIR / "modules" / module_name
    manifest = load_yaml(mod_dir / "module.yaml")
    if manifest:
        return manifest.get("depends_on", [])
    
    # Try legacy yaml module
    mod_file = CONFIG_DIR / "modules" / f"{module_name}.yaml"
    manifest = load_yaml(mod_file)
    if manifest:
        return manifest.get("depends_on", [])
    
    return []

def topological_sort(modules):
    result = []
    visited = set()
    temp_visited = set()

    def visit(m):
        if m in temp_visited:
            print(f"Error: Circular dependency detected involving '{m}'", file=sys.stderr)
            return
        if m not in visited:
            temp_visited.add(m)
            for dep in get_module_deps(m):
                if dep in modules: # Only sort if dep is also enabled
                    visit(dep)
            temp_visited.remove(m)
            visited.add(m)
            result.append(m)

    for module in modules:
        visit(module)
    return result

def main():
    host_config_path = CONFIG_DIR / "hosts/hay.yaml"
    config = load_yaml(host_config_path)
    
    if not config or "enabled_modules" not in config:
        print("Error: Could not load enabled_modules from hay.yaml", file=sys.stderr)
        sys.exit(1)

    enabled = config["enabled_modules"]
    sorted_modules = topological_sort(enabled)

    if enabled == sorted_modules:
        print("✓ Module order is already optimal.")
    else:
        print("⚠ Module order is suboptimal. Reordering based on dependencies...")
        config["enabled_modules"] = sorted_modules
        with open(host_config_path, "w") as f:
            yaml.dump(config, f, sort_keys=False, indent=2)
        print("✓ hay.yaml has been updated and reordered.")

if __name__ == "__main__":
    main()
