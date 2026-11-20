#!/usr/bin/env bash
# Verify CRI reference normalization without Docker or a Kubernetes cluster.
set -euo pipefail

# shellcheck source=tests/k3d-import.sh
source "$(dirname "${BASH_SOURCE[0]}")/k3d-import.sh"

docker() {
    case "$1" in
        version) echo linux/amd64 ;;
        save) ;;
        ps) echo 'test-node server' ;;
        exec)
            if [ "$*" != "exec test-node crictl inspecti $EXPECTED_IMAGE" ]; then
                echo "unexpected CRI reference: $*" >&2
                return 1
            fi
            return "${INSPECT_STATUS:-0}"
            ;;
        *) echo "unexpected Docker command: $*" >&2; return 99 ;;
    esac
}
k3d() { return 0; }

for image in postgres:19 local/pgx-pgvector:19 ghcr.io/vendor/postgres:19 localhost:5000/postgres:19; do
    case "$image" in
        postgres:19) EXPECTED_IMAGE=docker.io/library/postgres:19 ;;
        local/*) EXPECTED_IMAGE="docker.io/$image" ;;
        *) EXPECTED_IMAGE="$image" ;;
    esac
    if ! k3d_import test-cluster "$image"; then
        echo "FAIL CRI reference normalization for $image" >&2
        exit 1
    fi
    echo "PASS CRI reference normalization for $image"
done

EXPECTED_IMAGE=docker.io/library/postgres:19
INSPECT_STATUS=1
if output="$(k3d_import test-cluster postgres:19 2>&1)"; then
    echo 'FAIL missing imported image must fail the gate' >&2
    exit 1
fi
if [[ "$output" != *'is not present in node test-node'* ]]; then
    printf 'FAIL import verification lost its diagnostic:\n%s\n' "$output" >&2
    exit 1
fi
echo 'PASS missing imported image fails the gate'
