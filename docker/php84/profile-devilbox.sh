# [Devilbox] PATH for the locally built PHP containers.
#
# Installed as /etc/profile.d/zzz-devilbox.sh, so every login shell gets it --
# including the non-interactive `bash -lc ...` used by scripts. The interactive
# bits (prompt, aliases, /etc/bashrc-devilbox.d) live in /etc/bash-devilbox,
# which is sourced from ~/.bashrc so it wins over the Debian defaults there.
#
# Written to be safely re-sourceable: an interactive login shell reaches this
# file more than once and must not accumulate duplicate PATH entries.
_dvl_path_prepend() {
    case ":${PATH}:" in
        *":$1:"*) ;;
        *) PATH="$1:${PATH}" ;;
    esac
}
_dvl_path_append() {
    case ":${PATH}:" in
        *":$1:"*) ;;
        *) PATH="${PATH}:$1" ;;
    esac
}

_dvl_path_append /usr/local/bin
_dvl_path_append /usr/local/sbin
# Prepended last-to-first, so the composer bin dir ends up in front.
_dvl_path_prepend "${HOME}/.local/bin"
_dvl_path_prepend "${HOME}/.yarn/bin"
# Composer 2 uses XDG paths; keep the Composer 1 location working too, since
# older docs and the stock devilbox images refer to ~/.composer.
_dvl_path_prepend "${HOME}/.composer/vendor/bin"
_dvl_path_prepend "${HOME}/.config/composer/vendor/bin"

unset -f _dvl_path_prepend _dvl_path_append
export PATH
