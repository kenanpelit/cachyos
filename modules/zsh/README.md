# Zsh Module

This module owns the interactive Zsh environment used by the desktop profile:
startup environment, plugin loading, completion setup, aliases, key bindings,
and shell helper functions.

## Layout

- [dotfiles/.zshenv](./dotfiles/.zshenv)
  is the canonical always-loaded environment file. It sets XDG fallbacks,
  `ZDOTDIR`, editor/browser defaults, history sizing, and Zsh cache paths.
- [dotfiles/zsh/.zprofile](./dotfiles/zsh/.zprofile)
  handles login-shell handoff to the TTY/session autostart path.
- [dotfiles/zsh/.zshrc](./dotfiles/zsh/.zshrc)
  owns interactive behavior: plugin setup, completion cache policy, tool
  integrations, guarded aliases, key bindings, and helper functions.
- [dotfiles/zsh/completions/](./dotfiles/zsh/completions)
  contains repo-managed completion definitions that are loaded through `fpath`
  before `compinit`.
- [dotfiles/zsh/themes/](./dotfiles/zsh/themes)
  contains the syntax-highlighting color theme.

Runtime files such as `history` and `.zcompdump` are intentionally ignored by
git and should not be reviewed as source config.

## Design Notes

- Shell startup must not perform network work. Zinit is expected to exist under
  `ZINIT_HOME`; if it is missing, the shell stays usable and skips plugins.
- Heavy language managers are lazy-loaded. The wrapper preserves the command
  that was invoked, so `node`, `npm`, `ruby`, `python`, and `pip` execute the
  real command after the manager initializes.
- Modern replacement tools are guarded. Aliases for `bat`, `eza`, `fd`,
  `delta`, `trash-put`, `procs`, `ncdu`, and `zoxide` are only installed when
  the matching command exists.
- Completion state is cached under `ZSH_COMPDUMP` with a lock-aware `compinit`
  wrapper to keep parallel shells from rebuilding the same dump at once.
- Destructive helpers should be functions with confirmation, not raw `rm -rf`
  aliases.

## Quick Checks

```sh
zsh -n modules/zsh/dotfiles/zsh/.zshrc
zsh -n modules/zsh/dotfiles/zsh/completions/_tsm
```
