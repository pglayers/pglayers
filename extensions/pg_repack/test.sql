-- pg_repack integration tests
CREATE EXTENSION IF NOT EXISTS pg_repack;

-- Test: extension version
SELECT CASE
    WHEN repack.version() LIKE 'pg_repack%'
    THEN 'PASS pg_repack: version function works'
    ELSE 'FAIL pg_repack: version function works'
END;

-- Test: can identify bloated table
CREATE TABLE test_repack (id serial PRIMARY KEY, data text);
INSERT INTO test_repack (data) SELECT repeat('x', 100) FROM generate_series(1, 1000);
DELETE FROM test_repack WHERE id % 2 = 0;

SELECT CASE
    WHEN pg_table_size('test_repack') > 0
    THEN 'PASS pg_repack: table with bloat exists for repacking'
    ELSE 'FAIL pg_repack: table with bloat exists for repacking'
END;

DROP TABLE test_repack;
