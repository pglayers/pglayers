-- pg_roaringbitmap integration tests
CREATE EXTENSION IF NOT EXISTS roaringbitmap;

-- Test: create and populate bitmap
SELECT CASE
    WHEN rb_cardinality(rb_build(ARRAY[1,2,3,4,5]::int[])) = 5
    THEN 'PASS pg_roaringbitmap: build bitmap and count'
    ELSE 'FAIL pg_roaringbitmap: build bitmap and count'
END;

-- Test: bitmap operations (AND, OR)
SELECT CASE
    WHEN rb_cardinality(rb_and(rb_build(ARRAY[1,2,3]::int[]), rb_build(ARRAY[2,3,4]::int[]))) = 2
    THEN 'PASS pg_roaringbitmap: AND intersection'
    ELSE 'FAIL pg_roaringbitmap: AND intersection'
END;

SELECT CASE
    WHEN rb_cardinality(rb_or(rb_build(ARRAY[1,2,3]::int[]), rb_build(ARRAY[3,4,5]::int[]))) = 5
    THEN 'PASS pg_roaringbitmap: OR union'
    ELSE 'FAIL pg_roaringbitmap: OR union'
END;
