-- pgtt integration tests
CREATE EXTENSION IF NOT EXISTS pgtt;

-- Test: pgtt_schema namespace exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_namespace WHERE nspname = 'pgtt_schema') > 0
    THEN 'PASS pgtt: pgtt_schema namespace exists'
    ELSE 'FAIL pgtt: pgtt_schema namespace exists'
END;

-- Test: extension is loaded
SELECT CASE
    WHEN (SELECT count(*) FROM pg_extension WHERE extname = 'pgtt') = 1
    THEN 'PASS pgtt: extension loaded in pg_extension'
    ELSE 'FAIL pgtt: extension loaded in pg_extension'
END;
