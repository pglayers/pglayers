-- pg_squeeze integration tests
CREATE EXTENSION IF NOT EXISTS pg_squeeze;

-- Test: schema exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_namespace WHERE nspname = 'squeeze') = 1
    THEN 'PASS pg_squeeze: squeeze schema exists'
    ELSE 'FAIL pg_squeeze: squeeze schema exists'
END;

-- Test: tables table exists for registering tables
SELECT CASE
    WHEN (SELECT count(*) FROM information_schema.tables WHERE table_schema = 'squeeze' AND table_name = 'tables') = 1
    THEN 'PASS pg_squeeze: squeeze.tables config table exists'
    ELSE 'FAIL pg_squeeze: squeeze.tables config table exists'
END;
