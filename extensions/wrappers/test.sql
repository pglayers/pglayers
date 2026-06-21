-- wrappers integration tests
CREATE EXTENSION IF NOT EXISTS wrappers;

-- Test: wrappers schema exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_namespace WHERE nspname = 'wrappers') > 0
    THEN 'PASS wrappers: wrappers schema created'
    ELSE 'FAIL wrappers: wrappers schema created'
END;

-- Test: foreign data wrapper registered
SELECT CASE
    WHEN (SELECT count(*) FROM pg_foreign_data_wrapper WHERE fdwname = 'wrappers_fdw') > 0
         OR (SELECT count(*) FROM pg_proc p
             JOIN pg_namespace n ON p.pronamespace = n.oid
             WHERE n.nspname = 'wrappers') > 0
    THEN 'PASS wrappers: FDW or wrappers functions registered'
    ELSE 'FAIL wrappers: FDW or wrappers functions registered'
END;

-- Test: extension is listed in pg_extension
SELECT CASE
    WHEN (SELECT count(*) FROM pg_extension WHERE extname = 'wrappers') = 1
    THEN 'PASS wrappers: extension loaded in pg_extension'
    ELSE 'FAIL wrappers: extension loaded in pg_extension'
END;
