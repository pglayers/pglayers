-- first_last_agg integration tests.
CREATE EXTENSION IF NOT EXISTS first_last_agg;

-- Load/sanity
SELECT CASE
    WHEN (SELECT count(*) FROM pg_extension WHERE extname = 'first_last_agg') = 1
    THEN 'PASS first_last_agg: extension loads'
    ELSE 'FAIL first_last_agg: extension loads'
END;

-- first() with ordering returns the lowest-ordered value
SELECT CASE
    WHEN (SELECT first(x ORDER BY x) FROM (VALUES (30),(10),(20)) t(x)) = 10
    THEN 'PASS first_last_agg: first() returns first ordered value'
    ELSE 'FAIL first_last_agg: first() returns first ordered value'
END;

-- last() with ordering returns the highest-ordered value
SELECT CASE
    WHEN (SELECT last(x ORDER BY x) FROM (VALUES (30),(10),(20)) t(x)) = 30
    THEN 'PASS first_last_agg: last() returns last ordered value'
    ELSE 'FAIL first_last_agg: last() returns last ordered value'
END;
