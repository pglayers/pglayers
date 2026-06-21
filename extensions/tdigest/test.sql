-- tdigest integration tests
CREATE EXTENSION IF NOT EXISTS tdigest;

-- Test: median of uniform distribution
SELECT CASE
    WHEN abs(tdigest_percentile(g, 100, 0.5) - 500) < 20
    THEN 'PASS tdigest: median of 1..1000 close to 500'
    ELSE 'FAIL tdigest: median of 1..1000 close to 500'
END
FROM generate_series(1, 1000) g;

-- Test: p99 is near the top
SELECT CASE
    WHEN tdigest_percentile(g, 100, 0.99) > 980
    THEN 'PASS tdigest: p99 of 1..1000 is above 980'
    ELSE 'FAIL tdigest: p99 of 1..1000 is above 980'
END
FROM generate_series(1, 1000) g;
