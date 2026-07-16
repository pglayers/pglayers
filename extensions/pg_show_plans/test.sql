-- pg_show_plans (live query plans; requires shared_preload_libraries) tests.
CREATE EXTENSION IF NOT EXISTS pg_show_plans;

SELECT CASE WHEN (SELECT count(*) FROM pg_extension WHERE extname='pg_show_plans')=1
    THEN 'PASS pg_show_plans: extension loads' ELSE 'FAIL pg_show_plans: extension loads' END;

-- the pg_show_plans view is queryable (lists in-flight plans)
SELECT CASE WHEN (SELECT count(*) >= 0 FROM pg_show_plans)
    THEN 'PASS pg_show_plans: pg_show_plans view is queryable'
    ELSE 'FAIL pg_show_plans: pg_show_plans view is queryable' END;
