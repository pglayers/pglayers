-- pg_stat_kcache integration tests
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pg_stat_kcache;

-- Test 1: Extension loads and exposes its statistics views
SELECT CASE
    WHEN to_regclass('pg_stat_kcache') IS NOT NULL
     AND to_regclass('pg_stat_kcache_detail') IS NOT NULL
    THEN 'PASS pg_stat_kcache: extension loaded with statistics views'
    ELSE 'FAIL pg_stat_kcache: extension loaded with statistics views'
END;

SET pg_stat_statements.track = 'all';
SET pg_stat_kcache.track = 'top';
CREATE TEMP TABLE pglayers_kcache_test AS
SELECT i AS value FROM generate_series(1, 100000) AS s(i);

-- Test 2: A real query records CPU usage and joins to pg_stat_statements
SELECT sum(length(md5(value::text))) FROM pglayers_kcache_test;
SELECT CASE
    WHEN EXISTS (
        SELECT 1 FROM pg_stat_kcache_detail
        WHERE query LIKE 'SELECT sum(length(md5(value::text))) FROM pglayers_kcache_test%'
          AND datname = current_database()
          AND top
          AND exec_user_time + exec_system_time > 0
          AND exec_reads >= 0 AND exec_writes >= 0
    )
    THEN 'PASS pg_stat_kcache: query records CPU and I/O statistics'
    ELSE 'FAIL pg_stat_kcache: query records CPU and I/O statistics'
END;

-- Test 3: Per-database aggregation includes the recorded workload
SELECT CASE
    WHEN EXISTS (
        SELECT 1 FROM pg_stat_kcache
        WHERE datname = current_database()
          AND exec_user_time + exec_system_time > 0
          AND exec_reads >= 0 AND exec_writes >= 0
    )
    THEN 'PASS pg_stat_kcache: database view aggregates query statistics'
    ELSE 'FAIL pg_stat_kcache: database view aggregates query statistics'
END;

-- Test 4: Reset removes the workload's kernel counters
SELECT pg_stat_kcache_reset();
SELECT CASE
    WHEN NOT EXISTS (
        SELECT 1 FROM pg_stat_kcache_detail
        WHERE query LIKE 'SELECT sum(length(md5(value::text))) FROM pglayers_kcache_test%'
          AND datname = current_database()
    )
    THEN 'PASS pg_stat_kcache: reset clears query statistics'
    ELSE 'FAIL pg_stat_kcache: reset clears query statistics'
END;

DROP TABLE pglayers_kcache_test;
RESET pg_stat_statements.track;
RESET pg_stat_kcache.track;
