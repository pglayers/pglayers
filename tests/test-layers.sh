#!/usr/bin/env bash
#
# Test suite for pglayers: detects layer collisions, missing
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
IMAGE_TAG="pglayers-test:${PG}"
PG_TAG="${PG_TAG:-$PG}"

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
if [ -n "${PGLAYERS_EXTENSIONS:-}" ]; then
    # Profile mode: use pre-filtered list from Makefile/environment
    for ext in $PGLAYERS_EXTENSIONS; do
        ver_var="VERSION_${PG}"
        ver="$(bash -c "source extensions/${ext}/extension.conf && echo \${${ver_var}}")"
        [ -n "$ver" ] && EXTENSIONS+=("$ext")
    done
else
    # Default: discover from filesystem
    for dir in extensions/*/; do
        ext="$(basename "$dir")"
        ver_var="VERSION_${PG}"
        ver="$(bash -c "source ${dir}/extension.conf && echo \${${ver_var}}")"
        [ -n "$ver" ] && EXTENSIONS+=("$ext")
    done
fi

info "Testing ${#EXTENSIONS[@]} extensions for PG ${PG}: ${EXTENSIONS[*]}"
info "Registry: ${REGISTRY}"
echo

# ============================================================
# Phase 1: Build all extension images locally (if not already built)
# ============================================================
info "Phase 1: Building extension images..."
BUILT_EXTENSIONS=()
for ext in "${EXTENSIONS[@]}"; do
    if docker image inspect "${REGISTRY}/${PREFIX}-${ext}:${PG}" &>/dev/null; then
        BUILT_EXTENSIONS+=("$ext")
    elif make build EXT="$ext" PG="$PG" REGISTRY="$REGISTRY" >/dev/null 2>&1; then
        BUILT_EXTENSIONS+=("$ext")
    else
        warn "Failed to build ${ext} for PG ${PG} (skipping)"
    fi
done

if [ "${#BUILT_EXTENSIONS[@]}" -lt "${#EXTENSIONS[@]}" ]; then
    skipped=$((${#EXTENSIONS[@]} - ${#BUILT_EXTENSIONS[@]}))
    info "Built ${#BUILT_EXTENSIONS[@]}/${#EXTENSIONS[@]} extensions (${skipped} skipped)"
fi
EXTENSIONS=("${BUILT_EXTENSIONS[@]}")
echo

# ============================================================
# Phase 2: Extract file lists from each extension image
# ============================================================
info "Phase 2: Extracting file lists..."
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Get base image file list (files and symlinks only, no directories)
docker create --name pgx-extract-base "postgres:${PG_TAG}" true 2>/dev/null
docker export pgx-extract-base 2>/dev/null | tar -t 2>/dev/null \
    | grep -v '/$' \
    | sed 's|^|/|' \
    | grep -v -E '^/\.dockerenv|^/dev/|^/proc/|^/sys/|^/etc/(hostname|hosts|resolv\.conf|mtab)$' \
    | LC_ALL=C sort > "${TMPDIR}/base.txt"
docker rm pgx-extract-base >/dev/null 2>&1

# Get each extension's file list (files and symlinks only, no directories)
# Also save the tar export for content-level collision checks in Phase 3.
for ext in "${EXTENSIONS[@]}"; do
    docker create --name "pgx-extract-${ext}" "${REGISTRY}/${PREFIX}-${ext}:${PG}" true 2>/dev/null
    docker export "pgx-extract-${ext}" 2>/dev/null > "${TMPDIR}/${ext}.tar"
    tar -tf "${TMPDIR}/${ext}.tar" 2>/dev/null \
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
if [ "$PG" -ge 18 ] 2>/dev/null; then
    info "Phase 3: SKIPPED (isolated layout eliminates collisions by design)"
    pass "Isolated layout (PG ${PG}): file collisions structurally impossible"
    echo
else
info "Phase 3: Checking for file collisions between extensions..."
COLLISION_FOUND=false

# Helper: get sha256 of a file from an extension's exported tar
file_hash() {
    local ext="$1" filepath="$2"
    # tar paths don't have a leading slash
    tar -xOf "${TMPDIR}/${ext}.tar" "${filepath#/}" 2>/dev/null | sha256sum | awk '{print $1}'
}

for ((i=0; i<${#EXTENSIONS[@]}; i++)); do
    for ((j=i+1; j<${#EXTENSIONS[@]}; j++)); do
        ext_a="${EXTENSIONS[$i]}"
        ext_b="${EXTENSIONS[$j]}"
        overlaps="$(comm -12 "${TMPDIR}/${ext_a}.txt" "${TMPDIR}/${ext_b}.txt" || true)"
        if [ -n "$overlaps" ]; then
            # Check if overlapping files have different content
            real_conflicts=""
            while IFS= read -r filepath; do
                hash_a="$(file_hash "$ext_a" "$filepath")"
                hash_b="$(file_hash "$ext_b" "$filepath")"
                if [ "$hash_a" != "$hash_b" ]; then
                    real_conflicts="${real_conflicts:+${real_conflicts}
}${filepath}"
                fi
            done <<< "$overlaps"
            if [ -n "$real_conflicts" ]; then
                count="$(echo "$real_conflicts" | wc -l)"
                COLLISION_FOUND=true
                fail "${ext_a} <-> ${ext_b}: ${count} conflicting file(s)"
                echo "$real_conflicts" | head -10 | sed 's/^/       /'
                [ "$count" -gt 10 ] && echo "       ... and $((count - 10)) more"
            else
                overlap_count="$(echo "$overlaps" | wc -l)"
                pass "${ext_a} <-> ${ext_b}: ${overlap_count} shared file(s), identical content"
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
fi  # end PG < 18 collision check

# ============================================================
# Phase 4: Check for base image overwrites
# ============================================================
if [ "$PG" -ge 18 ] 2>/dev/null; then
    info "Phase 4: SKIPPED (isolated layout cannot overwrite base image files)"
    pass "Isolated layout (PG ${PG}): no base image overwrites possible"
    echo
else
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
fi  # end PG < 18 base overwrite check

# ============================================================
# Phase 5: Build combined image and check shared libraries
# ============================================================
info "Phase 5: Building combined image and checking shared libraries..."

# Generate a test Dockerfile
{
    echo "FROM postgres:${PG_TAG}"
    if [ "$PG" -ge 18 ] 2>/dev/null; then
        # Isolated layout: each extension in its own /extensions/<ext>/ namespace
        for ext in "${EXTENSIONS[@]}"; do
            echo "COPY --from=${REGISTRY}/${PREFIX}-${ext}:${PG} / /extensions/${ext}/"
        done
        # Configure extension_control_path and dynamic_library_path
        ext_paths=""
        lib_paths=""
        for ext in "${EXTENSIONS[@]}"; do
            ext_paths="${ext_paths}/extensions/${ext}/share:"
            lib_paths="${lib_paths}/extensions/${ext}/lib:"
        done
        echo "RUN echo \"extension_control_path = '${ext_paths}\\\$system'\" >> /usr/share/postgresql/postgresql.conf.sample"
        echo "RUN echo \"dynamic_library_path = '${lib_paths}\\\$libdir'\" >> /usr/share/postgresql/postgresql.conf.sample"
        # Configure linker for bundled runtime deps
        # shellcheck disable=SC2016
        echo 'RUN for d in /extensions/*/lib; do echo "$d"; done > /etc/ld.so.conf.d/pglayers.conf && ldconfig'
        echo "ENV LD_LIBRARY_PATH=\"${lib_paths%:}\""
    else
        # Classic layout: flat overlay
        for ext in "${EXTENSIONS[@]}"; do
            echo "COPY --from=${REGISTRY}/${PREFIX}-${ext}:${PG} / /"
        done
    fi
    # Build shared_preload_libraries from extensions available for this PG version
    preloads=""
    for ext in "${EXTENSIONS[@]}"; do
        spl="$(bash -c "source extensions/${ext}/extension.conf && echo \$SHARED_PRELOAD")"
        [ -n "$spl" ] && preloads="${preloads:+${preloads},}${spl}"
    done
    [ -n "$preloads" ] && echo "RUN echo \"shared_preload_libraries = '${preloads}'\" >> /usr/share/postgresql/postgresql.conf.sample"
    # pgtt requires session_preload_libraries (not shared_preload)
    if printf '%s\n' "${EXTENSIONS[@]}" | grep -qx pgtt; then
        echo "RUN echo \"session_preload_libraries = 'pgtt'\" >> /usr/share/postgresql/postgresql.conf.sample"
    fi
    # Many extensions register background workers; increase the limit
    echo "RUN echo \"max_worker_processes = 64\" >> /usr/share/postgresql/postgresql.conf.sample"
    # Append PG_CONF lines from each extension's extension.conf
    for ext in "${EXTENSIONS[@]}"; do
        pgconf="$(bash -c "source extensions/${ext}/extension.conf && echo \${PG_CONF:-}")"
        [ -z "$pgconf" ] && continue
        echo "$pgconf" | tr '|' '\n' | while IFS= read -r line; do
            [ -z "$line" ] && continue
            echo "RUN echo \"${line}\" >> /usr/share/postgresql/postgresql.conf.sample"
        done
    done
    # documentdb gateway config file (already bundled in layer, but needed for test image)
    if printf '%s\n' "${EXTENSIONS[@]}" | grep -qx documentdb; then
        if [ "$PG" -ge 18 ] 2>/dev/null; then
            # In isolated layout, the config is at /extensions/documentdb/etc/documentdb/
            # Create a symlink at the expected system path
            echo "RUN mkdir -p /etc/documentdb && ln -sf /extensions/documentdb/etc/documentdb/gateway_config.json /etc/documentdb/gateway_config.json"
        else
            # shellcheck disable=SC2028
            # The \n is for the Dockerfile's printf, not bash's echo
            echo "RUN printf '%s\n' '{\"NodeHostName\":\"localhost\",\"PostgresPort\":5432,\"PostgresDataUser\":\"postgres\",\"GatewayListenPort\":10260,\"CertificateOptions\":{\"CertType\":\"PemAutoGenerated\"},\"TlsMode\":\"allowTLS\"}' > /etc/documentdb/gateway_config.json"
        fi
    fi
} > "${TMPDIR}/Dockerfile"

