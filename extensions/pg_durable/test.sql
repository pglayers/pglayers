-- pg_durable integration tests
CREATE EXTENSION IF NOT EXISTS pg_durable;

-- Test: extension loaded
SELECT CASE
    WHEN (SELECT count(*) FROM pg_extension WHERE extname = 'pg_durable') = 1
    THEN 'PASS pg_durable: extension loaded'
    ELSE 'FAIL pg_durable: extension loaded'
END;

-- Test: df schema exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_namespace WHERE nspname = 'df') = 1
    THEN 'PASS pg_durable: df schema exists'
    ELSE 'FAIL pg_durable: df schema exists'
END;

-- Test: core functions available
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc WHERE pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'df')) > 0
    THEN 'PASS pg_durable: df functions available'
    ELSE 'FAIL pg_durable: df functions available'
END;
