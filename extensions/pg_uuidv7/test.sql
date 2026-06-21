-- pg_uuidv7 integration tests
CREATE EXTENSION IF NOT EXISTS pg_uuidv7;

-- Test: generate UUIDv7
SELECT CASE
    WHEN uuid_generate_v7() IS NOT NULL
    THEN 'PASS pg_uuidv7: uuid_generate_v7 works'
    ELSE 'FAIL pg_uuidv7: uuid_generate_v7 works'
END;

-- Test: UUIDv7 is time-sortable (later call > earlier call)
SELECT CASE
    WHEN uuid_generate_v7() > uuid_generate_v7_from_timestamp('2020-01-01'::timestamptz)
    THEN 'PASS pg_uuidv7: time-sortable ordering'
    ELSE 'FAIL pg_uuidv7: time-sortable ordering'
END;

-- Test: extract timestamp from UUIDv7
SELECT CASE
    WHEN uuid_v7_to_timestamp(uuid_generate_v7()) > now() - interval '1 minute'
    THEN 'PASS pg_uuidv7: timestamp extraction'
    ELSE 'FAIL pg_uuidv7: timestamp extraction'
END;
