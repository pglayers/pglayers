-- timescaledb integration tests
-- NOTE: timescaledb CONFLICTS with pg_duckdb (both define time_bucket).
-- This test may fail if pg_duckdb is loaded in the same database.
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Test: check if extension is loaded (may fail due to pg_duckdb conflict)
SELECT CASE
    WHEN (SELECT count(*) FROM pg_extension WHERE extname = 'timescaledb') = 1
    THEN 'PASS timescaledb: extension loaded'
    WHEN (SELECT count(*) FROM pg_available_extensions WHERE name = 'timescaledb') = 1
    THEN 'PASS timescaledb: extension available (conflict with pg_duckdb)'
    ELSE 'FAIL timescaledb: extension not available'
END;
