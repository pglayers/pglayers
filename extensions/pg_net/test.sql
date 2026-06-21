-- pg_net integration tests
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Test: net schema exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_namespace WHERE nspname = 'net') = 1
    THEN 'PASS pg_net: net schema created'
    ELSE 'FAIL pg_net: net schema created'
END;

-- Test: http_get function exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc p
          JOIN pg_namespace n ON p.pronamespace = n.oid
          WHERE n.nspname = 'net' AND p.proname = 'http_get') > 0
    THEN 'PASS pg_net: net.http_get function available'
    ELSE 'FAIL pg_net: net.http_get function available'
END;

-- Test: http_post function exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc p
          JOIN pg_namespace n ON p.pronamespace = n.oid
          WHERE n.nspname = 'net' AND p.proname = 'http_post') > 0
    THEN 'PASS pg_net: net.http_post function available'
    ELSE 'FAIL pg_net: net.http_post function available'
END;
