#!/usr/bin/env bash
# Shared SQL-test gates. Callers provide pass() and fail() result reporters.

run_sql_test() {
    local container="$1" test_file="$2" label="$3"
    local output status=0 passes
    local complete="__PGLAYERS_SQL_TEST_COMPLETE__"

    if [ ! -r "$test_file" ]; then
        fail "${label}: cannot read ${test_file}"
        return 1
    fi

    # Ignore psqlrc files and stop at the first SQL error. Preserve docker/psql's
    # status even when earlier assertions printed PASS. The final marker also
    # rejects early successful exits (e.g. \quit) that truncate the test file.
    if output="$(
        { cat "$test_file" && printf '\n\\echo %s\n' "$complete"; } \
            | docker exec -i "$container" psql -X -U postgres -tA \
                -v ON_ERROR_STOP=1 -f - 2>&1
    )"; then
        status=0
    else
        status=$?
    fi

    passes="$(printf '%s\n' "$output" | grep -c '^PASS' || true)"
    if [ "$status" -ne 0 ]; then
        fail "${label}: test.sql exited with status ${status}"
    elif ! grep -qxF "$complete" <<< "$output"; then
        fail "${label}: test.sql did not complete"
    elif grep -q '^FAIL' <<< "$output"; then
        fail "${label}: test.sql reported a failed assertion"
    elif [ "$passes" -eq 0 ]; then
        fail "${label}: test.sql produced no PASS/FAIL output"
    else
        pass "${label} (${passes} checks)"
        return 0
    fi

    # Keep errors and partial assertion output, not just explicit FAIL rows.
    printf '%s\n' "$output" | sed '/^__PGLAYERS_SQL_TEST_COMPLETE__$/d; s/^/       /'
    return 1
}

check_sql_test_logs() {
    local container="$1" logs crashes
    if ! logs="$(docker logs "$container" 2>&1)"; then
        fail "could not read server logs after SQL tests"
        printf '%s\n' "$logs" | sed 's/^/       /'
        return 1
    fi

    # A recovered backend/background-worker crash is still a failure, even if a
    # later query succeeds. Normal administrative shutdowns do not match these.
    crashes="$(printf '%s\n' "$logs" | grep -iE \
        'was terminated by signal|terminating connection because of crash of another server process|PANIC:' || true)"
    if [ -n "$crashes" ]; then
        fail "server crash detected during SQL tests; recent server log:"
        printf '%s\n' "$logs" | tail -80 | sed 's/^/       /'
        return 1
    fi
    pass "no server crashes during SQL tests"
}