docker build -t "${IMAGE_TAG}" -f "${TMPDIR}/Dockerfile" "${TMPDIR}" >/dev/null 2>&1

# Check for missing shared libraries
if [ "$PG" -ge 18 ] 2>/dev/null; then
    missing="$(docker run --rm --entrypoint bash "${IMAGE_TAG}" -c '
        for so in /extensions/*/lib/*.so; do
            [ -f "$so" ] || continue
            ldd "$so" 2>/dev/null | grep "not found"
        done
    ' 2>/dev/null || true)"
else
    missing="$(docker run --rm --entrypoint bash "${IMAGE_TAG}" -c '
        for so in /usr/lib/postgresql/'"${PG}"'/lib/*.so; do
            [ -f "$so" ] || continue
            ldd "$so" 2>/dev/null | grep "not found"
        done
    ' 2>/dev/null || true)"
fi

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
info "Disk usage before starting test container:"
df -h / 2>/dev/null | tail -1 | sed 's/^/       /'

# Start a test container
docker rm -f pgx-func-test 2>/dev/null || true
docker run -d --name pgx-func-test \
    -e POSTGRES_PASSWORD=test \
    -e POSTGRES_HOST_AUTH_METHOD=trust \
    "${IMAGE_TAG}" >/dev/null 2>&1

# Wait for postgres to be ready (use TCP -- only available after final restart,
# not during the init phase which listens on Unix socket only)
pg_ready=false
for i in $(seq 1 90); do
    if docker exec pgx-func-test pg_isready -U postgres -h 127.0.0.1 >/dev/null 2>&1; then
        pg_ready=true
        break
    fi
    # Early exit if the container stopped (crash during startup)
    if ! docker inspect --format='{{.State.Running}}' pgx-func-test 2>/dev/null | grep -q true; then
        break
    fi
    sleep 1
done

if [ "$pg_ready" = false ]; then
    fail "PostgreSQL failed to start within 90s"
    echo "       Container logs (last 40 lines):"
    docker logs pgx-func-test 2>&1 | tail -40 | sed 's/^/       /'
    docker rm -f pgx-func-test >/dev/null 2>&1
    echo
    echo "========================================"
    printf -- "Results: ${GREEN}%d passed${NC}, ${RED}%d failed${NC}, ${YELLOW}%d warnings${NC}\n" \
        "$PASS" "$FAIL" "$WARN"
    echo "========================================"
    exit 1
fi

# Test CREATE EXTENSION for each
# Map directory names to SQL extension names where they differ.
# Extensions that are NOT loadable via CREATE EXTENSION (e.g., output
# plugins) should be listed in SKIP_CREATE_EXT.
declare -A EXT_SQL_NAMES=(
    [age]="age"
    [anon]="anon"
    [documentdb]="documentdb_core"
    [h3_pg]="h3"
    [hll]="hll"
    [http]="http"
    [hypopg]="hypopg"
    [ip4r]="ip4r"
    [orafce]="orafce"
    [pg_bigm]="pg_bigm"
    [pg_cron]="pg_cron"
    [pg_duckdb]="pg_duckdb"
    [pg_durable]="pg_durable"
    [pg_graphql]="pg_graphql"
    [pg_hashids]="pg_hashids"
    [pg_hint_plan]="pg_hint_plan"
    [pg_ivm]="pg_ivm"
    [pg_jsonschema]="pg_jsonschema"
    [pg_lake]="pg_lake"
    [pg_net]="pg_net"
    [pg_partman]="pg_partman"
    [pg_qualstats]="pg_qualstats"
    [pg_repack]="pg_repack"
    [pg_roaringbitmap]="roaringbitmap"
    [pg_similarity]="pg_similarity"
    [pg_squeeze]="pg_squeeze"
    [pg_stat_monitor]="pg_stat_monitor"
    [pg_textsearch]="pg_textsearch"
    [pg_uuidv7]="pg_uuidv7"
    [pg_wait_sampling]="pg_wait_sampling"
    [pgaudit]="pgaudit"
    [pgjwt]="pgjwt"
    [pglogical]="pglogical"
    [pgrouting]="pgrouting"
    [pgsodium]="pgsodium"
    [pgtap]="pgtap"
    [pgtt]="pgtt"
    [pgvector]="vector"
    [pgvectorscale]="vectorscale"
    [plpgsql_check]="plpgsql_check"
    [plprofiler]="plprofiler"
    [plv8]="plv8"
    [postgis]="postgis"
    [postgres_protobuf]="postgres_protobuf"
    [prefix]="prefix"
    [rum]="rum"
    [semver]="semver"
    [tdigest]="tdigest"
    [tds_fdw]="tds_fdw"
    [temporal_tables]="temporal_tables"
    [timescaledb]="timescaledb"
    [wal2json]="wal2json"
    [wrappers]="wrappers"
)

# Extensions that are NOT loadable via CREATE EXTENSION
# (or conflict with other extensions in the combined test image)
declare -A SKIP_CREATE_EXT=(
    [pg_failover_slots]=1
    [pgrouting]=1
    [timescaledb]=1
    [wal2json]=1
)

# Wait for postgres to recover from any crash (background worker crashes
# can put the server into recovery mode temporarily).
wait_for_ready() {
    local i
    for i in $(seq 1 60); do
        if docker exec pgx-func-test pg_isready -U postgres -h 127.0.0.1 >/dev/null 2>&1; then
            # Double-check: ensure we can actually run a query (pg_isready
            # can return OK before the server finishes crash recovery)
            if docker exec pgx-func-test psql -U postgres -tAc "SELECT 1;" >/dev/null 2>&1; then
                return 0
            fi
        fi
        sleep 1
    done
    return 1
}

for ext in "${EXTENSIONS[@]}"; do
    # Skip extensions that aren't CREATE EXTENSION-able
    if [ -n "${SKIP_CREATE_EXT[$ext]:-}" ]; then
        pass "SKIP ${ext} (not a CREATE EXTENSION type)"
        continue
    fi
    sql_name="${EXT_SQL_NAMES[$ext]:-$ext}"
    # Handle extension dependencies (read from extension.conf DEPENDS field)
    deps="$(bash -c "source extensions/${ext}/extension.conf && echo \${DEPENDS:-}")"
    if [ -n "$deps" ]; then
        # DEPENDS is a comma-separated list of SQL extension names
        IFS=',' read -ra dep_arr <<< "$deps"
        for dep in "${dep_arr[@]}"; do
            docker exec pgx-func-test psql -U postgres -c "CREATE EXTENSION IF NOT EXISTS ${dep};" >/dev/null 2>&1 || true
        done
    fi
    result="$(docker exec pgx-func-test psql -U postgres -tAc \
        "CREATE EXTENSION IF NOT EXISTS ${sql_name}; SELECT extname FROM pg_extension WHERE extname='${sql_name}';" 2>&1)" || true
    # Retry up to 3 times if the server was in recovery mode from a prior crash
    retries=0
    while [ "$retries" -lt 3 ] && echo "$result" | grep -qE "recovery mode|not yet accepting|crash of another|server closed the connection"; do
        wait_for_ready
        result="$(docker exec pgx-func-test psql -U postgres -tAc \
            "CREATE EXTENSION IF NOT EXISTS ${sql_name}; SELECT extname FROM pg_extension WHERE extname='${sql_name}';" 2>&1)" || true
        ((retries++)) || true
    done
    if echo "$result" | grep -q "${sql_name}"; then
        pass "CREATE EXTENSION ${sql_name}"
    else
        fail "CREATE EXTENSION ${sql_name}: $result"
    fi
done

# Smoke tests -- only run for extensions present in this PG version

smoke_test() {
    local desc="$1" sql="$2"
    local result rc retries=0
    result="$(docker exec pgx-func-test psql -U postgres -tAc "$sql" 2>&1)" && rc=0 || rc=$?
    # Retry up to 3 times if the server was in recovery mode
    while [ "$rc" -ne 0 ] && [ "$retries" -lt 3 ] && echo "$result" | grep -qE "recovery mode|not yet accepting|crash of another|server closed the connection"; do
        wait_for_ready
        result="$(docker exec pgx-func-test psql -U postgres -tAc "$sql" 2>&1)" && rc=0 || rc=$?
        ((retries++)) || true
    done
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
has_ext documentdb && smoke_test "documentdb BSON type" \
    "SELECT '{\"hello\": \"world\"}'::documentdb_core.bson;"
has_ext h3_pg && smoke_test "h3 cell" \
    "SELECT h3_lat_lng_to_cell('(0,0)'::point, 5);"
has_ext hll && smoke_test "hll aggregate" \
    "SELECT hll_cardinality(hll_add_agg(hll_hash_integer(g))) FROM generate_series(1,100) g;"
has_ext http && smoke_test "http functions" \
    "SELECT count(*) FROM pg_proc WHERE proname = 'http_get';"
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
has_ext pg_graphql && smoke_test "pg_graphql schema" \
    "SELECT count(*) FROM pg_namespace WHERE nspname = 'graphql';"
has_ext pg_hashids && smoke_test "pg_hashids encode" \
    "SELECT id_encode(123);"
has_ext pg_failover_slots && smoke_test "pg_failover_slots loaded" \
    "SELECT count(*) FROM pg_proc WHERE proname LIKE 'pg_failover_slot%';"
has_ext pg_hint_plan && smoke_test "pg_hint_plan loaded" \
    "SHOW pg_hint_plan.enable_hint;"
has_ext pg_ivm && smoke_test "pg_ivm functions" \
    "SELECT count(*) FROM pg_proc WHERE proname = 'create_immv';"
has_ext pg_jsonschema && smoke_test "pg_jsonschema validate" \
    "SELECT json_matches_schema('{\"type\":\"object\"}'::json, '{}'::json);"
has_ext pg_lake && smoke_test "pg_lake fdw" \
    "SELECT count(*) FROM pg_foreign_data_wrapper WHERE fdwname = 'pg_lake';"
has_ext pg_net && smoke_test "pg_net schema" \
    "SELECT count(*) FROM pg_namespace WHERE nspname = 'net';"
has_ext pg_qualstats && smoke_test "pg_qualstats view" \
    "SELECT count(*) FROM pg_qualstats();"
has_ext pg_partman && smoke_test "pg_partman config table" \
    "SELECT count(*) FROM public.part_config;"
has_ext pg_repack && smoke_test "pg_repack version" \
    "SELECT repack.version();"
has_ext pg_roaringbitmap && smoke_test "pg_roaringbitmap ops" \
    "SELECT rb_cardinality(rb_build(ARRAY[1,2,3]::int[]));"
has_ext pg_similarity && smoke_test "pg_similarity levenshtein" \
    "SELECT lev('hello', 'hallo');"
has_ext pgrouting && smoke_test "pgrouting dijkstra" \
    "SELECT count(*) FROM pg_proc WHERE proname = 'pgr_dijkstra';"
has_ext pgsodium && smoke_test "pgsodium random" \
    "SELECT length(pgsodium.randombytes_buf(16));"
has_ext pgtap && smoke_test "pgtap version" \
    "SELECT pgtap_version();"
has_ext pgtt && smoke_test "pgtt loaded" \
    "SELECT count(*) FROM pg_proc WHERE proname = 'pgtt_is_global_temporary';"
has_ext pg_squeeze && smoke_test "pg_squeeze schema" \
    "SELECT count(*) FROM squeeze.tables;"
has_ext pg_stat_monitor && smoke_test "pg_stat_monitor view" \
    "SELECT count(*) FROM pg_stat_monitor;"
has_ext pg_textsearch && smoke_test "pg_textsearch index" \
    "SELECT count(*) FROM pg_available_extensions WHERE name = 'pg_textsearch';"
has_ext pg_uuidv7 && smoke_test "pg_uuidv7 generate" \
    "SELECT uuid_generate_v7();"
has_ext pg_wait_sampling && smoke_test "pg_wait_sampling profile" \
    "SELECT count(*) FROM pg_wait_sampling_profile;"
has_ext pgaudit && smoke_test "pgaudit active" \
    "SHOW pgaudit.log;"
has_ext pgjwt && smoke_test "pgjwt sign" \
    "SELECT sign('{\"sub\":\"test\"}'::json, 'secret');"
has_ext pglogical && smoke_test "pglogical version" \
    "SELECT pglogical.pglogical_version();"
has_ext pgvector && smoke_test "pgvector similarity" \
    "SELECT '[1,2,3]'::vector <-> '[4,5,6]'::vector;"
has_ext pgvectorscale && smoke_test "pgvectorscale diskann" \
    "SELECT count(*) FROM pg_am WHERE amname = 'diskann';"
has_ext pgfincore && smoke_test "pgfincore loaded" \
    "SELECT count(*) FROM pg_proc WHERE proname = 'pgfincore';"
has_ext plpgsql_check && smoke_test "plpgsql_check lint" \
    "SELECT count(*) FROM pg_proc WHERE proname = 'plpgsql_check_function';"
has_ext plprofiler && smoke_test "plprofiler loaded" \
    "SELECT count(*) FROM pg_proc WHERE proname = 'pl_profiler_get_source';"
has_ext plv8 && smoke_test "plv8 javascript" \
    "SELECT plv8_version();"
has_ext postgis && smoke_test "PostGIS geometry" \
    "SELECT ST_AsText(ST_GeomFromText('POINT(1 2)'));"
has_ext postgres_protobuf && smoke_test "postgres_protobuf loaded" \
    "SELECT count(*) FROM pg_proc WHERE proname = 'protobuf_decode';"
has_ext prefix && smoke_test "prefix range" \
    "SELECT '123'::prefix_range @> '1234567890';"
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
has_ext wrappers && smoke_test "wrappers loaded" \
    "SELECT count(*) FROM pg_extension WHERE extname = 'wrappers';"
echo

# ============================================================
# Phase 7: Integration tests (per-extension test.sql files)
# ============================================================
info "Phase 7: Integration tests (extensions/*/test.sql)..."

