# ----------------------------------------------------------------------
# PWD Sanity Check
# 
# Sometimes ZSH starts in a non-existent or plugin directory
# This can happen after directory removal or during plugin updates
# Ensures we always start in a valid location
# ----------------------------------------------------------------------
[[ ! -d "$PWD" ]] && { export PWD="$HOME"; builtin cd "$HOME"; }
[[ "$PWD" == *"/zinit/"* ]] && { export PWD="$HOME"; builtin cd "$HOME"; }



# ----------------------------------------------------------------------
# XDG Base Directory Fallbacks
# 
# Ensure XDG variables are set even if not provided by system
# Some systems don't set these by default
# ----------------------------------------------------------------------
: ${XDG_CONFIG_HOME:=$HOME/.config}
: ${XDG_CACHE_HOME:=$HOME/.cache}
: ${XDG_DATA_HOME:=$HOME/.local/share}
: ${XDG_STATE_HOME:=$HOME/.local/state}
export XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME

# ----------------------------------------------------------------------
# Completion system
# ----------------------------------------------------------------------
autoload -Uz compinit
compinit -d "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/compdump"

# ----------------------------------------------------------------------
# Path Deduplication
# 
# -U flag ensures no duplicates in these arrays
# Prevents path pollution when shell is reloaded or nested
# This is important for performance and correctness
# ----------------------------------------------------------------------
typeset -gU path PATH cdpath CDPATH fpath FPATH manpath MANPATH

# ----------------------------------------------------------------------
# User Binary Paths
# 
# Add user-local bins to PATH with highest priority
# This allows user-installed programs to override system ones
# ----------------------------------------------------------------------
path=(
  $HOME/.local/bin
  $HOME/bin
  $HOME/.iptv/bin
  /usr/local/bin
  $path
)

# ----------------------------------------------------------------------
# TTY Configuration
# 
# Disable flow control (Ctrl-S/Ctrl-Q) for better keybinding support
# Only if we have a real TTY (not in pipe or script)
# This prevents Ctrl-S from freezing terminal
# ----------------------------------------------------------------------
if [[ -t 0 && -t 1 ]]; then
  stty -ixon 2>/dev/null || true
fi

# Use viins keymap as the default.
bindkey -v

# History options should be set in .zshrc and after oh-my-zsh sourcing.
HISTSIZE="200000"
SAVEHIST="150000"

HISTFILE="$HOME/.config/zsh/history"
mkdir -p "$(dirname "$HISTFILE")"

setopt HIST_FCNTL_LOCK

# Enabled history options
enabled_opts=(
  EXTENDED_HISTORY HIST_EXPIRE_DUPS_FIRST HIST_IGNORE_ALL_DUPS HIST_IGNORE_DUPS
  HIST_IGNORE_SPACE SHARE_HISTORY autocd
)
for opt in "${enabled_opts[@]}"; do
  setopt "$opt"
done
unset opt enabled_opts

# Disabled history options
disabled_opts=(
  APPEND_HISTORY HIST_FIND_NO_DUPS HIST_SAVE_NO_DUPS
)
for opt in "${disabled_opts[@]}"; do
  unsetopt "$opt"
done
unset opt disabled_opts

if [[ $options[zle] = on ]] && command -v fzf >/dev/null 2>&1; then
  source <(fzf --zsh)
fi

