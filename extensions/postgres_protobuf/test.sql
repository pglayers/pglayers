-- postgres_protobuf integration tests
CREATE EXTENSION IF NOT EXISTS postgres_protobuf;

-- Test: protobuf_decode function exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc WHERE proname = 'protobuf_decode') > 0
    THEN 'PASS postgres_protobuf: protobuf_decode function available'
    ELSE 'FAIL postgres_protobuf: protobuf_decode function available'
END;

-- Test: protobuf_to_json_text function exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc WHERE proname = 'protobuf_to_json_text') > 0
    THEN 'PASS postgres_protobuf: protobuf_to_json_text function available'
    ELSE 'FAIL postgres_protobuf: protobuf_to_json_text function available'
END;

-- Test: protobuf_from_json_text function exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc WHERE proname = 'protobuf_from_json_text') > 0
    THEN 'PASS postgres_protobuf: protobuf_from_json_text function available'
    ELSE 'FAIL postgres_protobuf: protobuf_from_json_text function available'
END;
