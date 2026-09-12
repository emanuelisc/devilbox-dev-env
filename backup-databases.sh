#!/bin/sh -eu
#
# Dump every MySQL and PostgreSQL database to ./backups/ as plain SQL.
#
# Why this exists next to the host bind mounts in docker-compose.override.yml:
# a bind mount protects the data directory from being DELETED (docker compose
# down -v, docker volume prune, Docker Desktop reset). It does NOT protect it
# from being CORRUPTED -- a broken InnoDB page is just as broken on the host.
# Only a logical dump gives you something to restore from.
#
# Usage:
#   ./backup-databases.sh              # dump both engines
#   ./backup-databases.sh mysql        # only MySQL
#   ./backup-databases.sh pgsql        # only PostgreSQL
#
# Restore (dumps are gzipped, and a per-database dump carries no CREATE DATABASE,
# so the target database must exist and be named explicitly):
#   gunzip -c backups/mysql/<db>-<date>.sql.gz \
#     | docker exec -i devilbox-mysql-1 mysql -uroot <db>
#   gunzip -c backups/pgsql/<db>-<date>.sql.gz \
#     | docker exec -i devilbox-pgsql-1 psql -U postgres -d <db>
#
# Keeps the newest KEEP dumps per database and deletes older ones.

CWD="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
DATE="$(date +%Y-%m-%d_%H%M)"
KEEP=7
WHICH="${1:-all}"

MYSQL_CONTAINER="devilbox-mysql-1"
PGSQL_CONTAINER="devilbox-pgsql-1"

_running() {
	[ "$(docker inspect -f '{{.State.Running}}' "${1}" 2>/dev/null)" = "true" ]
}

# Keep only the newest ${KEEP} files matching a prefix.
_rotate() {
	_dir="${1}"
	_prefix="${2}"
	# shellcheck disable=SC2012
	ls -1t "${_dir}/${_prefix}"-*.sql.gz 2>/dev/null | tail -n "+$((KEEP + 1))" | while read -r _old; do
		echo "    rotate: rm $(basename "${_old}")"
		rm -f "${_old}"
	done
}

# -------------------------------------------------------------------- MySQL
if [ "${WHICH}" = "all" ] || [ "${WHICH}" = "mysql" ]; then
	if _running "${MYSQL_CONTAINER}"; then
		mkdir -p "${CWD}/backups/mysql"
		echo "MySQL (${MYSQL_CONTAINER}):"
		docker exec "${MYSQL_CONTAINER}" mysql -uroot -N -B -e \
			'SHOW DATABASES' 2>/dev/null \
		| grep -vE '^(information_schema|performance_schema|sys)$' \
		| while read -r db; do
			printf '  %-30s' "${db}"
			docker exec "${MYSQL_CONTAINER}" mysqldump -uroot \
				--single-transaction --quick --routines --triggers --events \
				"${db}" 2>/dev/null \
			| gzip -c > "${CWD}/backups/mysql/${db}-${DATE}.sql.gz"
			du -h "${CWD}/backups/mysql/${db}-${DATE}.sql.gz" | cut -f1
			_rotate "${CWD}/backups/mysql" "${db}"
		done
	else
		echo "MySQL: container ${MYSQL_CONTAINER} not running -- skipped"
	fi
fi

# ----------------------------------------------------------------- Postgres
if [ "${WHICH}" = "all" ] || [ "${WHICH}" = "pgsql" ]; then
	if _running "${PGSQL_CONTAINER}"; then
		mkdir -p "${CWD}/backups/pgsql"
		echo "PostgreSQL (${PGSQL_CONTAINER}):"
		# Roles and other cluster-wide objects are not part of a per-db dump.
		printf '  %-30s' "_globals"
		docker exec "${PGSQL_CONTAINER}" pg_dumpall -U postgres --globals-only 2>/dev/null \
			| gzip -c > "${CWD}/backups/pgsql/_globals-${DATE}.sql.gz"
		du -h "${CWD}/backups/pgsql/_globals-${DATE}.sql.gz" | cut -f1
		_rotate "${CWD}/backups/pgsql" "_globals"

		docker exec "${PGSQL_CONTAINER}" psql -U postgres -tAc \
			'SELECT datname FROM pg_database WHERE datistemplate = false' 2>/dev/null \
		| while read -r db; do
			[ -n "${db}" ] || continue
			printf '  %-30s' "${db}"
			docker exec "${PGSQL_CONTAINER}" pg_dump -U postgres "${db}" 2>/dev/null \
				| gzip -c > "${CWD}/backups/pgsql/${db}-${DATE}.sql.gz"
			du -h "${CWD}/backups/pgsql/${db}-${DATE}.sql.gz" | cut -f1
			_rotate "${CWD}/backups/pgsql" "${db}"
		done
	else
		echo "PostgreSQL: container ${PGSQL_CONTAINER} not running -- skipped"
	fi
fi

echo "Done. Dumps in ${CWD}/backups/"
