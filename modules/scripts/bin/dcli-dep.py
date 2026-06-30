#!/usr/bin/env python3
# ==============================================================================
# Script: dcli-dep.py
# Description: Dependency manager for dcli modules using topological sort.
# Usage: dcli-dep.py [options]
# ==============================================================================
import yaml
import os
import sys
import argparse
from pathlib import Path

# Configuration paths
CONFIG_DIR = Path.home() / ".config/dcli"
if "ARCH_CONFIG_DIR" in os.environ:
    CONFIG_DIR = Path(os.environ["ARCH_CONFIG_DIR"])

def load_yaml(path):
    if not path.exists(): return None
    with open(path) as f:
        return yaml.safe_load(f)

def get_module_deps(module_name):
    """
    Tries to find the dependency list for a given module.
    Checks directory modules (module.yaml) and legacy modules (.yaml).
    """
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
    """
    Performs a topological sort on the provided list of modules
    using the dependency information from each module's manifest.
    """
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
                # Only process dependencies that are also in the enabled list
                if dep in modules:
                    visit(dep)
            temp_visited.remove(m)
            visited.add(m)
            result.append(m)

    for module in modules:
        visit(module)
    return result

def main():
    parser = argparse.ArgumentParser(
        description="dcli-dep: A dependency manager for dcli modules.",
        formatter_class=argparse.RawTextHelpFormatter,
        epilog="""
Neden Gerekli?
--------------
dcli modülleri (niri, ai, base vb.) genellikle birbirlerine ihtiyaç duyar. 
Eğer 'ai' modülü, bağımlı olduğu 'user-services' modülünden önce kurulmaya 
çalışılırsa, kurulum hataları oluşabilir.

Ne Yapar?
---------
1. hosts/hay.yaml dosyasındaki 'enabled_modules' listesini okur.
2. Her modülün 'depends_on' (bağımlılık) bilgilerini manifest dosyalarından tarar.
3. Topolojik Sıralama algoritması kullanarak en ideal kurulum sırasını hesaplar.
4. Eğer mevcut sıra hatalıysa, hay.yaml dosyasını otomatik olarak günceller.

Kullanım:
---------
$ dcli-dep          # Sıralamayı kontrol eder ve gerekirse düzeltir.
$ dcli-dep --help   # Bu yardım mesajını görüntüler.
"""
    )
    
    # Trigger parsing to show help if --help is passed
    parser.parse_args()

    host_config_path = CONFIG_DIR / "hosts/hay.yaml"
    config = load_yaml(host_config_path)
    
    if not config or "enabled_modules" not in config:
        print(f"Error: Could not load enabled_modules from {host_config_path}", file=sys.stderr)
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
