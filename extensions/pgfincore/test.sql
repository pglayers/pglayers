-- pgfincore integration tests
CREATE EXTENSION IF NOT EXISTS pgfincore;

-- Test: pgfincore function exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc WHERE proname = 'pgfincore') > 0
    THEN 'PASS pgfincore: pgfincore function exists'
    ELSE 'FAIL pgfincore: pgfincore function exists'
END;

-- Test: pgsysconf function exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc WHERE proname = 'pgsysconf') > 0
    THEN 'PASS pgfincore: pgsysconf function exists'
    ELSE 'FAIL pgfincore: pgsysconf function exists'
END;

-- Test: pgsysconf returns valid page size
SELECT CASE
    WHEN (SELECT (pgsysconf()).os_page_size) > 0
    THEN 'PASS pgfincore: pgsysconf returns valid page size'
    ELSE 'FAIL pgfincore: pgsysconf returns valid page size'
END;
