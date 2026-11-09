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
    WHEN (SELECT r['answer']::int FROM duckdb.query('SELECT 42 AS answer') r) = 42
    THEN 'PASS pg_duckdb: DuckDB query execution'
    ELSE 'FAIL pg_duckdb: DuckDB query execution'
END;

-- Test: aggregate multiple rows inside DuckDB, not just load the module
SELECT CASE
    WHEN (SELECT r['total']::bigint
          FROM duckdb.query('SELECT sum(i) AS total FROM range(1, 6) t(i)') r) = 15
    THEN 'PASS pg_duckdb: DuckDB aggregation'
    ELSE 'FAIL pg_duckdb: DuckDB aggregation'
END;
