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
    WHEN id_decode(id_encode(42, 'salt'), 'salt') = ARRAY[42]::bigint[]
    THEN 'PASS pg_hashids: encode/decode round-trip works'
    ELSE 'FAIL pg_hashids: encode/decode round-trip works'
END;

-- Test: arrays of IDs round-trip using the same salt
SELECT CASE
    WHEN id_decode(id_encode(ARRAY[1, 42, 123456]::bigint[], 'salt'), 'salt')
         = ARRAY[1, 42, 123456]::bigint[]
    THEN 'PASS pg_hashids: multiple IDs round-trip'
    ELSE 'FAIL pg_hashids: multiple IDs round-trip'
END;

-- Test: encode produces non-empty string
SELECT CASE
    WHEN length(id_encode(123, 'test_salt')) > 0
    THEN 'PASS pg_hashids: encode produces non-empty hash'
    ELSE 'FAIL pg_hashids: encode produces non-empty hash'
END;
