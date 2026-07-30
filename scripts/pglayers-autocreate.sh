#!/bin/bash
# pglayers extension auto-creation (runs once, during first DB init).
#
# The combined image preloads many extensions via shared_preload_libraries.
# A few of them (notably documentdb) ship background workers / a wire-protocol
# gateway that continuously poll for the extension's SQL objects; until the
# extension is actually created they emit perpetual warnings. This script
# creates those extensions once, so a fresh container starts clean.
#
# Controls:
#   PGLAYERS_CREATE_EXTENSIONS  Runtime override. Space/comma-separated list of
#                               SQL extension names, or "none" to disable.
#                               Defaults to the image's baked-in list.
#   PGLAYERS_AUTOCREATE_DEFAULT Baked into the image at build time (make image).
#
# CREATE EXTENSION ... CASCADE pulls in each extension's required dependencies
# automatically (e.g. documentdb -> documentdb_core, pg_cron, vector, postgis).
set -euo pipefail

exts="${PGLAYERS_CREATE_EXTENSIONS:-${PGLAYERS_AUTOCREATE_DEFAULT:-}}"

# Normalise commas to spaces.
exts="${exts//,/ }"

case "$exts" in
	""|"none"|"None"|"NONE")
		exit 0
		;;
esac

db="${POSTGRES_DB:-${POSTGRES_USER:-postgres}}"
user="${POSTGRES_USER:-postgres}"

for ext in $exts; do
	echo "pglayers: creating extension '${ext}' (CASCADE) in database '${db}'"
	if ! psql -v ON_ERROR_STOP=1 --username "$user" --dbname "$db" \
		-c "CREATE EXTENSION IF NOT EXISTS \"${ext}\" CASCADE;"; then
		echo "pglayers: WARNING: failed to create extension '${ext}'; skipping" >&2
	fi
done
