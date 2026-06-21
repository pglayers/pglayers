-- pgtt integration tests
CREATE EXTENSION IF NOT EXISTS pgtt;

-- Test: pgtt_is_global_temporary function exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc WHERE proname = 'pgtt_is_global_temporary') > 0
    THEN 'PASS pgtt: pgtt_is_global_temporary function exists'
    ELSE 'FAIL pgtt: pgtt_is_global_temporary function exists'
END;

-- Test: create a global temporary table and verify it exists
CREATE GLOBAL TEMPORARY TABLE test_gtt (id int, val text) ON COMMIT DELETE ROWS;
SELECT CASE
    WHEN pgtt_is_global_temporary('test_gtt'::regclass)
    THEN 'PASS pgtt: global temporary table created and recognized'
    ELSE 'FAIL pgtt: global temporary table created and recognized'
END;

-- Test: insert and verify on-commit behavior
INSERT INTO test_gtt VALUES (1, 'hello');
SELECT CASE
    WHEN (SELECT count(*) FROM test_gtt) = 1
    THEN 'PASS pgtt: data visible within transaction'
    ELSE 'FAIL pgtt: data visible within transaction'
END;

DROP TABLE test_gtt;
