# ~/.bash_profile (portable)

# include .profile if it exists
[[ -f ~/.profile ]] && . ~/.profile

# include .bashrc if it exists
[[ -f ~/.bashrc ]] && . ~/.bashrc

# Added by Antigravity CLI installer
export PATH="$HOME/.local/bin:$PATH"
