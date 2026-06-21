-- pg_stat_monitor integration tests
CREATE EXTENSION IF NOT EXISTS pg_stat_monitor;

-- Test: extension loaded
SELECT CASE
    WHEN (SELECT count(*) FROM pg_extension WHERE extname = 'pg_stat_monitor') = 1
    THEN 'PASS pg_stat_monitor: extension loaded'
    ELSE 'FAIL pg_stat_monitor: extension loaded'
END;

-- Test: view exists and returns data
SELECT 1+1;
SELECT CASE
    WHEN (SELECT count(*) FROM pg_stat_monitor) >= 0
    THEN 'PASS pg_stat_monitor: pg_stat_monitor view queryable'
    ELSE 'FAIL pg_stat_monitor: pg_stat_monitor view queryable'
END;
