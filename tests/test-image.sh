#!/usr/bin/env bash
#
# Run integration tests against a combined pglayers image.
#
# Usage:
#   ./tests/test-image.sh [IMAGE_TAG]
#
# Example:
#   make image PG=17 REGISTRY=local
#   make test-image PG=17
#
# Or directly:
#   ./tests/test-image.sh pglayers:17

set -euo pipefail

IMAGE="${1:-pglayers:17}"
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

# ---------------------------------------------------------------------------
# Startup log health.
#
# A fresh combined image must boot WITHOUT warnings. This is the guard that
# keeps the shipped image from silently regressing to the class of noise this
# suite exists to prevent (documentdb gateway panics, "too many background
# workers", pgnodemx's k8s Downward API warning, ...). It is scanned on the
# MAIN server (post-initdb) and BEFORE the test.sql suite runs, so it sees the
# out-of-the-box boot, not log lines produced by our own CREATE EXTENSION test
# activity.
#
# Benign lines can be excluded via LOG_ALLOWLIST (extended-regex patterns).
# Add entries sparingly, each with a justification comment.
LOG_ALLOWLIST=(
    # (none yet -- the full and azure images boot clean)
)

printf -- "Checking startup log health..."
sleep 8   # let background workers / the documentdb gateway settle
startup_log="$(docker logs "$CONTAINER" 2>&1 \
    | awk '/PostgreSQL init process complete; ready for start up/{p=1} p')"
# If the init anchor is absent (e.g. an already-initialised volume), scan it all.
[ -n "$startup_log" ] || startup_log="$(docker logs "$CONTAINER" 2>&1)"

# Problem signatures: any PostgreSQL WARNING/ERROR/FATAL/PANIC (anchored on the
# "[pid] SEVERITY:" log prefix so it never matches those words inside a message
# body), a Rust background-worker panic, or the (LOG-level) background-worker
# exhaustion message.
problems="$(printf '%s\n' "$startup_log" | grep -E \
    '\] (WARNING|ERROR|FATAL|PANIC):|thread .* panicked|too many background workers|increase .*max_worker_processes' \
    || true)"
if [ "${#LOG_ALLOWLIST[@]}" -gt 0 ]; then
    for pat in "${LOG_ALLOWLIST[@]}"; do
        problems="$(printf '%s\n' "$problems" | grep -vE "$pat" || true)"
    done
fi
problems="$(printf '%s\n' "$problems" | grep -vE '^[[:space:]]*$' || true)"

echo
if [ -z "$problems" ]; then
    pass "startup log clean (no warnings/errors on boot)"
else
    fail "startup log contains warnings/errors on a fresh boot:"
    printf '%s\n' "$problems" | sed 's/^/       /'
fi
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
        # shellcheck disable=SC2001
        # Prepending indent to each line; no bash-native equivalent for multiline
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
