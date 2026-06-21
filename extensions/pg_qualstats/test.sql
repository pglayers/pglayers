-- pg_qualstats integration tests
CREATE EXTENSION IF NOT EXISTS pg_qualstats;

-- Test: pg_qualstats view exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_views WHERE viewname = 'pg_qualstats') > 0
    THEN 'PASS pg_qualstats: pg_qualstats view exists'
    ELSE 'FAIL pg_qualstats: pg_qualstats view exists'
END;

-- Test: pg_qualstats_reset function exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc WHERE proname = 'pg_qualstats_reset') > 0
    THEN 'PASS pg_qualstats: pg_qualstats_reset function exists'
    ELSE 'FAIL pg_qualstats: pg_qualstats_reset function exists'
END;

-- Test: can query pg_qualstats view without error
SELECT CASE
    WHEN (SELECT count(*) FROM pg_qualstats) >= 0
    THEN 'PASS pg_qualstats: view is queryable'
    ELSE 'FAIL pg_qualstats: view is queryable'
END;
