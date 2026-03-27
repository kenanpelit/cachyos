#!/bin/sh

case $SHELL in
  */bash)
    [ -z "$BASH" ] && exec $SHELL "$0" "$@"
    set +o posix
    [ -f /etc/profile ] && . /etc/profile
    if [ -f "$HOME/.bash_profile" ]; then
      . "$HOME/.bash_profile"
    elif [ -f "$HOME/.bash_login" ]; then
      . "$HOME/.bash_login"
    elif [ -f "$HOME/.profile" ]; then
      . "$HOME/.profile"
    fi
    ;;
  */zsh)
    [ -z "$ZSH_NAME" ] && exec $SHELL "$0" "$@"
    [ -d /etc/zsh ] && zdir=/etc/zsh || zdir=/etc
    zhome=${ZDOTDIR:-$HOME}
    [ -f "$zdir/zprofile" ] && . "$zdir/zprofile"
    [ -f "$zhome/.zprofile" ] && . "$zhome/.zprofile"
    [ -f "$zdir/zlogin" ] && . "$zdir/zlogin"
    [ -f "$zhome/.zlogin" ] && . "$zhome/.zlogin"
    emulate -R sh
    ;;
  */fish)
    [ -f /etc/profile ] && . /etc/profile
    xsess_tmp="$(mktemp /tmp/xsess-env-XXXXXX)"
    $SHELL --login -c "/bin/sh -c 'export -p' > \"$xsess_tmp\""
    . "$xsess_tmp"
    rm -f "$xsess_tmp"
    ;;
  *)
    [ -f /etc/profile ] && . /etc/profile
    [ -f "$HOME/.profile" ] && . "$HOME/.profile"
    ;;
esac

[ -f /etc/xprofile ] && . /etc/xprofile
[ -f "$HOME/.xprofile" ] && . "$HOME/.xprofile"

if [ -d /etc/X11/xinit/xinitrc.d ]; then
  for i in /etc/X11/xinit/xinitrc.d/*; do
    [ -x "$i" ] && . "$i"
  done
fi

if [ -d /etc/X11/Xresources ]; then
  for i in /etc/X11/Xresources/*; do
    [ -f "$i" ] && xrdb -merge "$i"
  done
elif [ -f /etc/X11/Xresources ]; then
  xrdb -merge /etc/X11/Xresources
fi

[ -f "$HOME/.Xresources" ] && xrdb -merge "$HOME/.Xresources"

if [ -z "$*" ]; then
  exec xmessage -center -buttons OK:0 -default OK "No valid X session command was provided."
fi

exec "$@"
