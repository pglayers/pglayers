-- http integration tests
CREATE EXTENSION IF NOT EXISTS http;

-- Test: http_get function exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc WHERE proname = 'http_get') > 0
    THEN 'PASS http: http_get function available'
    ELSE 'FAIL http: http_get function available'
END;

-- Test: http_post function exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc WHERE proname = 'http_post') > 0
    THEN 'PASS http: http_post function available'
    ELSE 'FAIL http: http_post function available'
END;

-- Test: http composite type exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_type WHERE typname = 'http_response') > 0
    THEN 'PASS http: http_response type available'
    ELSE 'FAIL http: http_response type available'
END;
