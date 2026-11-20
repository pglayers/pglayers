#!/usr/bin/env bash
# Operand selection and version gates without Docker or a Kubernetes cluster.
set -euo pipefail

docker() {
    case "$*" in
        'image inspect local/pgx-pgvector:19'|'image inspect local/pgx-pg_cron:19'|'image inspect local/pgx-postgis:19'|'pull postgres:19') ;;
        'run --rm --entrypoint id postgres:19 -u postgres'|'run --rm --entrypoint id postgres:19 -g postgres') echo 999 ;;
        'run --rm --entrypoint postgres postgres:19 --version') echo "$MOCK_VERSION" ;;
        *) echo "unexpected Docker command: $*" >&2; return 99 ;;
    esac
}
kubectl() { echo 'unexpected kubectl command' >&2; return 99; }
k3d() {
    # The harness cleanup is harmless in these mocked runs.
    if [ "$*" = 'cluster delete pglayers-cnpg-test' ]; then return 0; fi
    echo 'cluster creation is intentionally stubbed' >&2
    return 99
}
export -f docker kubectl k3d
unset PG_TAG CNPG_PG_IMAGE

for version in 18.1 19rc2; do
    export MOCK_VERSION="postgres (PostgreSQL) $version"
    if output="$(bash tests/test-cnpg.sh local 19 2>&1)"; then
        echo "FAIL CNPG accepted an incorrect operand: $version" >&2
        exit 1
    fi
    if [[ "$output" != *'FAIL CNPG operand must run PostgreSQL 19 GA'* ]] \
        || [[ "$output" == *'Creating k3d cluster'* ]]; then
        printf 'FAIL CNPG did not reject the operand before cluster creation:\n%s\n' "$output" >&2
        exit 1
    fi
    echo "PASS CNPG preflight rejects $version before cluster creation"
done

export MOCK_VERSION='postgres (PostgreSQL) 19.0'
if output="$(bash tests/test-cnpg.sh local 19 2>&1)"; then
    echo 'FAIL CNPG fixture must stop at the stubbed cluster creation' >&2
    exit 1
fi
if [[ "$output" != *'PASS CNPG operand runs PostgreSQL 19 GA'* ]] \
    || [[ "$output" != *'Creating k3d cluster'* ]]; then
    printf 'FAIL CNPG GA operand did not pass preflight:\n%s\n' "$output" >&2
    exit 1
fi
echo 'PASS CNPG selects the official PG19 GA operand'
