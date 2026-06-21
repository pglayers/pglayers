-- hll integration tests
CREATE EXTENSION IF NOT EXISTS hll;

-- Test: basic cardinality estimation
SELECT CASE
    WHEN abs(hll_cardinality(hll_add_agg(hll_hash_integer(g))) - 1000) < 50
    THEN 'PASS hll: cardinality estimate within 5% for 1000 elements'
    ELSE 'FAIL hll: cardinality estimate within 5% for 1000 elements'
END
FROM generate_series(1, 1000) g;

-- Test: union of two sets
SELECT CASE
    WHEN hll_cardinality(
        hll_union(
            (SELECT hll_add_agg(hll_hash_integer(g)) FROM generate_series(1, 500) g),
            (SELECT hll_add_agg(hll_hash_integer(g)) FROM generate_series(400, 900) g)
        )
    ) BETWEEN 800 AND 1000
    THEN 'PASS hll: union cardinality correct'
    ELSE 'FAIL hll: union cardinality correct'
END;

-- Test: aggregation in table
CREATE TABLE test_hll (page text, visitors hll);
INSERT INTO test_hll SELECT '/home', hll_add_agg(hll_hash_integer(g)) FROM generate_series(1, 500) g;
SELECT CASE
    WHEN (SELECT hll_cardinality(visitors) FROM test_hll WHERE page = '/home') BETWEEN 450 AND 550
    THEN 'PASS hll: stored HLL cardinality'
    ELSE 'FAIL hll: stored HLL cardinality'
END;

DROP TABLE test_hll;