# Ensure container is healthy before starting integration tests
wait_for_ready

for ext in "${EXTENSIONS[@]}"; do
    test_file="extensions/${ext}/test.sql"
    if [ ! -f "$test_file" ]; then
        warn "${ext}: no test.sql found"
        continue
    fi
    output="$(docker exec -i pgx-func-test psql -U postgres -tA -v ON_ERROR_STOP=0 < "$test_file" 2>&1)" || true
    # Retry up to 3 times if the server was in recovery mode
    retries=0
    while [ "$retries" -lt 3 ] && echo "$output" | grep -qE "recovery mode|not yet accepting|crash of another|server closed the connection"; do
        wait_for_ready
        output="$(docker exec -i pgx-func-test psql -U postgres -tA -v ON_ERROR_STOP=0 < "$test_file" 2>&1)" || true
        ((retries++)) || true
    done
    failures="$(echo "$output" | grep '^FAIL' || true)"
    passes="$(echo "$output" | grep -c '^PASS' || true)"
    if [ -n "$failures" ]; then
        fail "integration ${ext}:"
        # shellcheck disable=SC2001
        # Prepending indent to each line; no bash-native equivalent for multiline
        echo "$failures" | sed 's/^/       /'
    elif [ "$passes" -gt 0 ]; then
        pass "integration ${ext} (${passes} checks)"
    else
        warn "${ext}: test.sql produced no PASS/FAIL output"
    fi
