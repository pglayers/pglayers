-- anon (postgresql_anonymizer) integration tests
CREATE EXTENSION IF NOT EXISTS anon CASCADE;

-- Test: extension loaded
SELECT CASE
    WHEN (SELECT count(*) FROM pg_extension WHERE extname = 'anon') = 1
    THEN 'PASS anon: extension loaded'
    ELSE 'FAIL anon: extension loaded'
END;

-- Exercise real masking, rather than only testing the function catalog.
SELECT CASE
    WHEN anon.partial('1234567890', 2, '******', 2) = '12******90'
    THEN 'PASS anon: partial masking preserves the requested prefix and suffix'
    ELSE 'FAIL anon: partial masking preserves the requested prefix and suffix'
END;

-- Test: anonymization functions available
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc WHERE proname LIKE 'fake_%'
          AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'anon')) > 0
    THEN 'PASS anon: fake_* functions available'
    ELSE 'FAIL anon: fake_* functions available'
END;
