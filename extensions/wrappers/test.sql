-- wrappers integration tests
CREATE EXTENSION IF NOT EXISTS wrappers;

-- Test: extension is listed in pg_extension
SELECT CASE
    WHEN (SELECT count(*) FROM pg_extension WHERE extname = 'wrappers') = 1
    THEN 'PASS wrappers: extension loaded in pg_extension'
    ELSE 'FAIL wrappers: extension loaded in pg_extension'
END;

-- Test: extension version is accessible
SELECT CASE
    WHEN (SELECT extversion FROM pg_extension WHERE extname = 'wrappers') IS NOT NULL
    THEN 'PASS wrappers: extension version is set'
    ELSE 'FAIL wrappers: extension version is set'
END;
