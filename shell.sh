#!/bin/sh

# Enter a PHP container. Defaults to the `php` service (the one driven by
# .env:PHP_SERVER); pass a service name to reach one of the pinned containers:
#
#   ./shell.sh          -> php    (default backend, .env:PHP_SERVER)
#   ./shell.sh php71    -> the pinned 7.1 container
#   ./shell.sh php84    -> the locally built 8.4 container
#
# The service name must exist in docker-compose.yml or docker-compose.override.yml.
#
SERVICE="${1:-php}"

if hash docker-compose 2>/dev/null; then
	docker-compose exec --user devilbox "${SERVICE}" bash -l
else
	docker compose exec --user devilbox "${SERVICE}" bash -l
fi