# Catppuccin theme for zsh-syntax-highlighting (portable)
if [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/zsh/catppuccin_mocha-zsh-syntax-highlighting.zsh" ]]; then
  source "${XDG_CONFIG_HOME:-$HOME/.config}/zsh/catppuccin_mocha-zsh-syntax-highlighting.zsh"
fi

# ----------------------------------------------------------------------
# Zinit Auto-Installation (Robust)
# 
# If Zinit is not installed, try to clone it from GitHub
# If clone fails (offline, no git, firewall), we skip plugin setup
# but keep the shell functional
# 
# The 2>/dev/null suppresses git errors in offline scenarios
# ----------------------------------------------------------------------
if [[ ! -d "$ZINIT_HOME" ]]; then
  mkdir -p "$(dirname "$ZINIT_HOME")"
  if !  git clone --depth=1 \
    https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME" 2>/dev/null; then
    echo "WARNING: Zinit could not be installed; skipping plugin setup." >&2
  fi
fi

# Only proceed with plugin setup if Zinit was successfully installed
if [[ -f "$ZINIT_HOME/zinit.zsh" ]]; then
  # --------------------------------------------------------------------
  # Load Zinit Core
  # 
  # This initializes the plugin manager
  # Must be loaded before any plugins
  # --------------------------------------------------------------------
  source "$ZINIT_HOME/zinit.zsh"

  # --------------------------------------------------------------------
  # Zinit Annexes (Extensions)
  # 
  # These add extra functionality to Zinit:
  # • bin-gem-node: Manage binary programs, gems, and node modules
  # • patch-dl: Apply patches and download files during installation
  # 
  # They enhance Zinit but aren't strictly necessary
  # --------------------------------------------------------------------
  zinit light-mode for \
    zdharma-continuum/zinit-annex-bin-gem-node \
    zdharma-continuum/zinit-annex-patch-dl

  # --------------------------------------------------------------------
  # ZLE Configuration (Zsh Line Editor)
  # 
  # Set up advanced line editing features:
  # • url-quote-magic: Auto-escape special chars in URLs
  # • bracketed-paste-magic: Handle pasted text intelligently
  # • edit-command-line: Edit current command in $EDITOR (Ctrl-x e)
  # --------------------------------------------------------------------
  autoload -Uz url-quote-magic bracketed-paste-magic edit-command-line

  zle -N self-insert url-quote-magic
  zle -N bracketed-paste bracketed-paste-magic
  zle -N edit-command-line

  zstyle ':url-quote-magic:*' url-metas '*?[]^()~#{}='
  zstyle ':bracketed-paste-magic' active-widgets '.self-*'

  bindkey '^xe'   edit-command-line
  bindkey '^x^e'  edit-command-line

  # --------------------------------------------------------------------
  # Shell Options
  # 
  # These control ZSH behavior. Each section is grouped by function.
  # Options are carefully chosen for optimal UX and safety
  # --------------------------------------------------------------------
  
  # Navigation options
  setopt AUTO_CD              # Type directory name to cd into it
  setopt AUTO_PUSHD           # Make cd push old directory onto stack
  setopt PUSHD_IGNORE_DUPS    # Don't push duplicates onto stack
  setopt PUSHD_SILENT         # Don't print directory stack after pushd/popd
  setopt PUSHD_TO_HOME        # pushd with no args goes to home

  # Globbing options
  setopt EXTENDED_GLOB        # Use extended globbing syntax (#, ~, ^)
  setopt GLOB_DOTS            # Include dotfiles in glob matches
  setopt NUMERIC_GLOB_SORT    # Sort numerically when possible
  setopt NO_CASE_GLOB         # Case-insensitive globbing
  setopt NO_NOMATCH           # Don't error on no glob match, pass through

  # Completion options
  setopt COMPLETE_IN_WORD     # Complete from both ends of word
  setopt ALWAYS_TO_END        # Move cursor to end after completion
  setopt AUTO_MENU            # Show menu on second tab press
  setopt AUTO_LIST            # List choices on ambiguous completion
  setopt AUTO_PARAM_SLASH     # Add slash after directory completion
  setopt NO_MENU_COMPLETE     # Don't insert first match immediately
  setopt LIST_PACKED          # Vary column widths for compact display

  # History options
  setopt EXTENDED_HISTORY         # Save timestamps in history
  setopt HIST_EXPIRE_DUPS_FIRST   # Expire duplicates first when trimming
  setopt HIST_FIND_NO_DUPS        # Don't show duplicates in search
  setopt HIST_IGNORE_ALL_DUPS     # Remove older duplicate entries
  setopt HIST_IGNORE_SPACE        # Don't save commands starting with space
  setopt HIST_REDUCE_BLANKS       # Remove superfluous blanks before saving
  setopt HIST_SAVE_NO_DUPS        # Don't write duplicates to history file
  setopt HIST_VERIFY              # Show history expansion before running
  setopt SHARE_HISTORY            # Share history across all sessions
  setopt INC_APPEND_HISTORY       # Append to history immediately, not on exit

  # UX options
  setopt INTERACTIVE_COMMENTS     # Allow comments in interactive shell
  setopt NO_BEEP                  # Don't beep on errors
  setopt PROMPT_SUBST             # Allow prompt string substitutions
  setopt TRANSIENT_RPROMPT        # Remove right prompt on accept
  setopt NO_FLOW_CONTROL          # Disable Ctrl-S/Ctrl-Q flow control
  setopt COMBINING_CHARS          # Combine zero-length punctuation chars

  # Safety options
  setopt NO_CLOBBER               # Don't overwrite files with > redirect
  setopt NO_RM_STAR_SILENT        # Ask for confirmation before rm *
  setopt CORRECT                  # Correct command spelling

  # --------------------------------------------------------------------
  # History Ignore Pattern
  # 
  # Don't save these common commands to history
  # Reduces clutter and improves search results
  # Pattern uses ZSH extended glob syntax
  # --------------------------------------------------------------------
  HISTORY_IGNORE="(ls|cd|pwd|exit|clear|history|cd ..|cd -|z *|zi *)"

  # --------------------------------------------------------------------
  # Disable Globbing for Specific Commands
  # 
  # Some commands interpret glob characters themselves
  # Using noglob prevents ZSH from expanding them first
  # This prevents issues with patterns in arguments
  # --------------------------------------------------------------------
  alias git='noglob git'
  alias find='noglob find'
  alias rsync='noglob rsync'
  alias scp='noglob scp'
  alias curl='noglob curl'
  alias wget='noglob wget'

  # --------------------------------------------------------------------
  # Eza (modern ls) configuration
  if command -v eza &>/dev/null; then
    export EZA_COLORS="da=1;34:gm=1;34"
    export EZA_ICON_SPACING=2
  fi

  # --------------------------------------------------------------------
  # Lazy Loading for Heavy Tools
  # 
  # NVM, pyenv, RVM, and Conda are slow to initialize (100-500ms each)
  # We load them only when their commands are actually used
  # This dramatically improves shell startup time
  # 
  # How it works:
  # 1. Define a lazy loader function
  # 2. Alias the real command to the lazy loader
  # 3. On first use, unalias, load real tool, run command
  # 4. Subsequent uses are normal (no lazy loading overhead)
  # --------------------------------------------------------------------
  # NVM (Node Version Manager)
# Only loads when you run: nvm, node, npm, or npx
if [[ -d "$HOME/.nvm" ]]; then
  _lazy_nvm() {
    unset -f _lazy_nvm
    unalias nvm node npm npx 2>/dev/null || true
    export NVM_DIR="$HOME/.nvm"
    [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
    nvm "$@"
  }
  alias nvm='_lazy_nvm'
  alias node='_lazy_nvm'
  alias npm='_lazy_nvm'
  alias npx='_lazy_nvm'
fi

# RVM (Ruby Version Manager)
# Only loads when you run: rvm, ruby, gem, or bundle
if [[ -d "$HOME/.rvm" ]]; then
  _lazy_rvm() {
    unset -f _lazy_rvm
    unalias rvm ruby gem bundle 2>/dev/null || true
    [[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm"
    rvm "$@"
  }
  alias rvm='_lazy_rvm'
  alias ruby='_lazy_rvm'
  alias gem='_lazy_rvm'
  alias bundle='_lazy_rvm'
fi

# pyenv (Python Version Manager)
# Only loads when you run: pyenv, python, or pip
if [[ -d "$HOME/.pyenv" ]]; then
  _lazy_pyenv() {
    unset -f _lazy_pyenv
    unalias pyenv python pip 2>/dev/null || true
    export PYENV_ROOT="$HOME/.pyenv"
    path=("$PYENV_ROOT/bin" $path)
    eval "$(pyenv init --path)"
    eval "$(pyenv init -)"
    pyenv "$@"
  }
  alias pyenv='_lazy_pyenv'
  alias python='_lazy_pyenv'
  alias pip='_lazy_pyenv'
fi

# Conda (Python Environment Manager)
# Only loads when you run: conda
if [[ -d "$HOME/.conda/miniconda3" || -d "$HOME/.conda/anaconda3" ]]; then
  _lazy_conda() {
    unset -f _lazy_conda
    unalias conda 2>/dev/null || true
    local conda_base="$HOME/.conda/miniconda3"
    [[ -d "$HOME/.conda/anaconda3" ]] && conda_base="$HOME/.conda/anaconda3"
    eval "$("$conda_base/bin/conda" shell.zsh hook 2>/dev/null)"
    conda "$@"
  }
  alias conda='_lazy_conda'
fi


  # ====================================================================
  # ZINIT PLUGINS - CRITICAL: Correct Load Order
  # ====================================================================
  # 
  # Plugin load order is CRITICAL for correct operation:
  # 
  # 1. zsh-completions  → Adds completion definitions to fpath
  # 2. fzf-tab          → Hooks into completion system (before compinit)
  # 3. compinit         → Initializes completion system
  # 4. Other plugins    → Load after completion system is ready
  # 5. syntax highlight → MUST BE LAST (wraps all ZLE widgets)
  # 
  # Loading in wrong order causes:
  # • Missing completions (if completions loaded after compinit)
  # • Widget conflicts (if fzf-tab loaded after compinit)
  # • Keybinding failures (if syntax highlighting not last)
  # • Performance degradation (if heavy plugins load too early)
  # 
  # ====================================================================

  # --------------------------------------------------------------------
  # 1. COMPLETIONS - MUST BE FIRST
  # 
  # Loads additional completion definitions before compinit runs
  # This plugin adds thousands of completions for common tools
  # 
  # blockf: Block default fpath modification
  # atpull: Rebuild completions when plugin updates
  # --------------------------------------------------------------------
  zinit ice blockf atpull'zinit creinstall -q .'
  zinit light zsh-users/zsh-completions

  # --------------------------------------------------------------------
  # 2. FZF-TAB - MUST BE BEFORE COMPINIT
  # 
  # Replaces ZSH's default completion menu with FZF
  # CRITICAL: Must load before compinit to hook into the system
  # If loaded after, tab completion won't be fuzzy
  # 
  # depth=1: Shallow clone for faster download
  # --------------------------------------------------------------------
  zinit ice depth=1
  zinit light Aloxaf/fzf-tab

  # Configure fzf-tab behavior
  # These styles control how the fuzzy completion menu looks and behaves
  zstyle ':fzf-tab:*' fzf-command fzf
  zstyle ':fzf-tab:*' fzf-min-height 100
  zstyle ':fzf-tab:*' switch-group ',' '.'
  zstyle ':fzf-tab:*' continuous-trigger '/'
  zstyle ':fzf-tab:complete:*:*' fzf-preview ""
  zstyle ':fzf-tab:complete:*:*' fzf-flags --height=80% --border=rounded --bind='ctrl-/:toggle-preview'

  # Context-specific preview commands
  # Shows helpful previews for different completion types
  zstyle ':fzf-tab:complete:kill:argument-rest' fzf-preview 'ps --pid=$word -o cmd --no-headers -w'
  zstyle ':fzf-tab:complete:systemctl-*:*' fzf-preview 'SYSTEMD_COLORS=1 systemctl status $word'
  zstyle ':fzf-tab:complete:git-(add|diff|restore):*' fzf-preview 'git diff $word | delta'
  zstyle ':fzf-tab:complete:git-log:*' fzf-preview 'git log --color=always $word'
  zstyle ':fzf-tab:complete:git-show:*' fzf-preview 'git show --color=always $word | delta'
  zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -T -L2 --icons --color=always $realpath 2>/dev/null'

  # --------------------------------------------------------------------
  # 3. COMPINIT - MUST BE AFTER COMPLETIONS AND FZF-TAB
  # 
  # Initializes ZSH's completion system
  # This is the core completion engine that makes tab completion work
  # 
  # We use aggressive caching to make this fast:
  # • Cache is valid for 24 hours
  # • Bytecode compilation for faster loading
  # • File locking to prevent race conditions
  # --------------------------------------------------------------------
  
  # Add our custom completions and functions to fpath
  # Must be done before compinit runs
  fpath=("/home/kenan/.config/zsh/completions" "/home/kenan/.config/zsh/functions" $fpath)

  # Load completion system module
  autoload -Uz compinit
  zmodload zsh/system 2>/dev/null || true

  # Set completion dump file location
  # Uses hostname and ZSH version to prevent conflicts
  : ${ZSH_COMPDUMP:="/home/kenan/.cache/zsh/zcompdump-$HOST-$ZSH_VERSION"}
  zstyle ':completion:*' dump-file "$ZSH_COMPDUMP"

  # ----------------------------------------------------------------------
  # _safe_compinit: Smart Completion Initialization
  # 
  # This function intelligently decides whether to rebuild completions:
  # 
  # Decision logic:
  # • If dump doesn't exist → Full rebuild
  # • If dump is >24h old → Full rebuild
  # • If dump is fresh → Use cached version (-C flag = trust cache)
  # 
  # Performance optimization:
  # • Full rebuild: ~200ms (cold start)
  # • Cached version: ~10ms (warm start)
  # • Bytecode compilation: Runs in background, doesn't block
  # 
  # Race condition prevention:
  # • Uses file locking to prevent multiple shells from rebuilding
  # • If lock acquisition fails, falls back to cached version
  # • This prevents corruption and wasted CPU cycles
  # 
  # Bytecode compilation:
  # • Compiles .zcompdump to .zcompdump.zwc for faster loading
  # • Only recompiles if source is newer than bytecode
  # • Runs in background (&!) to not block shell startup
  # ----------------------------------------------------------------------
  _safe_compinit() {
    local _lock_file="/home/kenan/.cache/zsh/.compinit-${HOST}-${ZSH_VERSION}.lock"
    local _dump_dir="$(dirname "$ZSH_COMPDUMP")"

    # Ensure dump directory exists
    [[ -d "$_dump_dir" ]] || mkdir -p "$_dump_dir"

    local -i need_rebuild=0
    
    # Check if dump exists and is fresh (less than 24 hours old)
    # Glob qualifier: (#qN.mh+24) = hidden, no error if not exist, modified >24h ago
    if [[ ! -s "$ZSH_COMPDUMP" || -n $ZSH_COMPDUMP(#qN.mh+24) ]]; then
      need_rebuild=1
    fi

    # If dump is fresh, use cached version (fast path)
    if (( need_rebuild == 0 )); then
      # -C: Skip security check (trust cache)
      # -i: Ignore insecure directories
      # -d: Specify dump file location
      compinit -C -i -d "$ZSH_COMPDUMP"
      
      # Compile dump to bytecode in background if needed
      if [[ ! -f "$ZSH_COMPDUMP.zwc" || "$ZSH_COMPDUMP" -nt "$ZSH_COMPDUMP.zwc" ]]; then
        # -U: Compile for use only (no execution)
        # &!: Run in background, disown from job table
        { zcompile -U "$ZSH_COMPDUMP" 2>/dev/null || true; } &!
      fi
      return 0
    fi

    # If we need to rebuild, try to acquire lock
    # If lock fails, another shell is already rebuilding
    if command -v zsystem &>/dev/null; then
      # -t 0.1: Try for 0.1 seconds, then give up
      if ! zsystem flock -t 0.1 "$_lock_file" 2>/dev/null; then
        # Lock acquisition failed, use cached version
        compinit -C -i -d "$ZSH_COMPDUMP"
        return 0
      fi
    fi

    # We have the lock, do full rebuild
    # -u: Skip security check during rebuild
    # -i: Ignore insecure directories
    # -d: Specify dump file location
    compinit -u -i -d "$ZSH_COMPDUMP"
    
    # Compile to bytecode in background
    { zcompile -U "$ZSH_COMPDUMP" 2>/dev/null || true; } &!
    
    # Release lock
    command -v zsystem &>/dev/null && zsystem flock -u "$_lock_file" 2>/dev/null || true
  }

  # Initialize completion system using smart function
  _safe_compinit
  
  # Also load bash completion compatibility
  # Allows bash completion scripts to work in ZSH
  autoload -Uz bashcompinit && bashcompinit

  # --------------------------------------------------------------------
  # Completion System Styles
  # 
  # These zstyle commands control how completions look and behave
  # They affect the completion menu, matching, caching, and display
  # --------------------------------------------------------------------
  autoload -Uz colors && colors
  _comp_options+=(globdots)  # Include hidden files in completion

  # Completion strategy: try multiple methods in order
  # 1. _extensions: Try matching file extensions
  # 2. _complete: Standard completion
  # 3. _approximate: Try approximate matching (typo tolerance)
  # 4. _ignored: Try previously ignored matches
  zstyle ':completion:*' completer _extensions _complete _approximate _ignored
  
  # Enable caching for better performance
  # Cache stores results of expensive completions
  zstyle ':completion:*' use-cache on
  zstyle ':completion:*' cache-path "/home/kenan/.cache/zsh/.zcompcache"
  
  # Enable full completion features
  zstyle ':completion:*' complete true
  zstyle ':completion:*' complete-options true

  # Smart case-insensitive matching
  # Three matchers for maximum flexibility:
  # 1. Case-insensitive: 'a' matches 'A'
  # 2. Partial matching: 'f-b' matches 'foo-bar'
  # 3. Left-anchored: 'fb' matches 'foobar'
  zstyle ':completion:*' matcher-list \
    'm:{a-zA-Z}={A-Za-z}' \
    'r:|[._-]=* r:|=*' \
    'l:|=* r:|=*'

  # File sorting and listing options
  zstyle ':completion:*' file-sort modification  # Sort by modification time
  zstyle ':completion:*' sort false              # Don't sort results
  zstyle ':completion:*' list-suffixes true      # Show suffixes in list
  zstyle ':completion:*' expand prefix suffix    # Expand on both sides
  zstyle ':completion:*' menu select=2           # Menu select on 2+ matches
  zstyle ':completion:*' group-name ""           # Group completions by type
  zstyle ':completion:*' verbose yes             # Show descriptions
  zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}  # Use LS_COLORS
  zstyle ':completion:*' special-dirs true       # Include . and ..
  zstyle ':completion:*' squeeze-slashes true    # Remove duplicate slashes

  # Colored completion messages
  zstyle ':completion:*:descriptions' format '%F{yellow}━━ %d ━━%f'
  zstyle ':completion:*:messages'     format '%F{purple}━━ %d ━━%f'
  zstyle ':completion:*:warnings'     format '%F{red}━━ no matches found ━━%f'
  zstyle ':completion:*:corrections'  format '%F{green}━━ %d (errors: %e) ━━%f'

  # Process completion for kill command
  # Shows processes with PID, user, and command
  zstyle ':completion:*:*:*:*:processes' command "ps -u $USER -o pid,user,comm -w"
  zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#) ([0-9a-z-]#)*=01;34=0=01'
  zstyle ':completion:*:*:kill:*' menu yes select
  zstyle ':completion:*:*:kill:*' force-list always
  zstyle ':completion:*:*:kill:*' insert-ids single

  # Man page completion
  # Separates man sections for better navigation
  zstyle ':completion:*:manuals'    separate-sections true
  zstyle ':completion:*:manuals.*'  insert-sections true

  # SSH/SCP/rsync completion
  # Organizes hosts by type (hostname, domain, IP)
  zstyle ':completion:*:(ssh|scp|rsync):*' tag-order \
    'hosts:-host:host hosts:-domain:domain hosts:-ipaddr:ip\ address'
  zstyle ':completion:*:(ssh|scp|rsync):*:hosts-host' \
    ignored-patterns '*(.|:)*' loopback localhost broadcasthost
  zstyle ':completion:*:(ssh|scp|rsync):*:hosts-domain' \
    ignored-patterns '<->.<->.<->.<->' '*@*'
  zstyle ':completion:*:(ssh|scp|rsync):*:hosts-ipaddr' \
    ignored-patterns '^(<->.<->.<->.<->)' '127.0.0.<->' '::1' 'fe80::*'

  # Always rehash for new commands
  # Checks for new executables in PATH
  zstyle ':completion:*' rehash true
  zstyle ':completion:*' accept-exact-dirs true

  # ====================================================================
  # 4. OTHER PLUGINS - AFTER COMPINIT
  # ====================================================================
  # 
  # These plugins can safely load after the completion system is ready
  # They don't interact with compinit so order among themselves doesn't matter
  # 
  # All plugins load synchronously (no wait) for simplicity and reliability
  # This adds ~50ms to startup but prevents timing issues
  # 
  # ====================================================================
  # ------------------------------------------------------------------
# History substring search
# 
# Provides up/down arrow history search with substring matching
# Essential for efficient history navigation
# Keybindings work in both standard and application cursor key modes
# ------------------------------------------------------------------
zinit light zsh-users/zsh-history-substring-search
bindkey '^[[A'  history-substring-search-up      # Up arrow
bindkey '^[[B'  history-substring-search-down    # Down arrow
bindkey '^[OA'  history-substring-search-up      # Up arrow (app mode)
bindkey '^[OB'  history-substring-search-down    # Down arrow (app mode)

# ------------------------------------------------------------------
# Auto-suggestions
# 
# Shows suggestions based on history as you type
# Lightweight and provides excellent UX
# Accept suggestion with End key or Ctrl-E
# ------------------------------------------------------------------
zinit light zsh-users/zsh-autosuggestions

# ------------------------------------------------------------------
# Autopair
# 
# Auto-closes brackets, quotes, and other pairs
# Tiny plugin with no performance impact
# Smart about when to insert pairs vs not
# ------------------------------------------------------------------
zinit light hlissner/zsh-autopair

# ------------------------------------------------------------------
# OMZ Plugin Snippets
# 
# Lightweight utilities from Oh-My-Zsh
# Each adds useful functionality without significant overhead
# 
# sudo: Press ESC twice to prepend sudo to command
# extract: Smart archive extraction (extract <file>)
# copypath: Copy current path to clipboard (copypath)
# copyfile: Copy file contents to clipboard (copyfile <file>)
# git: Extensive git aliases (gst, gco, gp, etc.)
# ------------------------------------------------------------------
zinit snippet OMZ::plugins/sudo/sudo.plugin.zsh
zinit snippet OMZ::plugins/extract/extract.plugin.zsh
zinit snippet OMZ::plugins/copypath/copypath.plugin.zsh
zinit snippet OMZ::plugins/copyfile/copyfile.plugin.zsh
zinit snippet OMZ::plugins/git/git.plugin.zsh

# ------------------------------------------------------------------
# Syntax Highlighting - MUST BE LAST
# 
# CRITICAL: This MUST be the last plugin loaded
# 
# Why last?
# • Wraps all ZLE widgets to provide syntax highlighting
# • Must wrap widgets after all other plugins have set them up
# • If loaded earlier, other plugins' widgets won't be highlighted
# 
# Performance Note:
# • Causes ~300-500ms freeze when loading
# • This is inherent to how it wraps ZLE widgets
# • Unavoidable - it's a design limitation
# 
# Trade-off:
# • Visual feedback (colored commands)
# • vs Instant responsiveness (no freeze)
# 
# If the freeze is unacceptable, comment out this line
# The shell works perfectly without syntax highlighting
# ------------------------------------------------------------------
zinit light zsh-users/zsh-syntax-highlighting


  # Fallback if zinitTurbo is disabled
  # Loads same plugins in non-turbo mode
  
else
  # Zinit not available - shell runs without plugins
  echo "WARNING: Zinit not available; shell running without plugins." >&2
fi

# ----------------------------------------------------------------------
# Tool Integrations
# 
# These tools enhance shell functionality
# They don't depend on Zinit and run regardless of plugin availability
# Each checks if the tool is installed before integrating
# ----------------------------------------------------------------------

# Zoxide: Smarter cd command that learns your habits
# Usage: z <partial-path> jumps to most frecent match
if command -v zoxide &>/dev/null; then
  eval "$(zoxide init zsh)"
fi

# Direnv: Automatic environment switching per directory
# Loads .envrc files when entering directories
# Silenced to avoid clutter during directory changes
if command -v direnv &>/dev/null; then
  eval "$(direnv hook zsh)"
  export DIRENV_LOG_FORMAT=""  # Silence direnv messages
fi

# Atuin: Better shell history with sync and search
# Provides enhanced Ctrl-R history search
# ATUIN_NOBIND prevents auto-binding to allow manual configuration
if command -v atuin &>/dev/null; then
  export ATUIN_NOBIND="true"
  eval "$(atuin init zsh)"
  bindkey '^r' _atuin_search_widget  # Ctrl-R for atuin search
fi

# ----------------------------------------------------------------------
# Custom Functions
# 
# Auto-load any functions in the functions directory
# Functions are lazy-loaded: loaded into memory but not executed
# until called, saving startup time
# ----------------------------------------------------------------------
if [[ -d "/home/kenan/.config/zsh/functions" ]]; then
  for func in "/home/kenan/.config/zsh/functions"/*(.N); do
    autoload -Uz "${func:t}"
  done
fi

# ----------------------------------------------------------------------
# Zinit Directory Escape
# 
# If we somehow ended up in a zinit plugin directory, go home
# This can happen if a plugin changes PWD during loading
# Prevents confusion when shell starts in unexpected location
# ----------------------------------------------------------------------
[[ $PWD == *"/zinit/plugins/"* ]] && cd ~

# ----------------------------------------------------------------------
# Debug Output
# 
# If debug mode is enabled, show profiling results
# Helps identify slow parts of shell startup
# ----------------------------------------------------------------------


# ----------------------------------------------------------------------
# Starship Prompt
# 
# Load Starship last so it doesn't interfere with plugin loading
# Starship provides a fast, customizable prompt with git integration
# ----------------------------------------------------------------------
if command -v starship &>/dev/null; then
  eval "$(starship init zsh)"
fi

# =========================================================================
# FZF configuration (Zsh side)
# DO NOT touch FZF_DEFAULT_OPTS here.
# Catppuccin theme is already injected via programs.fzf.defaultOptions.
# =========================================================================

# Completion trigger and options
export FZF_COMPLETION_TRIGGER='**'
export FZF_COMPLETION_OPTS='--border=rounded --info=inline'

# Default file search command
if command -v rg &>/dev/null; then
  export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!{.git,.cache,node_modules}/*"'
elif command -v fd &>/dev/null; then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --strip-cwd-prefix -E .git -E .cache -E node_modules'
fi

# CTRL-T and ALT-C commands (fd-based)
if command -v fd &>/dev/null; then
  export FZF_CTRL_T_COMMAND='fd --type f --type d --hidden --follow --strip-cwd-prefix -E .git -E .cache -E node_modules'
  export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --strip-cwd-prefix -E .git -E .cache -E node_modules'
fi

# CTRL-T: file/dir picker + preview + nvim integration
export FZF_CTRL_T_OPTS="\
  --preview '[[ -d {} ]] && eza -T -L2 --icons --color=always {} || bat -n --color=always -r :500 {}' \
  --preview-window 'right:60%:wrap' \
  --bind 'ctrl-/:change-preview-window(down|hidden|)' \
  --bind 'ctrl-e:execute(nvim {} < /dev/tty > /dev/tty 2>&1)'"

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
  --bind 'ctrl-y:execute-silent(echo -n {2..} | wl-copy)+abort' \
  --exact"

function yy() {
  local tmp="$(mktemp -t "yazi-cwd.XXXXX")"
  yazi "$@" --cwd-file="$tmp"
  if cwd="$(<"$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
    builtin cd -- "$cwd"
  fi
  rm -f -- "$tmp"
}

# WezTerm shell integration (optional)
if [[ -f /etc/profile.d/wezterm.sh ]]; then
  source /etc/profile.d/wezterm.sh
elif [[ -f /usr/share/wezterm/wezterm.sh ]]; then
  source /usr/share/wezterm/wezterm.sh
fi

if [[ $TERM != "dumb" ]] && command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi

# command-not-found integration (Arch/CachyOS: pkgfile)
if [[ -f /usr/share/doc/pkgfile/command-not-found.zsh ]]; then
  source /usr/share/doc/pkgfile/command-not-found.zsh
elif [[ -f /usr/share/doc/pkgfile/command-not-found.sh ]]; then
  source /usr/share/doc/pkgfile/command-not-found.sh
fi

if test -n "$KITTY_INSTALLATION_DIR"; then
  export KITTY_SHELL_INTEGRATION="no-rc"
  autoload -Uz -- "$KITTY_INSTALLATION_DIR"/shell-integration/zsh/kitty-integration
  kitty-integration
  unfunction kitty-integration
fi

export GPG_TTY=$TTY
export PASSWORD_STORE_DIR="$HOME/.pass"
gpg-connect-agent --quiet updatestartuptty /bye > /dev/null 2>/dev/null || true

alias -- ..='cd ..'
alias -- ...='cd ../..'
alias -- ....='cd ../../..'
alias -- .....='cd ../../../..'
if command -v ai-codex >/dev/null 2>&1; then
  alias -- codex=ai-codex
fi
if command -v ai-gemini >/dev/null 2>&1; then
  alias -- gemini=ai-gemini
fi
alias -- brave=brave-launcher
alias -- brave-backup='brave-setup backup'
alias -- brave-clean='brave-launcher --disable-extensions --incognito'
alias -- brave-debug='brave-launcher --enable-logging --v=1'
alias -- brave-dev='brave-launcher --disable-web-security --user-data-dir=/tmp/brave-dev'
alias -- brave-ext-clean='rm -rf ~/.config/BraveSoftware/Brave-Browser/Default/Extensions/'
alias -- brave-ext-list='ls -la ~/.config/BraveSoftware/Brave-Browser/Default/Extensions/ 2>/dev/null || echo '\''No Extensions directory found'\'''
alias -- brave-extensions=brave-install-extensions
alias -- brave-profile='brave-launcher --profile-directory='\''Default'\'''
alias -- brave-reset-cache='find ~/.cache/BraveSoftware -type f \( -name '\''*.tmp'\'' -o -name '\''*.lock'\'' \) -delete 2>/dev/null || true'
alias -- brave-safe='brave-launcher --disable-extensions --disable-gpu'
alias -- brave-setup=brave-setup
alias -- brave-status='brave-setup status'
alias -- brave-theme=brave-apply-theme
alias -- brave-theme-css='cat ~/.config/BraveSoftware/Brave-Browser/Default/Stylus/catppuccin-mocha.user.css'
alias -- brave-theme-edit='EDITOR:-nvim ~/.config/BraveSoftware/Brave-Browser/Default/Stylus/catppuccin-mocha.user.css'
alias -- c=clear
alias -- cal='cal -3'
alias -- cat='bat --paging=never'
alias -- cava-config='cat ~/.config/cava/config | grep -A10 '\''\[color\]'\'''
alias -- cava-theme='echo '\''Current Cava Catppuccin flavor: mocha'\'''
alias -- cd=z
alias -- chrome=chrome-launcher
alias -- chrome-clean='chrome-launcher --disable-extensions --incognito'
alias -- chrome-debug='chrome-launcher --enable-logging --v=1'
alias -- chrome-profile='chrome-launcher --profile-directory='\''Default'\'''
alias -- chrome-reset-cache='find ~/.cache/google-chrome -type f \( -name '\''*.tmp'\'' -o -name '\''*.lock'\'' \) -delete 2>/dev/null || true'
alias -- chrome-safe='chrome-launcher --disable-extensions --disable-gpu'
alias -- compress=apack
alias -- copy='xclip -selection clipboard'
alias -- cp='cp -i'
alias -- cpu=lscpu
alias -- curl='curl -L'
alias -- df='df -h'
alias -- diff='delta --side-by-side'
alias -- disk='lsblk -f'
alias -- dsize='du -hs'
alias -- extract=aunpack
alias -- fastping='ping -c 100 -s.2'
alias -- find=fd
alias -- firefox-new='firefox -new-instance'
alias -- firefox-profile='firefox -P'
alias -- firefox-safe='firefox -safe-mode'
alias -- free='free -h'
alias -- g=git
alias -- ga='git add'
alias -- gaa='git add --all'
alias -- gam='git am'
alias -- gama='git am --abort'
alias -- gamc='git am --continue'
alias -- gams='git am --skip'
alias -- gamscp='git am --show-current-patch'
alias -- gap='git apply'
alias -- gapa='git add --patch'
alias -- gapt='git apply --3way'
alias -- gau='git add --update'
alias -- gav='git add --verbose'
alias -- gb='git branch'
alias -- gbD='git branch --delete --force'
alias -- gba='git branch --all'
alias -- gbd='git branch --delete'
alias -- gbg='LANG=C git branch -vv | grep ": gone\]"'
alias -- gbgD='LANG=C git branch --no-color -vv | grep ": gone\]" | cut -c 3- | awk '\''{print $1}'\'' | xargs git branch -D'
alias -- gbgd='LANG=C git branch --no-color -vv | grep ": gone\]" | cut -c 3- | awk '\''{print $1}'\'' | xargs git branch -d'
alias -- gbl='git blame -w'
alias -- gbm='git branch --move'
alias -- gbnm='git branch --no-merged'
alias -- gbr='git branch --remote'
alias -- gbs='git bisect'
alias -- gbsb='git bisect bad'
alias -- gbsg='git bisect good'
alias -- gbsn='git bisect new'
alias -- gbso='git bisect old'
alias -- gbsr='git bisect reset'
alias -- gbss='git bisect start'
alias -- gc='git commit --verbose'
alias -- 'gc!'='git commit --verbose --amend'
alias -- gcB='git checkout -B'
alias -- gca='git commit --verbose --all'
alias -- 'gca!'='git commit --verbose --all --amend'
alias -- gcam='git commit --all --message'
alias -- 'gcan!'='git commit --verbose --all --no-edit --amend'
alias -- 'gcann!'='git commit --verbose --all --date=now --no-edit --amend'
alias -- 'gcans!'='git commit --verbose --all --signoff --no-edit --amend'
alias -- gcas='git commit --all --signoff'
alias -- gcasm='git commit --all --signoff --message'
alias -- gcb='git checkout -b'
alias -- gcf='git config --list'
alias -- gcfu='git commit --fixup'
alias -- gcl='git clone --recurse-submodules'
alias -- gclean='git clean --interactive -d'
alias -- gclf='git clone --recursive --shallow-submodules --filter=blob:none --also-filter-submodules'
alias -- gcmsg='git commit --message'
alias -- gcn='git commit --verbose --no-edit'
alias -- 'gcn!'='git commit --verbose --no-edit --amend'
alias -- gco='git checkout'
alias -- gcor='git checkout --recurse-submodules'
alias -- gcount='git shortlog --summary --numbered'
alias -- gcp='git cherry-pick'
alias -- gcpa='git cherry-pick --abort'
alias -- gcpc='git cherry-pick --continue'
alias -- gcs='git commit --gpg-sign'
alias -- gcsm='git commit --signoff --message'
alias -- gcss='git commit --gpg-sign --signoff'
alias -- gcssm='git commit --gpg-sign --signoff --message'
alias -- gd='git diff'
alias -- gdca='git diff --cached'
alias -- gdct='git describe --tags $(git rev-list --tags --max-count=1)'
alias -- gdcw='git diff --cached --word-diff'
alias -- gdg='git log --graph --decorate --oneline $(git rev-list -g --all)'
alias -- gds='git diff --staged'
alias -- gdt='git diff-tree --no-commit-id --name-only -r'
alias -- gdup='git diff @{upstream}'
alias -- gdw='git diff --word-diff'
alias -- gf='git fetch'
alias -- gfa='git fetch --all --tags --prune'
alias -- gfg='git ls-files | grep'
alias -- gfo='git fetch origin'
alias -- gg='git gui citool'
alias -- gga='git gui citool --amend'
alias -- ggpull='git pull origin "$(git branch --show-current)"'
alias -- ggpush='git push origin "$(git branch --show-current)"'
alias -- ggsup='git branch --set-upstream-to=origin/$(git branch --show-current)'
alias -- ghc='gh repo create'
alias -- ghh='git help'
alias -- ghv='gh repo view --web'
alias -- gignore='git update-index --assume-unchanged'
alias -- gignored='git ls-files -v | grep "^[[:lower:]]"'
alias -- ginfo='onefetch --number-of-file-churns 0 --no-color-palette'
alias -- ginit='git init && git add . && git commit -m '\''Initial commit'\'''
alias -- gk='gitk --all --branches'
alias -- gke='gitk --all $(git log --walk-reflogs --pretty=%h)'
alias -- gl='git pull'
alias -- glg='git log --stat'
alias -- glgg='git log --graph'
alias -- glgga='git log --graph --decorate --all'
alias -- glgm='git log --graph --max-count=10'
alias -- glgp='git log --stat --patch'
alias -- glo='git log --oneline --decorate'
alias -- glod='git log --graph --pretty="%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ad) %C(bold blue)<%an>%Creset"'
alias -- glods='git log --graph --pretty="%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ad) %C(bold blue)<%an>%Creset" --date=short'
alias -- glog='git log --oneline --decorate --graph'
alias -- gloga='git log --oneline --decorate --graph --all'
alias -- glol='git log --graph --pretty="%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset"'
alias -- glola='git log --graph --pretty="%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset" --all'
alias -- glols='git log --graph --pretty="%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset" --stat'
alias -- gm='git merge'
alias -- gma='git merge --abort'
alias -- gmc='git merge --continue'
alias -- gmff='git merge --ff-only'
alias -- gms='git merge --squash'
alias -- gmtl='git mergetool --no-prompt'
alias -- gmtlvim='git mergetool --no-prompt --tool=vimdiff'
alias -- gp='git push'
alias -- gpd='git push --dry-run'
alias -- gpf='git push --force-with-lease'
alias -- 'gpf!'='git push --force'
alias -- gpoat='git push origin --all && git push origin --tags'
alias -- gpod='git push origin --delete'
alias -- gpr='git pull --rebase'
alias -- gpra='git pull --rebase --autostash'
alias -- gprav='git pull --rebase --autostash -v'
alias -- gpristine='git reset --hard && git clean --force -dfx'
alias -- gprv='git pull --rebase -v'
alias -- gpsup='git push --set-upstream origin $(git branch --show-current)'
alias -- gpsupf='git push --set-upstream origin $(git branch --show-current) --force-with-lease'
alias -- gpu='git push upstream'
alias -- gpv='git push --verbose'
alias -- gr='git remote'
alias -- gra='git remote add'
alias -- grb='git rebase'
alias -- grba='git rebase --abort'
alias -- grbc='git rebase --continue'
alias -- grbi='git rebase --interactive'
alias -- grbo='git rebase --onto'
alias -- grbs='git rebase --skip'
alias -- grev='git revert'
alias -- greva='git revert --abort'
alias -- grevc='git revert --continue'
alias -- grf='git reflog'
alias -- grh='git reset'
alias -- grhh='git reset --hard'
alias -- grhk='git reset --keep'
alias -- grhs='git reset --soft'
alias -- grm='git rm'
alias -- grmc='git rm --cached'
alias -- grmv='git remote rename'
alias -- groh='git reset origin/$(git branch --show-current) --hard'
alias -- grrm='git remote remove'
alias -- grs='git restore'
alias -- grset='git remote set-url'
alias -- grss='git restore --source'
alias -- grst='git restore --staged'
alias -- grt='cd "$(git rev-parse --show-toplevel || echo .)"'
alias -- gru='git reset --'
alias -- grup='git remote update'
alias -- grv='git remote --verbose'
alias -- gsb='git status --short --branch'
alias -- gsd='git svn dcommit'
alias -- gsh='git show'
alias -- gsi='git submodule init'
alias -- gsize='git count-objects -vH'
alias -- gsps='git show --pretty=short --show-signature'
alias -- gsr='git svn rebase'
alias -- gss='git status --short'
alias -- gst='git status'
alias -- gsta='git stash push'
alias -- gstaa='git stash apply'
alias -- gstall='git stash --all'
alias -- gstc='git stash clear'
alias -- gstd='git stash drop'
alias -- gstl='git stash list'
alias -- gstp='git stash pop'
alias -- gsts='git stash show --patch'
alias -- gstu='git stash push --include-untracked'
alias -- gsu='git submodule update'
alias -- gsw='git switch'
alias -- gswc='git switch --create'
alias -- gta='git tag --annotate'
alias -- gts='git tag --sign'
alias -- gtv='git tag | sort -V'
alias -- gunignore='git update-index --no-assume-unchanged'
alias -- gunwip='git rev-list --max-count=1 --format="%s" HEAD | grep -q "\--wip--" && git reset HEAD~1'
alias -- gwch='git whatchanged -p --abbrev-commit --pretty=medium'
alias -- gwhen='git log --follow --patch --'
alias -- gwho='git shortlog -s --'
alias -- gwip='git add -A; git rm $(git ls-files --deleted) 2> /dev/null; git commit --no-verify --no-gpg-sign --message "--wip-- [skip ci]"'
alias -- gwipe='git reset --hard && git clean --force -df'
alias -- gwt='git worktree'
  alias -- gwta='git worktree add'
  alias -- gwtls='git worktree list'
  alias -- gwtmv='git worktree move'
  alias -- gwtrm='git worktree remove'
  alias -- h='history | tail -20'
  alias -- hw='hwinfo --short'
  alias -- ip='ip -color=auto'
  alias -- ipy=ipython
  alias -- j='jobs -l'
  alias -- l='eza --icons -a --group-directories-first -1'
alias -- la='eza --icons -la --group-directories-first'
alias -- ldot='eza --icons -ld .*'
alias -- less='bat --paging=always'
alias -- lg=lazygit
alias -- ll='eza --icons -la --group-directories-first --no-user'
alias -- llt='eza --icons --tree --long --level=3 --group-directories-first'
alias -- load=uptime
alias -- localip='ip route get 8.8.8.8 | awk '\''{print $7; exit}'\'''
alias -- ls='eza --icons --group-directories-first'
alias -- lsize='eza --icons -la --group-directories-first --total-size'
alias -- lt='eza --icons --tree --level=2 --group-directories-first'
alias -- lzg=lazygit
alias -- mem='free -h && echo && cat /proc/meminfo | grep MemTotal'
alias -- microcode='grep . /sys/devices/system/cpu/vulnerabilities/*'
  alias -- mkdir='mkdir -pv'
  alias -- moon='curl wttr.in/moon'
  alias -- mv='mv -i'
  alias -- myip='curl -s ifconfig.me'
  alias -- news='curl getnews.tech'
  alias -- now='date +'\''%T'\'''
  alias -- nowdate='date +'\''%d-%m-%Y'\'''
  alias -- nowtime='date +'\''%d-%m-%Y %T'\'''
  alias -- open=xdg-open
  alias -- osc='cd ~/.cachy'
  alias -- p=pass
  alias -- paste='xclip -selection clipboard -o'
  alias -- path='echo -e ${PATH//:/\\n}'
  alias -- paudit='pass audit'
  alias -- pc='pass -c'
alias -- pci=lspci
alias -- pdf=tdf
alias -- pe='pass edit'
alias -- pf='pass find'
alias -- pg='pass generate'
alias -- pi='pass insert'
alias -- ping='ping -c 5'
alias -- pipf='pip freeze'
alias -- pipi='pip install'
alias -- pipl='pip list'
alias -- pipr='pip install -r requirements.txt'
alias -- pipu='pip install --upgrade'
alias -- piv='python3 -m venv .venv'
alias -- ports='ss -tulanp'
alias -- potp='pass otp'
alias -- potpc='pass otp -c'
alias -- ppull='pass git pull'
alias -- ppush='pass git push'
alias -- pr='pass rm'
alias -- ps=procs
alias -- psa='ps auxf'
alias -- pscpu='ps auxf | sort -nr -k 3 | head -20'
alias -- psgrep='ps aux | grep -v grep | grep -i'
alias -- psh='pass show'
alias -- psmem='ps auxf | sort -nr -k 4 | head -20'
alias -- psv='source .venv/bin/activate'
alias -- pv-1080='pipe-viewer -1'
alias -- pv-240='pipe-viewer -2'
alias -- pv-360='pipe-viewer -3'
alias -- pv-360deg='pipe-viewer --360'
alias -- pv-3d='pipe-viewer --dimension=3d'
alias -- pv-480='pipe-viewer -4'
alias -- pv-4k='pipe-viewer --resolution=2160p'
alias -- pv-720='pipe-viewer -7'
alias -- pv-all='pipe-viewer --all'
alias -- pv-audio='pipe-viewer -n -a --audio-quality=best'
alias -- pv-auto='pipe-viewer --autoplay'
alias -- pv-av1='pipe-viewer --prefer-av1'
alias -- pv-backwards='pipe-viewer --backwards'
alias -- pv-best='pipe-viewer --best'
alias -- pv-cc='pipe-viewer --captions'
alias -- pv-ch='pipe-viewer -sc'
alias -- pv-comments='pipe-viewer --comments'
alias -- pv-dislike='pipe-viewer --dislike'
alias -- pv-dislikes='pipe-viewer -D'
alias -- pv-dl='pipe-viewer -d'
alias -- pv-dl-audio='pipe-viewer -d -n -a --convert-to=mp3'
alias -- pv-dl-mp4='pipe-viewer -d --prefer-mp4 --mkv-merge'
alias -- pv-dl-name='pipe-viewer -d --filename='\''%T - %t.%e'\'''
alias -- pv-dl-skip='pipe-viewer -d --skip-if-exists'
alias -- pv-dl-subdir='pipe-viewer -d --dl-in-subdir'
alias -- pv-examples='pipe-viewer --examples'
alias -- pv-fav='pipe-viewer --favorite'
alias -- pv-favs='pipe-viewer -F'
alias -- pv-fs='pipe-viewer --fullscreen'
alias -- pv-hdr='pipe-viewer --hdr'
alias -- pv-help='pipe-viewer --help'
alias -- pv-hfr='pipe-viewer --hfr'
alias -- pv-info='pipe-viewer -i'
alias -- pv-interactive='pipe-viewer --interactive'
alias -- pv-like='pipe-viewer --like'
alias -- pv-likes='pipe-viewer -L'
alias -- pv-live='pipe-viewer --live'
alias -- pv-long='pipe-viewer --duration=long'
alias -- pv-m4a='pipe-viewer --prefer-m4a'
alias -- pv-month='pipe-viewer --time=month'
alias -- pv-mp4='pipe-viewer --prefer-mp4 --ignore-av1'
alias -- pv-mpv='pipe-viewer --player=mpv'
alias -- pv-order-new='pipe-viewer --order=upload_date'
alias -- pv-order-views='pipe-viewer --order=view_count'
alias -- pv-pl='pipe-viewer --pid'
alias -- pv-pl-play='pipe-viewer --pp'
alias -- pv-pl-search='pipe-viewer -sp'
alias -- pv-play='pipe-viewer --best --player=mpv'
alias -- pv-quiet='pipe-viewer -q'
alias -- pv-rquiet='pipe-viewer --really-quiet'
alias -- pv-save='pipe-viewer --save'
alias -- pv-saved='pipe-viewer -lc'
alias -- pv-search='pipe-viewer --search-videos'
alias -- pv-short='pipe-viewer --duration=short'
alias -- pv-shorts='pipe-viewer --shorts'
alias -- pv-shuffle='pipe-viewer --shuffle'
alias -- pv-streams='pipe-viewer -us'
alias -- pv-sub='pipe-viewer --subscribe'
alias -- pv-subs='pipe-viewer -S'
alias -- pv-today='pipe-viewer --time=today'
alias -- pv-trend='pipe-viewer --no-invidious --ytdl --trending=popular --region=TR'
alias -- pv-trend-gaming='pipe-viewer --no-invidious --ytdl --trending=gaming --region=TR'
alias -- pv-trend-movies='pipe-viewer --no-invidious --ytdl --trending=movies --region=TR'
alias -- pv-trend-music='pipe-viewer --no-invidious --ytdl --trending=music --region=TR'
alias -- pv-trend-news='pipe-viewer --no-invidious --ytdl --trending=news --region=TR'
alias -- pv-tricks='pipe-viewer --tricks'
alias -- pv-uploads='pipe-viewer -uv'
alias -- pv-v=pipe-viewer
alias -- pv-vinfo='pipe-viewer --video-info'
alias -- pv-vlc='pipe-viewer --player=vlc'
alias -- pv-week='pipe-viewer --time=week'
alias -- py=python3
alias -- rm='trash-put'
alias -- secret-get='secret-tool lookup'
alias -- secret-list='secret-tool search --all'
alias -- serve='python3 -m http.server 8000'
alias -- sesh-c='sesh connect'
alias -- sesh-k='sesh kill'
alias -- sesh-l='sesh list'
alias -- sesh-r='sesh last'
alias -- space=ncdu
alias -- starfast='export STARSHIP_CONFIG=$HOME/.config/starship/starship-fast.toml; exec zsh -l'
alias -- starfull='export STARSHIP_CONFIG=$HOME/.config/starship/starship-full.toml; exec zsh -l'
alias -- starship-debug='STARSHIP_LOG=debug starship module all'
alias -- starship-profile='if [[ "${STARSHIP_CONFIG:-}" == *"/starship-full.toml" ]]; then
  echo "Starship Mode: FULL"
else
  echo "Starship Mode: FAST"
fi
'
alias -- starship-test='starship print-config'
alias -- starship-timings='starship timings'
alias -- sysactive='systemctl list-units --state=active'
alias -- sysfailed='systemctl list-units --failed'
alias -- tree='eza --icons --tree --group-directories-first'
alias -- tsm=tsm
alias -- tsm-add='tsm add'
alias -- tsm-auto-remove='tsm auto-remove'
alias -- tsm-auto-tag='tsm auto-tag'
alias -- tsm-config='tsm config'
alias -- tsm-disk='tsm disk-check'
alias -- tsm-files='tsm files'
alias -- tsm-health='tsm health'
alias -- tsm-info='tsm info'
alias -- tsm-limit='tsm limit'
alias -- tsm-list='tsm list'
alias -- tsm-list-filter-complete='tsm list --filter="progress=100"'
alias -- tsm-list-filter-size='tsm list --filter="size>1GB"'
alias -- tsm-list-sort-name='tsm list --sort-by=name'
alias -- tsm-list-sort-progress='tsm list --sort-by=progress'
alias -- tsm-list-sort-size='tsm list --sort-by=size'
alias -- tsm-list-sort-status='tsm list --sort-by=status'
alias -- tsm-priority-high='tsm priority high'
alias -- tsm-priority-low='tsm priority low'
alias -- tsm-priority-normal='tsm priority normal'
alias -- tsm-purge='tsm purge'
alias -- tsm-purge-all='tsm purge all'
alias -- tsm-remove='tsm remove'
alias -- tsm-remove-all='tsm remove all'
alias -- tsm-remove-done='tsm remove-done'
alias -- tsm-schedule='tsm schedule'
alias -- tsm-search='tsm search'
alias -- tsm-search-cat='tsm search -l'
alias -- tsm-search-recent='tsm search -R'
alias -- tsm-speed='tsm speed'
alias -- tsm-start='tsm start'
alias -- tsm-start-all='tsm start all'
alias -- tsm-stats='tsm stats'
alias -- tsm-stop='tsm stop'
alias -- tsm-stop-all='tsm stop all'
alias -- tsm-tag='tsm tag'
alias -- tsm-tracker='tsm tracker'
alias -- tt='trash-put'
alias -- usage='du -h --max-depth=1 | sort -hr'
alias -- usb=lsusb
alias -- userlist='cut -d: -f1 /etc/passwd | sort'
alias -- vimrc='nvim ~/.config/nvim/init.lua'
alias -- vulns='grep . /sys/devices/system/cpu/vulnerabilities/*'
alias -- weather='curl wttr.in'
alias -- week='date +%V'
alias -- wget='wget -c'
alias -- youtube-dl=yt-dlp
alias -- yt=yt-dlp
alias -- yta='yt-dlp --extract-audio --audio-format mp3'
alias -- ytp-mp3='yt-dlp --yes-playlist --extract-audio --audio-format mp3 -o '\''%(playlist_index)s-%(title)s.%(ext)s'\'''
alias -- ytp-mp4='yt-dlp --yes-playlist -f '\''bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo+bestaudio'\'' --merge-output-format mp4 -o '\''%(playlist_index)s-%(title)s.%(ext)s'\'''
  alias -- ytv=yt-dlp
  alias -- yy=yazi
  alias -- zshrc='nvim ~/.config/zsh/.zshrc'
# =============================================================================
# Environment Variables and Core Setup
# =============================================================================
# Transmission script location for CLI access
export TSM_SCRIPT="tsm"

# =============================================================================
# Enhanced Vi Mode Configuration
# =============================================================================
bindkey -v
export KEYTIMEOUT=1

# Smart word characters for enhanced navigation
WORDCHARS='~!#$%^&*(){}[]<>?.+;-'
MOTION_WORDCHARS='~!#$%^&*(){}[]<>?.+;'

# Enhanced word movement functions
function smart-backward-word() {
  local WORDCHARS="${MOTION_WORDCHARS}"
  zle backward-word
}
function smart-forward-word() {
  local WORDCHARS="${MOTION_WORDCHARS}"
  zle forward-word
}
zle -N smart-backward-word
zle -N smart-forward-word

# =============================================================================
# Enhanced Vi Mode Visual Feedback System
# =============================================================================
function zle-keymap-select {
  case $KEYMAP in
    vicmd|NORMAL)
      echo -ne '\e[1 q'  # Block cursor for command mode
      ;;
    viins|INSERT|main)
      echo -ne '\e[5 q'  # Beam cursor for insert mode
      ;;
  esac
}

function zle-line-init {
  echo -ne '\e[5 q'  # Beam cursor on new line
}

zle -N zle-keymap-select
zle -N zle-line-init

# =============================================================================
# Smart History Navigation System
# =============================================================================
autoload -U up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search

# Vi mode history navigation
bindkey -M vicmd "k" up-line-or-beginning-search
bindkey -M vicmd "j" down-line-or-beginning-search
bindkey -M vicmd '?' history-incremental-search-backward
bindkey -M vicmd '/' history-incremental-search-forward
bindkey -M vicmd 'n' history-search-forward
bindkey -M vicmd 'N' history-search-backward

# Insert mode history (arrow keys and Ctrl shortcuts)
bindkey -M viins "^[[A" up-line-or-beginning-search
bindkey -M viins "^[[B" down-line-or-beginning-search
bindkey -M viins "^P" up-line-or-beginning-search
bindkey -M viins "^N" down-line-or-beginning-search

# =============================================================================
# Enhanced Navigation Key Bindings
# =============================================================================
# Line movement shortcuts
bindkey -M vicmd 'H' beginning-of-line
bindkey -M vicmd 'L' end-of-line
bindkey -M viins '^A' beginning-of-line
bindkey -M viins '^E' end-of-line

# Word movement (Ctrl+arrows for both modes)
bindkey -M vicmd '^[[1;5C' smart-forward-word
bindkey -M viins '^[[1;5C' smart-forward-word
bindkey -M vicmd '^[[1;5D' smart-backward-word
bindkey -M viins '^[[1;5D' smart-backward-word

# Alt+arrows for word movement alternative
bindkey -M viins '^[f' smart-forward-word
bindkey -M viins '^[b' smart-backward-word

# =============================================================================
# Enhanced Editing Key Bindings
# =============================================================================
# Vi mode enhancements
bindkey -M vicmd 'Y' vi-yank-eol
bindkey -M vicmd 'v' edit-command-line
bindkey -M vicmd 'gg' beginning-of-buffer-or-history
bindkey -M vicmd 'G' end-of-buffer-or-history

# Insert mode editing shortcuts
bindkey -M viins '^?' backward-delete-char
bindkey -M viins '^H' backward-delete-char
bindkey -M viins '^U' backward-kill-line
bindkey -M viins '^K' kill-line
bindkey -M viins '^Y' yank

# Smart word deletion function
function smart-backward-kill-word() {
  local WORDCHARS="${WORDCHARS//:}"
  WORDCHARS="${WORDCHARS//\/}"
  WORDCHARS="${WORDCHARS//.}"
  WORDCHARS="${WORDCHARS//-}"
  zle backward-kill-word
}
zle -N smart-backward-kill-word
bindkey -M viins '^W' smart-backward-kill-word
bindkey -M vicmd '^W' smart-backward-kill-word

# Autosuggestion bindings
bindkey -M viins '^F' autosuggest-accept
bindkey -M viins '^L' autosuggest-accept
bindkey -M viins '^[[Z' autosuggest-execute  # Shift+Tab

# =============================================================================
# FZF Integration Key Bindings
# =============================================================================
if command -v fzf > /dev/null; then
  # Enhanced FZF bindings for both modes
  bindkey -M viins '^T' fzf-file-widget       # Ctrl+T: Files
  bindkey -M viins '^R' fzf-history-widget    # Ctrl+R: History
  bindkey -M viins '^[c' fzf-cd-widget        # Alt+C: Directories
  
  # Vi command mode FZF bindings
  bindkey -M vicmd '^T' fzf-file-widget
  bindkey -M vicmd '^R' fzf-history-widget
  bindkey -M vicmd '^[c' fzf-cd-widget
fi

# =============================================================================
# Terminal Integration Key Bindings
# =============================================================================
# Clear screen for both modes
bindkey -M viins '^L' clear-screen
bindkey -M vicmd '^L' clear-screen

# Suspend/Resume functionality
bindkey -M viins '^Z' push-input
bindkey -M vicmd '^Z' push-input

# =============================================================================
# ZSH Completion System for Transmission CLI
# =============================================================================
_tsm_completions() {
    local commands=(
        # Core transmission commands
        "list:Display torrent list with status information"
        "add:Add new torrent from file or magnet link"
        "info:Show detailed information about specific torrent"
        "speed:Display current download/upload speeds"
        "files:List files contained in torrent"
        "config:Configure authentication credentials"
        
        # Search and discovery commands
        "search:Search for torrents by keyword"
        "search-cat:List available torrent categories"
        "search-recent:Search in recent torrents (last 48 hours)"
        
        # Individual torrent management
        "start:Start downloading specified torrent"
        "stop:Stop downloading specified torrent"
        "remove:Remove torrent from client (keep files)"
        "purge:Remove torrent and delete all files"
        
        # Batch operation commands
        "start-all:Start all torrents in queue"
        "stop-all:Stop all active torrents"
        "remove-all:Remove all torrents (keep files)"
        "purge-all:Remove all torrents and delete files"
        
        # Advanced management features
        "health:Check torrent health and connectivity"
        "stats:Show detailed client statistics"
        "disk:Check disk usage and available space"
        "tracker:Display tracker information and status"
        "limit:Set speed limits for downloads/uploads"
        "auto-remove:Enable automatic removal of completed torrents"
        "remove-done:Remove all completed torrents"
        
        # Priority and scheduling
        "priority:Set torrent priority (high/normal/low)"
        "schedule:Schedule torrent start/stop times"
        "tag:Add custom tags to torrents"
        "auto-tag:Automatically tag torrents by content type"
        
        # List management and filtering
        "list-sort:Sort torrent list by criteria"
        "list-filter:Filter torrents by specific conditions"
    )
    _describe 'tsm commands' commands
}
compdef _tsm_completions tsm

# =============================================================================
# File Manager Functions (Yazi Integration)
# =============================================================================
# Main Yazi wrapper function with directory change support
function y() {
  local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
  yazi "$@" --cwd-file="$tmp"
  if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
    builtin cd -- "$cwd"
  fi
  rm -f -- "$tmp"
}

# Alternative Yazi function with 'k' command
function k() {
  local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
  yazi "$@" --cwd-file="$tmp"
  if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
    builtin cd -- "$cwd"
  fi
  rm -f -- "$tmp"
}

# =============================================================================
# Network Utility Functions
# =============================================================================
# Multi-source external IP detection function
function wanip() {
  local ip
  # Try Mullvad first (privacy-focused)
  ip=$(curl -s https://am.i.mullvad.net/ip 2>/dev/null) && echo "Mullvad IP: $ip" && return 0
  # Fallback to OpenDNS
  ip=$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null) && echo "OpenDNS IP: $ip" && return 0
  # Fallback to Google DNS
  ip=$(dig TXT +short o-o.myaddr.l.google.com @ns1.google.com 2>/dev/null | tr -d '"') && echo "Google DNS IP: $ip" && return 0
  echo "Error: Could not determine external IP address"
  return 1
}

# File transfer function using transfer.sh service
function transfer() {  
  if [ -z "$1" ]; then
    echo "Usage: transfer FILE_TO_TRANSFER"
    return 1
  fi
  tmpfile=$(mktemp -t transferXXX)
  curl --progress-bar --upload-file "$1" "https://transfer.sh/$(basename $1)" >> $tmpfile
  cat $tmpfile
  rm -f $tmpfile
}

# =============================================================================
# Pipe Viewer — Akıllı Fonksiyonlar (fallback'lı, Nix-safe)
# =============================================================================
export PV_CMD="pipe-viewer"

# pv-tr <kategori> [bölge]
# kategori: popular | music | gaming | news | movies
pv-tr() {
  local cat="$1"
  local region="$2"
  [ -z "$cat" ] && cat="popular"
  [ -z "$region" ] && region="TR"

  "$PV_CMD" --invidious --api=auto --trending="$cat" --region="$region" \
  || "$PV_CMD" --no-invidious --ytdl --trending="$cat" --region="$region"
}

# pv-find "anahtar kelimeler" [ek pipe-viewer argümanları...]
pv-find() {
  if [ -z "$1" ]; then
    echo "Usage: pv-find \"keywords\" [extra pipe-viewer opts]"; return 1
  fi
  local q="$1"; shift
  "$PV_CMD" --no-invidious --ytdl --search-videos "$q" "$@"
}

# pv-playx [--best | --resolution=720p | ...] "<url|keywords>" [ek opsiyonlar...]
# URL ise direkt oynatır; değilse arayıp listeler.
pv-playx() {
  local opts=()
  while [ -n "$1" ] && printf "%s" "$1" | grep -qE '^--'; do
    opts+=( "$1" )
    shift
  done

  if [ -z "$1" ]; then
    echo "Usage: pv-playx [--best|--resolution=...] <url|keywords> [extra opts]"; return 1
  fi

  local input="$1"; shift
  if printf "%s" "$input" | grep -qE '^https?://|(^| )youtu(\.be|be\.com)'; then
    "$PV_CMD" --no-invidious --ytdl "${opts[@]}" "$input" "$@"
  else
    "$PV_CMD" --no-invidious --ytdl --search-videos "${opts[@]}" "$input" "$@"
  fi
}

# pv-audiox "<url|keywords>" [--audio-quality=best|medium|low]
pv-audiox() {
  if [ -z "$1" ]; then
    echo "Usage: pv-audiox <url|keywords> [--audio-quality=best|medium|low]"; return 1
  fi
  local input="$1"; shift
  if printf "%s" "$input" | grep -qE '^https?://'; then
    "$PV_CMD" --no-invidious --ytdl -n -a --audio-quality=best "$input" "$@"
  else
    "$PV_CMD" --no-invidious --ytdl -n -a --audio-quality=best --search-videos "$input" "$@"
  fi
}

# pv-dlx [--dir="..."] [--name="%T - %t.%e"] <url|keywords>
# Ör: pv-dlx --dir="$HOME/Videos" --name="%T - %t.%e" "linux news"
pv-dlx() {
  local dldir="."
  local namefmt="%T - %t.%e"
  local args=()

  while [ -n "$1" ] && printf "%s" "$1" | grep -qE '^--'; do
    case "$1" in
      --dir=*)
        dldir="$(printf "%s" "$1" | sed 's/^--dir=//')"
        ;;
      --name=*)
        namefmt="$(printf "%s" "$1" | sed 's/^--name=//')"
        ;;
      *)
        args+=( "$1" )
        ;;
    esac
    shift
  done

  if [ -z "$1" ]; then
    echo "Usage: pv-dlx [--dir=DIR] [--name=FMT] <url|keywords>"; return 1
  fi

  local input="$1"; shift
  mkdir -p "$dldir"

  if printf "%s" "$input" | grep -qE '^https?://'; then
    "$PV_CMD" --no-invidious --ytdl -d --skip-if-exists --dl-in-subdir \
      --downloads-dir="$dldir" --filename="$namefmt" "$input" "$@" "${args[@]}"
  else
    "$PV_CMD" --no-invidious --ytdl -d --skip-if-exists --dl-in-subdir \
      --downloads-dir="$dldir" --filename="$namefmt" --search-videos "$input" "$@" "${args[@]}"
  fi
}

# pv-commentsx <id|url> [relevance|time]
pv-commentsx() {
  if [ -z "$1" ]; then
    echo "Usage: pv-commentsx <video-id|url> [relevance|time]"; return 1
  fi
  local target="$1"
  local order="$2"
  [ -z "$order" ] && order="relevance"

  "$PV_CMD" --comments="$target" --comments-order="$order" \
  || "$PV_CMD" --ytdl --comments="$target" --comments-order="$order"
}

# pv-plx list|play <playlist-id>
pv-plx() {
  if [ "$1" != "list" ] && [ "$1" != "play" ]; then
    echo "Usage: pv-plx list|play <playlist-id>"; return 1
  fi
  local mode="$1"; shift
  local pid="$1"

  if [ -z "$pid" ]; then
    echo "Missing <playlist-id>"; return 1
  fi

  if [ "$mode" = "list" ]; then
    "$PV_CMD" --pid="$pid"
  else
    "$PV_CMD" --no-invidious --ytdl --pp="$pid"
  fi
}

# pv-chx <channel|@handle> uploads|streams|shorts|popular|pstreams|pshorts
pv-chx() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: pv-chx <channel> <uploads|streams|shorts|popular|pstreams|pshorts>"; return 1
  fi
  local ch="$1"
  local mode="$2"

  case "$mode" in
    uploads)   "$PV_CMD" -uv "$ch" ;;
    streams)   "$PV_CMD" -us "$ch" ;;
    shorts)    "$PV_CMD" --shorts "$ch" ;;
    popular)   "$PV_CMD" -pv "$ch" ;;
    pstreams)  "$PV_CMD" -ps "$ch" ;;
    pshorts)   "$PV_CMD" --pshorts "$ch" ;;
    *) echo "Invalid mode: $mode"; return 1 ;;
  esac
}

# pv-reg <ISO-REGION>  (ör: pv-reg TR)
pv-reg() {
  if [ -z "$1" ]; then
    echo "Usage: pv-reg <REGION>"; return 1
  fi
  local region="$1"
  "$PV_CMD" --no-invidious --ytdl --trending=popular --region="$region" \
  || "$PV_CMD" --invidious --api=auto --trending=popular --region="$region"
}

# pv-open ...  → pipe-viewer'a argümanları doğrudan geçir
pv-open() {
  if [ "$#" -eq 0 ]; then
    "$PV_CMD" --help
    return 0
  fi
  "$PV_CMD" "$@"
}

# =============================================================================
# File Editing Utility Functions
# =============================================================================
# Quick file editor with automatic creation and permissions
function v() {
  local file="$1"
  if [[ -z "$file" ]]; then
    echo "Error: Filename required."
    return 1
  fi
  [[ ! -f "$file" ]] && touch "$file"
  chmod 755 "$file"
  vim -c "set paste" "$file"
}

# Edit command by path (which-edit)
function vw() {
  local file
  if [[ -n "$1" ]]; then
    file=$(which "$1" 2>/dev/null)
    if [[ -n "$file" ]]; then
      echo "File found: $file"
      vim "$file"
    else
      echo "File not found: $1"
    fi
  else
    echo "Usage: vw <command-name>"
  fi
}

# =============================================================================
# Archive Management Functions
# =============================================================================
# Universal archive extraction function
function ex() {
  if [ -f $1 ] ; then
    case $1 in
      *.tar.bz2)   tar xjf $1   ;;
      *.tar.gz)    tar xzf $1   ;;
      *.bz2)       bunzip2 $1   ;;
      *.rar)       unrar x $1   ;;
      *.gz)        gunzip $1    ;;
      *.tar)       tar xf $1    ;;
      *.tbz2)      tar xjf $1   ;;
      *.tgz)       tar xzf $1   ;;
      *.zip)       unzip $1     ;;
      *.Z)         uncompress $1;;
      *.7z)        7z x $1      ;;
      *.deb)       ar x $1      ;;
      *.tar.xz)    tar xf $1    ;;
      *.tar.zst)   tar xf $1    ;;
      *)           echo "'$1' cannot be extracted with ex()" ;;
    esac
  else
    echo "'$1' is not a valid file"
  fi
}

# =============================================================================
# FZF Enhanced Search Functions
# =============================================================================
# File content search with preview
function fif() {
  if [ ! "$#" -gt 0 ]; then echo "Search term required"; return 1; fi
  fd --type f --hidden --follow --exclude .git \
  | fzf -m --preview="bat --style=numbers --color=always {} 2>/dev/null | rg --colors 'match:bg:yellow' --ignore-case --pretty --context 10 '$1' || rg --ignore-case --pretty --context 10 '$1' {}"
}

# Directory history search
function fcd() {
  local dir
  dir=$(dirs -v | fzf --height 40% --reverse | cut -f2-)
  if [[ -n "$dir" ]]; then
    cd "$dir"
  fi
}

# Git commit search and checkout
function fgco() {
  local commits commit
  commits=$(git log --pretty=oneline --abbrev-commit --reverse) &&
  commit=$(echo "$commits" | fzf --tac +s +m -e) &&
  git checkout $(echo "$commit" | sed "s/ .*//")
}

# Quick commit function (English single-line message)
function gc() {
  if [ -z "$1" ]; then
    echo "Usage: gc <commit-message>"
    echo "Example: gc 'fix: resolve login issue'"
    return 1
  fi
  git add -A && git commit -m "$1"
}

# Interactive commit message function
function gci() {
  git add -A
  echo "Enter commit message (English, single line):"
  read -r message
  if [ -n "$message" ]; then
    git commit -m "$message"
  else
    echo "Commit cancelled: empty message"
    return 1
  fi
}

# =============================================================================
# History Management Function
# =============================================================================
function cleanhistory() {
  print -z $( ([ -n "$ZSH_NAME" ] && fc -l 1 || history) | fzf +m --height 50% --reverse --border --header="DEL key to delete selected command, ESC to exit" \
  --bind="del:execute(sed -i '/{}/d' $HISTFILE)+reload(fc -R; ([ -n "$ZSH_NAME" ] && fc -l 1 || history))" \
  --preview="echo {}" --preview-window=up:3:hidden:wrap --bind="?:toggle-preview")
}

# =============================================================================
# Session Management Functions (Sesh Integration)
# =============================================================================
# Enhanced session manager with FZF integration
if ! typeset -f sesh-sessions > /dev/null; then
  function sesh-sessions() {
    {
      exec </dev/tty
      exec <&1
      local session
      session=$(sesh list -t -c | fzf --height 40% --reverse --border-label ' sesh ' --border --prompt '⚡  ')
      zle reset-prompt > /dev/null 2>&1 || true
      [[ -z "$session" ]] && return
      sesh connect $session
    }
  }
  zle -N sesh-sessions
fi

# Sesh session management key bindings
bindkey -M viins '^[s' sesh-sessions    # Alt+S in insert mode
bindkey -M vicmd '^[s' sesh-sessions    # Alt+S in command mode
bindkey -M viins '\es' sesh-sessions    # Alternative Alt+S binding
bindkey -M vicmd '\es' sesh-sessions    # Alternative Alt+S binding

# Go
export GOPATH="$HOME/.local/share/go"
export PATH="$PATH:$GOPATH/bin"
