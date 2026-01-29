# FZF defaults (theme + behavior). Keep shell-specific bindings in shell rc.

# Catppuccin Mocha palette
FZF_DEFAULT_OPTS="\
--color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
--color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
--color=marker:#a6e3a1,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8 \
--color=border:#6c7086,label:#cdd6f4,query:#cdd6f4 \
--color=selected-bg:#313244,selected-fg:#cdd6f4 \
--border=rounded \
--border-label= \
--preview-window=right:60%:wrap,border-rounded \
--prompt=❯ \
--marker=✓ \
--pointer=▶ \
--separator=─ \
--scrollbar=│ \
--info=inline \
--height=80% \
--layout=reverse \
--multi \
--cycle \
--scroll-off=5 \
--bind=ctrl-/:toggle-preview \
--bind=ctrl-u:preview-half-page-up \
--bind=ctrl-d:preview-half-page-down \
--bind=ctrl-a:select-all \
--bind=ctrl-x:deselect-all \
--bind=ctrl-space:toggle+down \
--bind=alt-w:toggle-preview-wrap \
--no-scrollbar"
export FZF_DEFAULT_OPTS

: "${FZF_PREVIEW_IMAGE_HANDLER:=chafa}"
export FZF_PREVIEW_IMAGE_HANDLER

# Completion trigger and options
: "${FZF_COMPLETION_TRIGGER:=**}"
: "${FZF_COMPLETION_OPTS:=--border=rounded --info=inline}"
export FZF_COMPLETION_TRIGGER FZF_COMPLETION_OPTS

# Default search command
if command -v rg >/dev/null 2>&1; then
  export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!{.git,.cache,node_modules}/*"'
elif command -v fd >/dev/null 2>&1; then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --strip-cwd-prefix -E .git -E .cache -E node_modules'
fi

# CTRL-T and ALT-C commands (fd-based)
if command -v fd >/dev/null 2>&1; then
  export FZF_CTRL_T_COMMAND='fd --type f --type d --hidden --follow --strip-cwd-prefix -E .git -E .cache -E node_modules'
  export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --strip-cwd-prefix -E .git -E .cache -E node_modules'
fi

# CTRL-T: file/dir picker + preview
export FZF_CTRL_T_OPTS="\
--preview '[[ -d {} ]] && eza -T -L2 --icons --color=always {} || bat -n --color=always -r :500 {}' \
--preview-window 'right:60%:wrap' \
--bind 'ctrl-/:change-preview-window(down|hidden|)'"

# ALT-C: directory picker + tree preview
export FZF_ALT_C_OPTS="\
--preview 'eza -T -L3 --icons --color=always --group-directories-first {}' \
--preview-window 'right:60%' \
--bind 'ctrl-/:change-preview-window(down|hidden|)'"

# CTRL-R: history search with small preview
export FZF_CTRL_R_OPTS="\
--preview 'echo {}' \
--preview-window 'down:3:hidden:wrap' \
--bind '?:toggle-preview' \
--exact"
