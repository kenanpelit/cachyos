# ~/.profile (portable)

# UWSM loads the shell profile before Hyprland session startup.
# Keep session-critical variables out of this file so the compositor's managed
# environment.d stack remains the single source of truth.
export TERM=kitty
export GTK_THEME=catppuccin-mocha-mauve-standard+default

# Added by Antigravity CLI installer
export PATH="$HOME/.local/bin:$PATH"
