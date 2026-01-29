# FZF defaults (theme + behavior). Keep shell-specific bindings in ~/.zshrc.

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
