-- pg_ivm integration tests
CREATE EXTENSION IF NOT EXISTS pg_ivm;

-- Test: function exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc WHERE proname = 'create_immv') > 0
    THEN 'PASS pg_ivm: create_immv function exists'
    ELSE 'FAIL pg_ivm: create_immv function exists'
END;

-- Test: create and auto-update an IMMV
CREATE TABLE test_ivm_src (product text, amount int);
INSERT INTO test_ivm_src VALUES ('A', 100), ('B', 200);
SELECT pgivm.create_immv('test_ivm_mv', 'SELECT product, sum(amount) AS total FROM test_ivm_src GROUP BY product');

SELECT CASE
    WHEN (SELECT total FROM test_ivm_mv WHERE product = 'A') = 100
    THEN 'PASS pg_ivm: IMMV initial data correct'
    ELSE 'FAIL pg_ivm: IMMV initial data correct'
END;

-- Insert and check auto-update
INSERT INTO test_ivm_src VALUES ('A', 50);
SELECT CASE
    WHEN (SELECT total FROM test_ivm_mv WHERE product = 'A') = 150
    THEN 'PASS pg_ivm: IMMV auto-updated after INSERT'
    ELSE 'FAIL pg_ivm: IMMV auto-updated after INSERT'
END;

DROP TABLE test_ivm_mv;
DROP TABLE test_ivm_src;
