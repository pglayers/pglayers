#!/usr/bin/env bash
# Validate the DocumentDB gateway through the MongoDB wire protocol.

set -euo pipefail

CONTAINER="${1:?usage: test-documentdb-gateway.sh <container>}"

fail() {
	printf 'FAIL documentdb_mongo: %s\n' "$1"
	exit 1
}

if ! docker exec "$CONTAINER" psql -U postgres -tAc \
	"SELECT 1 FROM pg_roles WHERE rolname = 'docdb_test'" | grep -qx 1; then
	docker exec "$CONTAINER" psql -U postgres -v ON_ERROR_STOP=1 -c \
		"CREATE ROLE docdb_test WITH LOGIN PASSWORD 'PglayersDocDB42' SUPERUSER;" \
		>/dev/null || fail "could not create gateway test role"
fi
docker exec "$CONTAINER" psql -U postgres -v ON_ERROR_STOP=1 -c \
	"ALTER ROLE docdb_test WITH LOGIN PASSWORD 'PglayersDocDB42' SUPERUSER;" \
	>/dev/null || fail "could not configure gateway test role"

if ! docker exec "$CONTAINER" bash -c \
	"apt-get update -qq && apt-get install -qq -y python3-pymongo >/dev/null 2>&1" \
	>/dev/null 2>&1; then
	fail "could not install pymongo"
fi

for _ in $(seq 1 30); do
	if docker exec "$CONTAINER" bash -c \
		'timeout 1 bash -c "echo > /dev/tcp/localhost/10260" 2>/dev/null'; then
		docker exec -i "$CONTAINER" python3 < extensions/documentdb/test_mongo.py
		exit $?
	fi
	sleep 1
done

fail "gateway port 10260 not ready after 30s"
