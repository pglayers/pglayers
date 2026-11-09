#!/usr/bin/env bash
# Fast regression tests for the SQL gates; no Docker daemon required.
set -euo pipefail

# shellcheck source=tests/sql-test-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/sql-test-lib.sh"

pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; }

# Read a real SQL file but stub the Docker boundary, including the exit status.
# This keeps the runner's command flags, stdin, and result handling under test.
docker() {
    case "$1" in
        exec)
            if [ "$*" != 'exec -i test-container psql -X -U postgres -tA -v ON_ERROR_STOP=1 -f -' ]; then
                echo "unexpected docker command: $*" >&2
                return 99
            fi
            local sql
            sql="$(cat)"
            if [[ "$sql" != *'\echo __PGLAYERS_SQL_TEST_COMPLETE__' ]]; then
                echo 'missing completion marker in SQL input' >&2
                return 99
            fi
            ;;
        logs) ;;
        *) echo "unexpected docker command: $*" >&2; return 99 ;;
    esac
    printf '%s\n' "$MOCK_OUTPUT"
    return "$MOCK_STATUS"
}

expect_result() {
    local expected_status="$1" expected_output="$2"
    shift 2
    local output status=0
    if output="$("$@")"; then
        status=0
    else
        status=$?
    fi
    if [ "$status" -ne "$expected_status" ] || [[ "$output" != *"$expected_output"* ]]; then
        printf 'FAIL expected status %s and %s; got status %s:\n%s\n' \
            "$expected_status" "$expected_output" "$status" "$output" >&2
        exit 1
    fi
    if [ "$expected_status" -ne 0 ] && grep -q '^PASS' <<< "$output"; then
        printf 'FAIL failed run also reported a PASS:\n%s\n' "$output" >&2
        exit 1
    fi
    printf 'PASS %s\n' "$expected_output"
}

sql_file="$(dirname "${BASH_SOURCE[0]}")/../extensions/pg_statviz/test.sql"
complete='__PGLAYERS_SQL_TEST_COMPLETE__'

MOCK_STATUS=0
MOCK_OUTPUT="PASS fixture: loads
PASS fixture: snapshot
$complete"
expect_result 0 'fixture (2 checks)' run_sql_test test-container "$sql_file" fixture

MOCK_OUTPUT="PASS fixture: loads
FAIL fixture: snapshot
$complete"
expect_result 1 'failed assertion' run_sql_test test-container "$sql_file" fixture

MOCK_OUTPUT="$complete"
expect_result 1 'no PASS/FAIL output' run_sql_test test-container "$sql_file" fixture

MOCK_OUTPUT='PASS fixture: loads'
expect_result 1 'did not complete' run_sql_test test-container "$sql_file" fixture

MOCK_STATUS=3
MOCK_OUTPUT='PASS fixture: loads
ERROR: division by zero'
expect_result 1 'test.sql exited with status 3' run_sql_test test-container "$sql_file" fixture
expect_result 1 'ERROR: division by zero' run_sql_test test-container "$sql_file" fixture

MOCK_STATUS=2
MOCK_OUTPUT='PASS fixture: loads
server closed the connection unexpectedly'
expect_result 1 'test.sql exited with status 2' run_sql_test test-container "$sql_file" fixture
expect_result 1 'server closed the connection unexpectedly' run_sql_test test-container "$sql_file" fixture

# A successful-looking payload must not override a Docker execution failure.
MOCK_STATUS=125
MOCK_OUTPUT="PASS fixture: loads
$complete"
expect_result 1 'test.sql exited with status 125' run_sql_test test-container "$sql_file" fixture

expect_result 1 'cannot read' run_sql_test test-container /dev/null/missing.sql fixture

MOCK_STATUS=0
MOCK_OUTPUT='LOG: database system is ready to accept connections
LOG: background worker "logical replication launcher" exited with exit code 1'
expect_result 0 'no server crashes' check_sql_test_logs test-container

MOCK_OUTPUT='LOG: client backend (PID 123) was terminated by signal 11: Segmentation fault
LOG: database system is ready to accept connections'
expect_result 1 'server crash detected' check_sql_test_logs test-container

MOCK_OUTPUT='LOG: background worker "fixture" (PID 123) was terminated by signal 6: Aborted'
expect_result 1 'server crash detected' check_sql_test_logs test-container

MOCK_OUTPUT='PANIC: fixture failure'
expect_result 1 'server crash detected' check_sql_test_logs test-container

MOCK_STATUS=1
MOCK_OUTPUT='Error response from daemon: No such container'
expect_result 1 'could not read server logs' check_sql_test_logs test-container
