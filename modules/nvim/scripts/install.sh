#!/usr/bin/env bash
set -euo pipefail

real_user="${SUDO_USER:-$(id -un)}"
user_home="$(getent passwd "$real_user" | cut -d: -f6 2>/dev/null || true)"
if [[ -z "${user_home:-}" ]]; then
  user_home="$(eval echo "~$real_user")"
fi

bin_dir="${user_home}/.local/bin"

install_vim_symlink() {
  if [[ ! -x /usr/bin/nvim ]]; then
    echo "nvim binary not found at /usr/bin/nvim"
    return 1
  fi

  mkdir -p "$bin_dir"
  ln -sfn /usr/bin/nvim "${bin_dir}/vim"

  if [[ "$(id -u)" -eq 0 ]]; then
    local user_group
    user_group="$(id -gn "$real_user" 2>/dev/null || true)"
    chown "$real_user:${user_group:-$real_user}" "$bin_dir" || true
    chown -h "$real_user:${user_group:-$real_user}" "${bin_dir}/vim" || true
    chmod 755 "$bin_dir" || true
  fi
}

install_vim_symlink
