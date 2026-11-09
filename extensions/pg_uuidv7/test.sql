-- pg_uuidv7 integration tests
CREATE EXTENSION IF NOT EXISTS pg_uuidv7;

-- Test: generate UUIDv7
SELECT CASE
    WHEN uuid_generate_v7() IS NOT NULL
    THEN 'PASS pg_uuidv7: uuid_generate_v7 works'
    ELSE 'FAIL pg_uuidv7: uuid_generate_v7 works'
END;

-- Test: UUIDv7 is time-sortable, independently of the server clock
SELECT CASE
    WHEN uuid_timestamptz_to_v7('2021-01-01+00'::timestamptz)
         > uuid_timestamptz_to_v7('2020-01-01+00'::timestamptz)
    THEN 'PASS pg_uuidv7: time-sortable ordering'
    ELSE 'FAIL pg_uuidv7: time-sortable ordering'
END;

-- Test: timestamps round-trip at UUIDv7's millisecond precision
SELECT CASE
    WHEN uuid_v7_to_timestamptz(uuid_timestamptz_to_v7('2020-01-01 12:34:56.789+00'::timestamptz))
         = '2020-01-01 12:34:56.789+00'::timestamptz
    THEN 'PASS pg_uuidv7: timestamp extraction'
    ELSE 'FAIL pg_uuidv7: timestamp extraction'
END;
