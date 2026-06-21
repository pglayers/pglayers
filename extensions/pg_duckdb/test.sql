-- pg_duckdb integration tests
CREATE EXTENSION IF NOT EXISTS pg_duckdb;

-- Test: extension loaded
SELECT CASE
    WHEN (SELECT count(*) FROM pg_extension WHERE extname = 'pg_duckdb') = 1
    THEN 'PASS pg_duckdb: extension loaded'
    ELSE 'FAIL pg_duckdb: extension loaded'
END;

-- Test: DuckDB execution
SELECT CASE
    WHEN (SELECT duckdb.query($$ SELECT 42 AS answer $$)::text) IS NOT NULL
    THEN 'PASS pg_duckdb: DuckDB query execution'
    ELSE 'FAIL pg_duckdb: DuckDB query execution'
END;
