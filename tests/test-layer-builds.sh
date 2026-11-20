#!/usr/bin/env bash
# Build-gate regressions: supported layers may not be silently skipped.
# Stub only the Docker/Make boundary; no Docker daemon required.
set -euo pipefail

docker() {
    if [ "$*" = 'image inspect local/pgx-pg_net:19' ]; then
        return 1
    fi
    echo "FAIL unexpected Docker command after build failure: $*" >&2
    return 99
}
make() { return 1; }
export -f docker make

output=""
if output="$(PGLAYERS_EXTENSIONS=pg_net bash tests/test-layers.sh local 19 2>&1)"; then
    echo 'FAIL supported extension build failure must fail the suite' >&2
    exit 1
fi
if [[ "$output" != *'FAIL Failed to build pg_net for PG 19'* ]] \
    || [[ "$output" == *'Phase 2:'* ]]; then
    printf 'FAIL build gate did not stop before layer checks:\n%s\n' "$output" >&2
    exit 1
fi
echo 'PASS supported extension build failure stops the layer suite'

if output="$(PGLAYERS_EXTENSIONS=' ' bash tests/test-layers.sh local 19 2>&1)"; then
    echo 'FAIL empty supported extension set must fail the suite' >&2
    exit 1
fi
if [[ "$output" != *'FAIL No supported extensions selected for PG 19'* ]]; then
    printf 'FAIL empty-set gate did not report the failure:\n%s\n' "$output" >&2
    exit 1
fi
echo 'PASS empty supported extension set fails the layer suite'
