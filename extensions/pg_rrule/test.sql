-- pg_rrule (iCalendar RRULE recurrence) integration tests.
CREATE EXTENSION IF NOT EXISTS pg_rrule;

SELECT CASE
    WHEN (SELECT count(*) FROM pg_extension WHERE extname = 'pg_rrule') = 1
    THEN 'PASS pg_rrule: extension loads'
    ELSE 'FAIL pg_rrule: extension loads'
END;

-- a COUNT=3 daily rule yields exactly 3 occurrences
SELECT CASE
    WHEN array_length(
             get_occurrences('FREQ=DAILY;COUNT=3'::rrule,
                             '2020-01-01 00:00:00'::timestamp), 1) = 3
    THEN 'PASS pg_rrule: daily COUNT=3 yields 3 occurrences'
    ELSE 'FAIL pg_rrule: daily COUNT=3 yields 3 occurrences'
END;

-- the first occurrence is the start instant
SELECT CASE
    WHEN (get_occurrences('FREQ=DAILY;COUNT=3'::rrule,
                          '2020-01-01 00:00:00'::timestamp))[1]
         = '2020-01-01 00:00:00'::timestamp
    THEN 'PASS pg_rrule: first occurrence is the start'
    ELSE 'FAIL pg_rrule: first occurrence is the start'
END;
