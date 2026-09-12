#!/bin/sh
set -e

# Keep bind-mounted project files writable from the host.
if [ -n "${NEW_GID}" ]; then groupmod -o -g "${NEW_GID}" devilbox >/dev/null 2>&1 || true; fi
if [ -n "${NEW_UID}" ]; then usermod  -o -u "${NEW_UID}" -g "${NEW_GID:-1000}" devilbox >/dev/null 2>&1 || true; fi

# usermod does not chown the home directory when the uid changes, and the tool
# caches below have to belong to the devilbox user or composer/npm/yarn bail out.
for _dir in /home/devilbox \
            /home/devilbox/.cache \
            /home/devilbox/.config \
            /home/devilbox/.config/composer \
            /home/devilbox/.composer \
            /home/devilbox/.npm \
            /home/devilbox/.local \
            /var/log/php; do
	mkdir -p "${_dir}" 2>/dev/null || true
	chown "${NEW_UID:-1000}:${NEW_GID:-1000}" "${_dir}" 2>/dev/null || true
done

if [ -n "${TIMEZONE}" ] && [ -f "/usr/share/zoneinfo/${TIMEZONE}" ]; then
	ln -snf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
	echo "${TIMEZONE}" > /etc/timezone
fi

# *.dvl.to resolves to 127.0.0.1 (public wildcard), so container-to-container API
# calls need the same localhost forwarding the devilbox php image sets up via
# FORWARD_PORTS_TO_LOCALHOST. Without this, http://myproject.dvl.to/ from here is a
# connection refused.
socat TCP-LISTEN:80,fork,reuseaddr,bind=127.0.0.1    TCP:httpd:80    &
socat TCP-LISTEN:443,fork,reuseaddr,bind=127.0.0.1   TCP:httpd:443   &
socat TCP-LISTEN:3306,fork,reuseaddr,bind=127.0.0.1  TCP:mysql:3306  &
socat TCP-LISTEN:5432,fork,reuseaddr,bind=127.0.0.1  TCP:pgsql:5432  &
socat TCP-LISTEN:6379,fork,reuseaddr,bind=127.0.0.1  TCP:redis:6379  &
socat TCP-LISTEN:11211,fork,reuseaddr,bind=127.0.0.1 TCP:memcd:11211 &
socat TCP-LISTEN:27017,fork,reuseaddr,bind=127.0.0.1 TCP:mongo:27017 &

exec "$@"
