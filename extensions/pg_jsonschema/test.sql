-- pg_jsonschema integration tests
CREATE EXTENSION IF NOT EXISTS pg_jsonschema;

-- Test: json_matches_schema function exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc WHERE proname = 'json_matches_schema') > 0
    THEN 'PASS pg_jsonschema: json_matches_schema function available'
    ELSE 'FAIL pg_jsonschema: json_matches_schema function available'
END;

-- Test: valid JSON passes schema validation
SELECT CASE
    WHEN json_matches_schema(
        '{"type": "object", "properties": {"name": {"type": "string"}}}'::json,
        '{"name": "test"}'::json
    ) = true
    THEN 'PASS pg_jsonschema: valid JSON passes schema'
    ELSE 'FAIL pg_jsonschema: valid JSON passes schema'
END;

-- Test: invalid JSON fails schema validation
SELECT CASE
    WHEN json_matches_schema(
        '{"type": "object", "properties": {"age": {"type": "integer"}}}'::json,
        '{"age": "not a number"}'::json
    ) = false
    THEN 'PASS pg_jsonschema: invalid JSON fails schema'
    ELSE 'FAIL pg_jsonschema: invalid JSON fails schema'
END;
