-- temporal_tables integration tests
CREATE EXTENSION IF NOT EXISTS temporal_tables;

-- Test: versioning trigger function exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc WHERE proname = 'versioning') > 0
    THEN 'PASS temporal_tables: versioning function exists'
    ELSE 'FAIL temporal_tables: versioning function exists'
END;

-- Test: set up temporal table
CREATE TABLE test_temporal (
    id serial PRIMARY KEY,
    name text,
    sys_period tstzrange NOT NULL DEFAULT tstzrange(now(), null)
);
CREATE TABLE test_temporal_history (LIKE test_temporal);

CREATE TRIGGER versioning_trigger
    BEFORE INSERT OR UPDATE OR DELETE ON test_temporal
    FOR EACH ROW EXECUTE PROCEDURE versioning('sys_period', 'test_temporal_history', true);

INSERT INTO test_temporal (name) VALUES ('original');
UPDATE test_temporal SET name = 'modified' WHERE id = 1;

SELECT CASE
    WHEN (SELECT count(*) FROM test_temporal_history) = 1
    THEN 'PASS temporal_tables: history row created on update'
    ELSE 'FAIL temporal_tables: history row created on update'
END;

DROP TABLE test_temporal_history;
DROP TABLE test_temporal;
