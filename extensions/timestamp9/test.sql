-- timestamp9 (nanosecond-precision timestamps) integration tests.
CREATE EXTENSION IF NOT EXISTS timestamp9;

SELECT CASE
    WHEN (SELECT count(*) FROM pg_extension WHERE extname = 'timestamp9') = 1
    THEN 'PASS timestamp9: extension loads'
    ELSE 'FAIL timestamp9: extension loads'
END;

-- round-trips through the standard timestamp type
SELECT CASE
    WHEN timestamp9_to_timestamp(timestamp_to_timestamp9('2020-01-01 12:00:00'::timestamp))
         = '2020-01-01 12:00:00'::timestamp
    THEN 'PASS timestamp9: converts to/from timestamp'
    ELSE 'FAIL timestamp9: converts to/from timestamp'
END;

-- ordering of two distinct instants
SELECT CASE
    WHEN timestamp_to_timestamp9('2020-01-01 00:00:00'::timestamp)
       < timestamp_to_timestamp9('2020-01-02 00:00:00'::timestamp)
    THEN 'PASS timestamp9: ordering comparison'
    ELSE 'FAIL timestamp9: ordering comparison'
END;
