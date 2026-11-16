-- pg_stat_monitor integration tests
CREATE EXTENSION IF NOT EXISTS pg_stat_monitor;

-- Test: extension loaded
SELECT CASE
    WHEN (SELECT count(*) FROM pg_extension WHERE extname = 'pg_stat_monitor') = 1
    THEN 'PASS pg_stat_monitor: extension loaded'
    ELSE 'FAIL pg_stat_monitor: extension loaded'
END;

-- Exercise the planner/executor hooks and require real collected statistics.
CREATE TEMP TABLE pgsm_regression_probe (id int);
INSERT INTO pgsm_regression_probe VALUES (1), (2), (3);
SELECT count(*) FROM pgsm_regression_probe;
SELECT CASE
    WHEN (SELECT coalesce(sum(calls), 0) FROM pg_stat_monitor
          WHERE query LIKE 'SELECT count(*) FROM pgsm_regression_probe%') >= 1
    THEN 'PASS pg_stat_monitor: executed queries are recorded'
    ELSE 'FAIL pg_stat_monitor: executed queries are recorded'
END;

-- Cover relation permission checks for views after the PG19 graph-API revert.
CREATE TEMP VIEW pgsm_regression_view AS SELECT * FROM pgsm_regression_probe;
SELECT CASE
    WHEN (SELECT sum(id) FROM pgsm_regression_view) = 6
    THEN 'PASS pg_stat_monitor: relation hooks handle views'
    ELSE 'FAIL pg_stat_monitor: relation hooks handle views'
END;

DROP VIEW pgsm_regression_view;
DROP TABLE pgsm_regression_probe;
