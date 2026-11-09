#!/usr/bin/env bash
# Regression checks for defaults that depend on the composed extension set.
set -euo pipefail

for pg in 17 18 19; do
    # A default make variable is not automatically exported to shell recipes.
    # Keep local pre-release tests on the same base tag as builds and CI.
    tag="$(./scripts/pg-tag.sh "$pg")"
    output="$(
        # Do not inherit the parent make invocation's PG_TAG override.
        unset PG_TAG MAKEFLAGS MAKEOVERRIDES MFLAGS
        make --no-print-directory -s -n test PG="$pg" REGISTRY=local
    )"
    if [[ "$output" != *"PG_TAG=\"$tag\""* ]]; then
        echo "FAIL PG $pg: make test must forward its resolved base tag" >&2
        exit 1
    fi
    echo "PASS PG $pg: make test forwards its resolved base tag"

    output="$(./scripts/combined-config.sh "$pg" pg_duckdb pg_show_plans)"
    if ! grep -q 'pg_show_plans.is_enabled = off' <<< "$output"; then
        echo "FAIL PG $pg: mixed DuckDB/pg_show_plans image must disable automatic capture" >&2
        exit 1
    fi
    echo "PASS PG $pg: mixed DuckDB/pg_show_plans default"

    for ext in pg_duckdb pg_show_plans; do
        output="$(./scripts/combined-config.sh "$pg" "$ext")"
        if grep -q 'pg_show_plans.is_enabled' <<< "$output"; then
            echo "FAIL PG $pg: $ext alone must retain upstream capture defaults" >&2
            exit 1
        fi
        echo "PASS PG $pg: $ext standalone defaults unchanged"
    done
done
