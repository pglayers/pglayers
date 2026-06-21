-- prefix integration tests
CREATE EXTENSION IF NOT EXISTS prefix;

-- Test: prefix range type works
SELECT CASE
    WHEN '123'::prefix_range @> '1234567890'
    THEN 'PASS prefix: prefix_range contains operator'
    ELSE 'FAIL prefix: prefix_range contains operator'
END;

-- Test: prefix range comparison
SELECT CASE
    WHEN '123'::prefix_range <> '124'::prefix_range
    THEN 'PASS prefix: prefix_range inequality'
    ELSE 'FAIL prefix: prefix_range inequality'
END;

-- Test: GiST index creation
CREATE TABLE test_prefix (p prefix_range);
INSERT INTO test_prefix VALUES ('33'), ('331'), ('332');
CREATE INDEX ON test_prefix USING gist (p);
SELECT CASE
    WHEN (SELECT count(*) FROM pg_indexes WHERE tablename = 'test_prefix') = 1
    THEN 'PASS prefix: GiST index created'
    ELSE 'FAIL prefix: GiST index created'
END;

DROP TABLE test_prefix;