done

# ============================================================
# Phase 8: MongoDB wire protocol test (documentdb gateway)
# ============================================================
if has_ext documentdb; then
    info "Phase 8: DocumentDB MongoDB wire protocol test..."
    wait_for_ready

    # Create a test user (BlockedRolePrefixes blocks 'pg*' prefix)
    docker exec pgx-func-test psql -U postgres -c \
        "CREATE ROLE docdb_test WITH LOGIN PASSWORD 'docdb_test' SUPERUSER;" >/dev/null 2>&1 || true

    # Install pymongo in the container
    if docker exec pgx-func-test bash -c \
        "apt-get update -qq && apt-get install -qq -y python3-pip >/dev/null 2>&1 && pip3 install --break-system-packages pymongo >/dev/null 2>&1" 2>/dev/null; then

        # Wait for gateway to be ready (port 10260)
        gw_ready=false
        for i in $(seq 1 15); do
            if docker exec pgx-func-test bash -c 'timeout 1 bash -c "echo > /dev/tcp/localhost/10260" 2>/dev/null'; then
                gw_ready=true
                break
            fi
            sleep 1
        done

        if [ "$gw_ready" = true ]; then
            output="$(docker exec -i pgx-func-test python3 < extensions/documentdb/test_mongo.py 2>&1)" || true
            failures="$(echo "$output" | grep '^FAIL' || true)"
            passes="$(echo "$output" | grep -c '^PASS' || true)"
            if [ -n "$failures" ]; then
                fail "mongo protocol:"
                # shellcheck disable=SC2001
                # Prepending indent to each line; no bash-native equivalent for multiline
                echo "$failures" | sed 's/^/       /'
            elif [ "$passes" -gt 0 ]; then
                pass "mongo protocol (${passes} checks)"
            else
                warn "documentdb: test_mongo.py produced no PASS/FAIL output"
                echo "$output" | tail -5 | sed 's/^/       /'
            fi
        else
            warn "documentdb: gateway port 10260 not ready after 15s, skipping mongo tests"
        fi
    else
        warn "documentdb: could not install pymongo, skipping mongo protocol tests"
    fi
    echo
fi

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
