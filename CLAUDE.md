# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

A fork of upstream [cytopia/devilbox](https://github.com/cytopia/devilbox) — a Docker-based
zero-conf LEMP stack — with two deviations from upstream:

1. **PHP 8.3 / 8.4 support**, built locally, because the upstream `devilbox/php-fpm` images stop
   at 8.2 (see [Multi-PHP](#multi-php));
2. **all persistent data on host bind mounts** instead of named Docker volumes, so a
   `docker compose down -v` or a Docker Desktop reset cannot destroy the databases
   (see [Databases](#databases--data-lives-on-the-host-not-in-volumes)).

Everything else tracks upstream. Two layers of code exist here and should not be confused:

* **the stack** (this repo: compose files, `cfg/`, `docker/`, `.devilbox/` intranet) — infrastructure;
* **the projects** (`data/www/<name>/`) — separate applications, each with its own tooling. They are
  gitignored and are not part of this git tree.

Local customisation belongs in the files git ignores — `.env`, `docker-compose.override.yml`,
`data/` — or in the hook directories described under [Conventions](#conventions). Avoid editing
`docker-compose.yml` or `env-example` unless there is no override hook for the change.

## Everyday commands

```bash
docker compose up -d httpd php mysql   # start; bind/php pulled in via depends_on
docker compose up -d php84             # bring up ONE service — a bare `up -d` restarts everything
docker compose stop
./shell.sh                             # shell (user devilbox) in the default `php` container
./shell.sh php71                       # shell in the pinned 7.1 container
./shell.sh php84                       # shell in the locally built 8.4 container
docker compose build php84             # rebuild the local image after editing docker/php84/
./check-config.sh                      # validate .env / docker-compose consistency
./update-docker.sh [php|httpd|mysql|bind|rest]   # pull the image tags this git state pins
docker exec devilbox-httpd-1 supervisorctl restart watcherd   # re-generate vhosts
./backup-databases.sh [mysql|pgsql]    # dump all databases to backups/ (gzipped, keeps 7)
```

Logs land on the host under `log/<service>/` and are gitignored.

### Upstream test suite (`.tests/`)

`make -C .tests test-smoke-intranet`, `test-smoke-vhosts`, `test-smoke-modules`,
`test-smoke-vendors`, `test-smoke-ssl`, `test-smoke-framework-wordpress`, `test-smoke-container`, …
Individual tests are plain scripts: `.tests/tests/intranet-vhost.sh`. Shell lint:
`make -C .tests lint-tests` (dockerised shellcheck).

⚠️ `make -C .tests start` **rewrites `.env`** (`HOST_PATH_HTTPD_DATADIR=.tests/www`,
`DEBUG_ENTRYPOINT=3`) and detaches the stack from your real projects. Back up `.env` before running
it. The smoke tests assume that fixture setup, so they are mostly of use when debugging the stack
itself, not the projects running on it.

## Architecture

### Request path

`httpd` (nginx) runs `watcherd` + `vhost-gen`: every directory in `data/www/` automatically becomes
the vhost `<dirname>.dvl.to`, served from `<dirname>/<HTTPD_DOCROOT_DIR>` (`.env`), with a
self-signed cert. nginx passes `SCRIPT_FILENAME` as an absolute path under `/shared/httpd`, which is
why **every** PHP container must bind-mount `data/www` at exactly that path.

* Default FPM backend: `conf:phpfpm:tcp:172.16.238.10:9000` (the `php` service).
* Per-project override: `data/www/<project>/.devilbox/backend.cfg`, a single line such as
  `conf:phpfpm:tcp:172.16.238.212:9000`. Active by default: `MASS_VHOST_BACKEND_REWRITE=file:backend.cfg`
  is hardcoded in `docker-compose.yml` (httpd environment), not a `.env` setting.
* A per-project vhost template can be dropped in `data/www/<project>/.devilbox/`
  (`.env:HTTPD_TEMPLATE_DIR`), overriding `cfg/vhost-gen/`.
* After adding a project or editing `backend.cfg`, restart `watcherd` (command above) — no container
  restart needed.

Static IPs on `app_net` (172.16.238.0/24): `bind .100`, `php .10`, `httpd .11`, `mysql .12`,
`pgsql .13`, `redis .14`, `memcd .15`, `mongo .16`. The override adds `php71 .201`, `php83 .211`
and `php84 .212`; keep new services in the `.2xx` range to stay clear of upstream.

### Multi-PHP

Upstream is effectively dead: `devilbox/php-fpm` stops at `8.2-work-0.151` (2023-02), so
`.env:PHP_SERVER` cannot go past 8.2. Newer versions are built locally from official `php:X-fpm`.

| Service | Image | Role |
|---------|-------|------|
| `php`   | `devilbox/php-fpm:${PHP_SERVER}-work-0.150` | default for every project without `backend.cfg` |
| `php71` | same image, pinned to 7.1 | legacy projects that cannot move off 7.1 |
| `php83` | `devilbox-local/php-fpm:8.3`, built from `docker/php83/` | opt-in via `backend.cfg` |
| `php84` | `devilbox-local/php-fpm:8.4`, built from `docker/php84/` | opt-in via `backend.cfg` |

A pinned container such as `php71` exists so `PHP_SERVER` can be raised for everything else without
breaking projects stuck on an old version. Note the consequence: a project's **web** PHP version
(`backend.cfg`) and its **CLI** PHP version (`./shell.sh <service>`) are chosen independently — a
project Makefile that shells into `php` gets `PHP_SERVER`'s version even if its vhost runs on 8.4.

`docker/php8*/` reproduces the devilbox conventions the rest of the stack assumes: `/shared/httpd`
mount path, `/etc/php-custom.d` + `/etc/php-fpm-custom.d` drop-ins, `/etc/bashrc-devilbox.d`, a
`devilbox` user (uid 1000, remapped from `NEW_UID`/`NEW_GID` in `entrypoint.sh` — without it
`docker compose exec --user devilbox` fails), and `socat` port forwarders to localhost mirroring the
stock image's `FORWARD_PORTS_TO_LOCALHOST`.

### PHP configuration drop-ins

`cfg/php-ini-<ver>/` loads **only `*.ini`**; `cfg/php-fpm-<ver>/` loads **only `*.conf`**. The
shipped `devilbox-php.ini-*` and `devilbox-fpm.conf-*` files are inert examples — editing them
changes nothing. To change settings, add a real file.

`cfg/php-ini-8.4/devilbox.ini` and `cfg/php-fpm-8.4/devilbox.conf` are the active ones for the local
8.4 image and are committed in this fork, since they are what the locally built image needs
re-established: dev error reporting, `user = devilbox`, `clear_env = no`, `catch_workers_output`,
opcache revalidation. Use them as the reference when adding a new version. Any *other* `.ini`/`.conf`
you drop in these directories stays local — `.gitignore` only makes an exception for `devilbox.ini`
and `devilbox.conf`.

Alphabetically last `.ini` wins.

### Databases — data lives on the host, not in volumes

`docker-compose.override.yml` **replaces** the `mysql` service with `mysql:5.7` under
`platform: linux/amd64` (Rosetta emulation on Apple Silicon) on host port **3306**, with an empty
root password. This bypasses `.env:MYSQL_SERVER` and `HOST_PORT_MYSQL` — reading `.env` alone will
mislead you about which database is actually running. Verify merges with
`docker compose config --format json`.

**Every** persistent data directory is a **host bind mount**; the stack declares no named volume:

| Container path | Host path | Services |
|---|---|---|
| `/var/lib/mysql` | `data/mysql-datadir/` | `mysql` |
| `/var/lib/postgresql/data/pgdata` (`$PGDATA`) | `data/pgsql-datadir/` | `pgsql` |
| `/data/db` | `data/mongo-datadir/` | `mongo` |
| `/var/mail` | `data/mail/` | all PHP containers |

This is deliberate: named volumes are destroyed by `docker compose down -v`, `docker volume prune`,
`docker system prune --volumes` and by any Docker Desktop reset or disk-image resize. Host
directories survive all of that, so **Docker-level cleanup is not a data-loss risk here**.
Consequences to respect:

* The pgsql bind mount must target `/var/lib/postgresql/data/pgdata`, not `.../data` — the base
  compose file sets `PGDATA` to the `pgdata` subdirectory and mounts there; a mismatched target
  leaves the upstream named volume in place.
* `data/*-datadir/` and `data/mail/` are gitignored and must never be committed or copied while the
  service is running.
* `/var/mail` is shared by all PHP containers (`PHP_MAIL_CATCH_ALL` delivers intercepted mail there
  and the intranet reads it) — switch them together or they end up on different spools.
* A bind mount protects against *deletion*, not *corruption* — corrupt InnoDB pages are corrupt on
  the host too. `./backup-databases.sh [mysql|pgsql]` dumps every database to `backups/<engine>/` as
  gzipped SQL, keeping the newest 7 per database. Run it before risky operations.

⚠️ **Never commit a database dump.** `.gitignore` blocks `*.sql`/`*.sql.gz` at the repo root and
under `cfg/` and `data/`, because a production dump carries password hashes, API keys and personal
data.

`docker-compose.yml` carries one local edit: `${HOST_PATH_MYSQL_DATADIR}:/shared/mysql`, so host
`data/mysql/*.sql` is importable from inside the mysql container. Redis, Memcached and Mongo are
stock and reachable from the host on their default ports.

### Disk usage

On macOS, Docker Desktop's virtual disk
(`~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw`) is sparse and capped by
`DiskSizeMiB` in `~/Library/Group Containers/group.com.docker/settings-store.json`. Actual usage is
`docker system df`, not the apparent `ls -l` size of `Docker.raw`. `data/www/` lives on the host and
is *not* part of that figure.

**Lowering that limit wipes the virtual disk** — every image, container and named volume goes.
Recovery is `docker compose build php84` plus an explicit
`docker compose up -d bind php php71 php84 httpd mysql pgsql redis memcd mongo` (name the services —
a bare `up -d` also starts the unused `cockroach` example service from the override, ~1.5 GB). With
no named volumes left, `docker system prune -a --volumes` does not touch the databases.

### Networking gotchas

* `*.dvl.to` resolves to `127.0.0.1` via public wildcard DNS, but only for names the wildcard
  actually answers — a new vhost usually needs a `127.0.0.1 <name>.dvl.to` line in the host
  `/etc/hosts`.
* Inside containers, `http://<project>.dvl.to/` therefore hits localhost; it works only because of
  the socat forwarders (stock images: `FORWARD_PORTS_TO_LOCALHOST`; local images:
  `docker/php8*/entrypoint.sh`). Cross-container HTTP/API calls break without them.
* The intranet is at `http://localhost` (`DEVILBOX_UI_ENABLE=1`); its PHP source is `.devilbox/www/`
  and it bundles phpMyAdmin/Adminer/phpPgAdmin/phpRedmin.

## Conventions

* Stack changes go in `docker-compose.override.yml` (services), `.env` (settings),
  `cfg/<ver>/*.ini|*.conf` (PHP config), `docker/php8*/` (image contents). `compose/` holds upstream
  example overrides worth copying from.
* Anything that must survive a container being rebuilt belongs on a host bind mount, not a named
  volume — see the database section above.
* A new PHP version = new `docker/phpXY/` + `cfg/php-ini-X.Y/` + `cfg/php-fpm-X.Y/` + `log/php-fpm-X.Y/`
  + a service on a free `172.16.238.2xx` IP + `backend.cfg` in the projects that should use it.
  See the README section "Adding a project on a specific PHP version".
* Shell scripts follow upstream style: tabs, `#!/bin/sh` where possible, shellcheck-clean
  (`--exclude=SC1091`). `.editorconfig` is authoritative for indentation.
