-- anon (postgresql_anonymizer) integration tests
CREATE EXTENSION IF NOT EXISTS anon CASCADE;

-- Test: extension loaded
SELECT CASE
    WHEN (SELECT count(*) FROM pg_extension WHERE extname = 'anon') = 1
    THEN 'PASS anon: extension loaded'
    ELSE 'FAIL anon: extension loaded'
END;

-- Test: anonymization functions available
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc WHERE proname LIKE 'fake_%'
          AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'anon')) > 0
    THEN 'PASS anon: fake_* functions available'
    ELSE 'FAIL anon: fake_* functions available'
END;
