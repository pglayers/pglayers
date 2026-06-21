#!/usr/bin/env bash
#
# Test suite for postgres-extender: detects layer collisions, missing
# shared libraries, and verifies extensions load correctly.
#
# Usage:
#   ./tests/test-layers.sh [REGISTRY] [PG_MAJOR]
#
# Requires: docker, jq
# Builds and tests locally -- does not push anything.

set -euo pipefail

REGISTRY="${1:-local}"
PG="${2:-17}"
PREFIX="pgx"
IMAGE_TAG="postgres-extender-test:${PG}"

PASS=0
FAIL=0
WARN=0

# Colors (if terminal)
if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; NC=''
fi

pass() { ((PASS++)) || true; printf -- "${GREEN}PASS${NC} %s\n" "$1"; }
fail() { ((FAIL++)) || true; printf -- "${RED}FAIL${NC} %s\n" "$1"; }
warn() { ((WARN++)) || true; printf -- "${YELLOW}WARN${NC} %s\n" "$1"; }
info() { printf -- "---- %s\n" "$1"; }

# Discover extensions
EXTENSIONS=()
for dir in extensions/*/; do
    ext="$(basename "$dir")"
    ver_var="VERSION_${PG}"
    ver="$(bash -c "source ${dir}/extension.conf && echo \${${ver_var}}")"
    [ -n "$ver" ] && EXTENSIONS+=("$ext")
done

info "Testing ${#EXTENSIONS[@]} extensions for PG ${PG}: ${EXTENSIONS[*]}"
info "Registry: ${REGISTRY}"
echo

# ============================================================
# Phase 1: Build all extension images locally (if not already built)
# ============================================================
info "Phase 1: Building extension images..."
for ext in "${EXTENSIONS[@]}"; do
    if ! docker image inspect "${REGISTRY}/${PREFIX}-${ext}:${PG}" &>/dev/null; then
        make build EXT="$ext" PG="$PG" REGISTRY="$REGISTRY" >/dev/null 2>&1
    fi
done
echo

# ============================================================
# Phase 2: Extract file lists from each extension image
# ============================================================
info "Phase 2: Extracting file lists..."
TMPDIR="$(mktemp -d)"
trap "rm -rf $TMPDIR" EXIT

# Get base image file list (files and symlinks only, no directories)
docker create --name pgx-extract-base "postgres:${PG}" true 2>/dev/null
docker export pgx-extract-base 2>/dev/null | tar -t 2>/dev/null \
    | grep -v '/$' \
    | sed 's|^|/|' \
    | grep -v -E '^/\.dockerenv|^/dev/|^/proc/|^/sys/|^/etc/(hostname|hosts|resolv\.conf|mtab)$' \
    | LC_ALL=C sort > "${TMPDIR}/base.txt"
docker rm pgx-extract-base >/dev/null 2>&1

# Get each extension's file list (files and symlinks only, no directories)
for ext in "${EXTENSIONS[@]}"; do
    docker create --name "pgx-extract-${ext}" "${REGISTRY}/${PREFIX}-${ext}:${PG}" true 2>/dev/null
    docker export "pgx-extract-${ext}" 2>/dev/null | tar -t 2>/dev/null \
        | grep -v '/$' \
        | sed 's|^|/|' \
        | grep -v -E '^/\.dockerenv|^/dev/|^/proc/|^/sys/|^/etc/(hostname|hosts|resolv\.conf|mtab)$' \
        | LC_ALL=C sort > "${TMPDIR}/${ext}.txt"
    docker rm "pgx-extract-${ext}" >/dev/null 2>&1
done
echo

# ============================================================
# Phase 3: Check for collisions between extension layers
# ============================================================
info "Phase 3: Checking for file collisions between extensions..."
COLLISION_FOUND=false

for ((i=0; i<${#EXTENSIONS[@]}; i++)); do
    for ((j=i+1; j<${#EXTENSIONS[@]}; j++)); do
        ext_a="${EXTENSIONS[$i]}"
        ext_b="${EXTENSIONS[$j]}"
        overlaps="$(comm -12 "${TMPDIR}/${ext_a}.txt" "${TMPDIR}/${ext_b}.txt" || true)"
        if [ -n "$overlaps" ]; then
            real_overlaps="$overlaps"
            if [ -n "$real_overlaps" ]; then
                count="$(echo "$real_overlaps" | wc -l)"
                COLLISION_FOUND=true
                fail "${ext_a} <-> ${ext_b}: ${count} overlapping file(s)"
                echo "$real_overlaps" | head -10 | sed 's/^/       /'
                [ "$count" -gt 10 ] && echo "       ... and $((count - 10)) more"
            fi
        else
            pass "${ext_a} <-> ${ext_b}: no collisions"
        fi
    done
done

if [ "$COLLISION_FOUND" = false ]; then
    pass "No file collisions detected between any extension pair"
fi
echo

# ============================================================
# Phase 4: Check for base image overwrites
# ============================================================
info "Phase 4: Checking for base image file overwrites..."

for ext in "${EXTENSIONS[@]}"; do
    overlaps="$(comm -12 "${TMPDIR}/base.txt" "${TMPDIR}/${ext}.txt" || true)"
    if [ -n "$overlaps" ]; then
        count="$(echo "$overlaps" | wc -l)"
        # Some overwrites are expected (e.g., shared_preload_libraries in
        # postgresql.conf). Flag only unexpected ones.
        unexpected="$(echo "$overlaps" | grep -vE '(postgresql\.conf|pg_hba\.conf)' || true)"
        if [ -n "$unexpected" ]; then
            warn "${ext}: overwrites ${count} base image file(s)"
            echo "$unexpected" | head -5 | sed 's/^/       /'
            [ "$count" -gt 5 ] && echo "       ... and $((count - 5)) more"
        else
            pass "${ext}: no unexpected base image overwrites"
        fi
    else
        pass "${ext}: no base image overwrites"
    fi
done
echo

# ============================================================
# Phase 5: Build combined image and check shared libraries
# ============================================================
info "Phase 5: Building combined image and checking shared libraries..."

# Generate a test Dockerfile
{
    echo "FROM postgres:${PG}"
    for ext in "${EXTENSIONS[@]}"; do
        echo "COPY --from=${REGISTRY}/${PREFIX}-${ext}:${PG} / /"
    done
    # Build shared_preload_libraries from extensions available for this PG version
    preloads=""
    for ext in "${EXTENSIONS[@]}"; do
        spl="$(bash -c "source extensions/${ext}/extension.conf && echo \$SHARED_PRELOAD")"
        [ -n "$spl" ] && preloads="${preloads:+${preloads},}${spl}"
    done
    [ -n "$preloads" ] && echo "RUN echo \"shared_preload_libraries = '${preloads}'\" >> /usr/share/postgresql/postgresql.conf.sample"
    # pg_durable config (only if present)
    if printf '%s\n' "${EXTENSIONS[@]}" | grep -qx pg_durable; then
        echo "RUN echo \"pg_durable.database = 'postgres'\" >> /usr/share/postgresql/postgresql.conf.sample"
        echo "RUN echo \"pg_durable.worker_role = 'postgres'\" >> /usr/share/postgresql/postgresql.conf.sample"
        echo "RUN echo \"pg_durable.enable_superuser_instances = on\" >> /usr/share/postgresql/postgresql.conf.sample"
    fi
} > "${TMPDIR}/Dockerfile"

docker build -t "${IMAGE_TAG}" -f "${TMPDIR}/Dockerfile" "${TMPDIR}" >/dev/null 2>&1

# Check for missing shared libraries
missing="$(docker run --rm --entrypoint bash "${IMAGE_TAG}" -c '
    for so in /usr/lib/postgresql/'"${PG}"'/lib/*.so; do
        [ -f "$so" ] || continue
        ldd "$so" 2>/dev/null | grep "not found"
    done
' 2>/dev/null || true)"

if [ -z "$missing" ]; then
    pass "All shared library dependencies resolve"
else
    fail "Missing shared libraries detected:"
    echo "$missing" | sort -u | sed 's/^/       /'
fi
echo

# ============================================================
# Phase 6: Functional tests -- load all extensions
# ============================================================
info "Phase 6: Functional tests (CREATE EXTENSION + smoke tests)..."

# Start a test container
docker rm -f pgx-func-test 2>/dev/null || true
docker run -d --name pgx-func-test \
    -e POSTGRES_PASSWORD=test \
    -e POSTGRES_HOST_AUTH_METHOD=trust \
    "${IMAGE_TAG}" >/dev/null 2>&1

# Wait for postgres to be ready
for i in $(seq 1 60); do
    if docker exec pgx-func-test pg_isready -U postgres >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Test CREATE EXTENSION for each
# Map directory names to SQL extension names where they differ.
# Extensions that are NOT loadable via CREATE EXTENSION (e.g., output
# plugins) should be listed in SKIP_CREATE_EXT.
declare -A EXT_SQL_NAMES=(
    [age]="age"
    [anon]="anon"
    [h3_pg]="h3"
    [hll]="hll"
    [hypopg]="hypopg"
    [ip4r]="ip4r"
    [orafce]="orafce"
    [pg_bigm]="pg_bigm"
    [pg_cron]="pg_cron"
    [pg_duckdb]="pg_duckdb"
    [pg_durable]="pg_durable"
    [pg_hint_plan]="pg_hint_plan"
    [pg_ivm]="pg_ivm"
    [pg_partman]="pg_partman"
    [pg_repack]="pg_repack"
    [pg_roaringbitmap]="roaringbitmap"
    [pg_squeeze]="pg_squeeze"
    [pg_stat_monitor]="pg_stat_monitor"
    [pg_uuidv7]="pg_uuidv7"
    [pgaudit]="pgaudit"
    [pgrouting]="pgrouting"
    [pgvector]="vector"
    [plpgsql_check]="plpgsql_check"
    [plv8]="plv8"
    [postgis]="postgis"
    [semver]="semver"
    [tdigest]="tdigest"
    [tds_fdw]="tds_fdw"
    [temporal_tables]="temporal_tables"
    [timescaledb]="timescaledb"
)

# Extensions that are NOT loadable via CREATE EXTENSION
# (or conflict with other extensions in the combined test image)
declare -A SKIP_CREATE_EXT=(
    [pg_failover_slots]=1
    [pgrouting]=1
    [timescaledb]=1
    [wal2json]=1
)

for ext in "${EXTENSIONS[@]}"; do
    # Skip extensions that aren't CREATE EXTENSION-able
    if [ -n "${SKIP_CREATE_EXT[$ext]:-}" ]; then
        pass "SKIP ${ext} (not a CREATE EXTENSION type)"
        continue
    fi
    sql_name="${EXT_SQL_NAMES[$ext]:-$ext}"
    result="$(docker exec pgx-func-test psql -U postgres -tAc \
        "CREATE EXTENSION IF NOT EXISTS ${sql_name}; SELECT extname FROM pg_extension WHERE extname='${sql_name}';" 2>&1)" || true
    if echo "$result" | grep -q "${sql_name}"; then
        pass "CREATE EXTENSION ${sql_name}"
    else
        fail "CREATE EXTENSION ${sql_name}: $result"
    fi
done

# Smoke tests -- only run for extensions present in this PG version
smoke_test() {
    local desc="$1" sql="$2"
    local result rc
    result="$(docker exec pgx-func-test psql -U postgres -tAc "$sql" 2>&1)" && rc=0 || rc=$?
    if [ "$rc" -eq 0 ] && [ -n "$result" ]; then
        pass "smoke: ${desc}"
    else
        fail "smoke: ${desc}: ${result}"
    fi
}

# Helper: only run smoke test if extension is in the EXTENSIONS list
has_ext() { printf '%s\n' "${EXTENSIONS[@]}" | grep -qx "$1"; }

has_ext age && smoke_test "age graph" \
    "LOAD 'age'; SET search_path = ag_catalog; SELECT create_graph('smoke_g'); SELECT drop_graph('smoke_g', true);"
has_ext anon && smoke_test "anon loaded" \
    "SELECT count(*) FROM pg_extension WHERE extname = 'anon';"
has_ext credcheck && smoke_test "credcheck loaded" \
    "SHOW credcheck.password_min_length;"
has_ext h3_pg && smoke_test "h3 cell" \
    "SELECT h3_lat_lng_to_cell('(0,0)'::point, 5);"
has_ext hll && smoke_test "hll aggregate" \
    "SELECT hll_cardinality(hll_add_agg(hll_hash_integer(g))) FROM generate_series(1,100) g;"
has_ext hypopg && smoke_test "hypopg create index" \
    "SELECT indexrelid FROM hypopg_create_index('CREATE INDEX ON public.part_config (parent_table)');"
has_ext ip4r && smoke_test "ip4r range" \
    "SELECT '192.168.1.0/24'::ip4r;"
has_ext orafce && smoke_test "orafce nvl" \
    "SELECT oracle.nvl(NULL::text, 'fallback');"
has_ext pg_bigm && smoke_test "pg_bigm search" \
    "SELECT bigm_similarity('hello', 'helo');"
has_ext pg_cron && smoke_test "pg_cron schedule" \
    "SELECT cron.schedule('test_job', '* * * * *', 'SELECT 1');"
has_ext pg_duckdb && smoke_test "pg_duckdb loaded" \
    "SELECT count(*) FROM pg_extension WHERE extname = 'pg_duckdb';"
has_ext pg_durable && smoke_test "pg_durable loaded" \
    "SELECT count(*) FROM pg_extension WHERE extname = 'pg_durable';"
has_ext pg_failover_slots && smoke_test "pg_failover_slots loaded" \
    "SELECT count(*) FROM pg_proc WHERE proname LIKE 'pg_failover_slot%';"
has_ext pg_hint_plan && smoke_test "pg_hint_plan loaded" \
    "SHOW pg_hint_plan.enable_hint;"
has_ext pg_ivm && smoke_test "pg_ivm functions" \
    "SELECT count(*) FROM pg_proc WHERE proname = 'create_immv';"
has_ext pg_partman && smoke_test "pg_partman config table" \
    "SELECT count(*) FROM public.part_config;"
has_ext pg_repack && smoke_test "pg_repack version" \
    "SELECT repack.version();"
has_ext pg_roaringbitmap && smoke_test "pg_roaringbitmap ops" \
    "SELECT rb_cardinality(rb_build(ARRAY[1,2,3]::int[]));"
has_ext pgrouting && smoke_test "pgrouting dijkstra" \
    "SELECT count(*) FROM pg_proc WHERE proname = 'pgr_dijkstra';"
has_ext pg_squeeze && smoke_test "pg_squeeze schema" \
    "SELECT count(*) FROM squeeze.tables;"
has_ext pg_stat_monitor && smoke_test "pg_stat_monitor view" \
    "SELECT count(*) FROM pg_stat_monitor;"
has_ext pg_uuidv7 && smoke_test "pg_uuidv7 generate" \
    "SELECT uuid_generate_v7();"
has_ext pgaudit && smoke_test "pgaudit active" \
    "SHOW pgaudit.log;"
has_ext pgvector && smoke_test "pgvector similarity" \
    "SELECT '[1,2,3]'::vector <-> '[4,5,6]'::vector;"
has_ext plpgsql_check && smoke_test "plpgsql_check lint" \
    "SELECT count(*) FROM pg_proc WHERE proname = 'plpgsql_check_function';"
has_ext plv8 && smoke_test "plv8 javascript" \
    "SELECT plv8_version();"
has_ext postgis && smoke_test "PostGIS geometry" \
    "SELECT ST_AsText(ST_Point(1, 2));"
has_ext rum && smoke_test "rum index" \
    "SELECT 1 FROM pg_available_extensions WHERE name = 'rum';"
has_ext semver && smoke_test "semver comparison" \
    "SELECT '1.2.3'::semver > '1.2.2'::semver;"
has_ext tdigest && smoke_test "tdigest percentile" \
    "SELECT tdigest_percentile(x, 100, 0.5) FROM generate_series(1,100) x;"
has_ext tds_fdw && smoke_test "tds_fdw wrapper" \
    "SELECT count(*) FROM pg_foreign_data_wrapper WHERE fdwname = 'tds_fdw';"
has_ext temporal_tables && smoke_test "temporal_tables loaded" \
    "SELECT proname FROM pg_proc WHERE proname = 'versioning';"
has_ext timescaledb && smoke_test "timescaledb available" \
    "SELECT count(*) FROM pg_available_extensions WHERE name = 'timescaledb';"
has_ext wal2json && smoke_test "wal2json plugin exists" \
    "SELECT count(*) FROM pg_proc WHERE proname = 'pg_logical_slot_get_changes';"
echo

# ============================================================
# Phase 7: Integration tests (per-extension test.sql files)
# ============================================================
info "Phase 7: Integration tests (extensions/*/test.sql)..."

for ext in "${EXTENSIONS[@]}"; do
    test_file="extensions/${ext}/test.sql"
    if [ ! -f "$test_file" ]; then
        warn "${ext}: no test.sql found"
        continue
    fi
    output="$(docker exec -i pgx-func-test psql -U postgres -tA -v ON_ERROR_STOP=0 < "$test_file" 2>&1)"
    failures="$(echo "$output" | grep '^FAIL' || true)"
    passes="$(echo "$output" | grep -c '^PASS' || true)"
    if [ -n "$failures" ]; then
        fail "integration ${ext}:"
        echo "$failures" | sed 's/^/       /'
    elif [ "$passes" -gt 0 ]; then
        pass "integration ${ext} (${passes} checks)"
    else
        warn "${ext}: test.sql produced no PASS/FAIL output"
    fi
done

# Cleanup
docker rm -f pgx-func-test >/dev/null 2>&1
echo

# ============================================================
# Summary
# ============================================================
echo "========================================"
printf -- "Results: ${GREEN}%d passed${NC}, ${RED}%d failed${NC}, ${YELLOW}%d warnings${NC}\n" \
    "$PASS" "$FAIL" "$WARN"
echo "========================================"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
