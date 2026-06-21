-- pg_hashids integration tests
CREATE EXTENSION IF NOT EXISTS pg_hashids;

-- Test: id_encode function exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc WHERE proname = 'id_encode') > 0
    THEN 'PASS pg_hashids: id_encode function exists'
    ELSE 'FAIL pg_hashids: id_encode function exists'
END;

-- Test: encode and decode round-trip
SELECT CASE
    WHEN id_decode(id_encode(42, 'salt')) = 42
    THEN 'PASS pg_hashids: encode/decode round-trip works'
    ELSE 'FAIL pg_hashids: encode/decode round-trip works'
END;

-- Test: encode produces non-empty string
SELECT CASE
    WHEN length(id_encode(123, 'test_salt')) > 0
    THEN 'PASS pg_hashids: encode produces non-empty hash'
    ELSE 'FAIL pg_hashids: encode produces non-empty hash'
END;
