#!/usr/bin/env bash
#
# Run integration tests against a combined postgres-extender image.
#
# Usage:
#   ./tests/test-image.sh [IMAGE_TAG]
#
# Example:
#   make image PG=17 REGISTRY=local
#   make test-image PG=17
#
# Or directly:
#   ./tests/test-image.sh postgres-extender:17

set -euo pipefail

IMAGE="${1:-postgres-extender:17}"
CONTAINER="pgx-test-image-$$"

PASS=0
FAIL=0

# Colors
if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
else
    RED=''; GREEN=''; NC=''
fi

pass() { ((PASS++)) || true; printf -- "${GREEN}PASS${NC} %s\n" "$1"; }
fail() { ((FAIL++)) || true; printf -- "${RED}FAIL${NC} %s\n" "$1"; }

cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "Testing image: ${IMAGE}"
echo

# Start the container
docker run -d --name "$CONTAINER" \
    -e POSTGRES_PASSWORD=test \
    -e POSTGRES_HOST_AUTH_METHOD=trust \
    "$IMAGE" >/dev/null 2>&1

# Wait for PostgreSQL to be ready
printf -- "Waiting for PostgreSQL..."
for i in $(seq 1 60); do
    if docker exec "$CONTAINER" pg_isready -U postgres >/dev/null 2>&1; then
        echo " ready."
        break
    fi
    sleep 1
    [ "$i" -eq 60 ] && { echo " TIMEOUT"; exit 1; }
done
echo

# Run each extension's test.sql
for test_file in extensions/*/test.sql; do
    ext="$(basename "$(dirname "$test_file")")"

    # Skip if extension is not installed in this image
    installed="$(docker exec "$CONTAINER" psql -U postgres -tAc \
        "SELECT count(*) FROM pg_available_extensions WHERE name LIKE '${ext//_/%}'" 2>/dev/null || echo "0")"
    [ "$installed" = "0" ] && continue

    output="$(docker exec -i "$CONTAINER" psql -U postgres -tA -v ON_ERROR_STOP=0 < "$test_file" 2>&1)"
    failures="$(echo "$output" | grep '^FAIL' || true)"
    passes="$(echo "$output" | grep -c '^PASS' || true)"

    if [ -n "$failures" ]; then
        fail "${ext}:"
        echo "$failures" | sed 's/^/       /'
    elif [ "$passes" -gt 0 ]; then
        pass "${ext} (${passes} checks)"
    fi
done

echo
echo "========================================"
printf -- "Results: ${GREEN}%d passed${NC}, ${RED}%d failed${NC}\n" "$PASS" "$FAIL"
echo "========================================"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
