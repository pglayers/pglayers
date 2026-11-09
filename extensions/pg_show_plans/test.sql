-- pg_show_plans (live query plans; requires shared_preload_libraries) tests.
CREATE EXTENSION IF NOT EXISTS pg_show_plans;

SELECT CASE WHEN (SELECT count(*) FROM pg_extension WHERE extname='pg_show_plans')=1
    THEN 'PASS pg_show_plans: extension loads' ELSE 'FAIL pg_show_plans: extension loads' END;

-- the pg_show_plans view is queryable (lists in-flight plans)
-- Combined images with pg_duckdb disable automatic capture by default because
-- of duckdb/pg_duckdb#1042. Enable it only for these ordinary PostgreSQL queries.
BEGIN;
SET LOCAL pg_show_plans.is_enabled = true;
SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_show_plans WHERE pid = pg_backend_pid())
    THEN 'PASS pg_show_plans: pg_show_plans view is queryable'
    ELSE 'FAIL pg_show_plans: pg_show_plans view is queryable' END;
ROLLBACK;
