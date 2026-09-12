# [Devilbox] Interactive shell setup for the locally built PHP containers.
#
# Installed as /etc/bash-devilbox and sourced from the tail of ~/.bashrc (same
# convention as the stock devilbox/php-fpm images), which is what makes the
# prompt below survive the Debian default further up in that file.

# ~/.bashrc is also read by `docker compose exec`, which never runs
# /etc/profile.d, so make sure PATH is set up here too.
if [ -r /etc/profile.d/zzz-devilbox.sh ]; then
    . /etc/profile.d/zzz-devilbox.sh
fi

[ -z "${PS1}" ] && return

# Anything the user drops into the host-side `bash/` directory.
if [ -d /etc/bashrc-devilbox.d/ ]; then
    for _dvl_f in /etc/bashrc-devilbox.d/*.sh; do
        [ -f "${_dvl_f}" ] || continue
        # shellcheck disable=SC1090
        . "${_dvl_f}"
    done
    unset _dvl_f
fi

if [ -r /usr/share/bash-completion/bash_completion ]; then
    # shellcheck disable=SC1091
    . /usr/share/bash-completion/bash_completion
fi

# Name the container in the prompt, so it is obvious which PHP version the
# shell is attached to.
PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]$ '

alias ls='ls --color=auto'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'
