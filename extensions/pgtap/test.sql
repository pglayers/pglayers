-- pgTAP integration tests
CREATE EXTENSION IF NOT EXISTS pgtap;

-- Test: pgTAP version function exists
SELECT CASE
    WHEN pgtap_version() IS NOT NULL
    THEN 'PASS pgtap: version function returns value'
    ELSE 'FAIL pgtap: version function returns value'
END;

-- Test: core test functions available
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc WHERE proname IN ('ok', 'is', 'isnt', 'pass', 'fail')) >= 4
    THEN 'PASS pgtap: core test functions available'
    ELSE 'FAIL pgtap: core test functions available'
END;

-- Test: can run a basic assertion
SELECT CASE
    WHEN ok(1 = 1, 'one equals one') ~ '^ok'
    THEN 'PASS pgtap: ok() assertion works'
    ELSE 'FAIL pgtap: ok() assertion works'
END;
