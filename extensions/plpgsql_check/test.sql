-- plpgsql_check integration tests
CREATE EXTENSION IF NOT EXISTS plpgsql_check;

-- Test: validate a correct function
CREATE OR REPLACE FUNCTION test_good() RETURNS int AS $$
BEGIN RETURN 42; END;
$$ LANGUAGE plpgsql;

SELECT CASE
    WHEN (SELECT count(*) FROM plpgsql_check_function('test_good()')) = 0
    THEN 'PASS plpgsql_check: valid function passes check'
    ELSE 'FAIL plpgsql_check: valid function passes check'
END;

-- Test: detect error in a function
CREATE OR REPLACE FUNCTION test_bad() RETURNS int AS $$
BEGIN RETURN nonexistent_column; END;
$$ LANGUAGE plpgsql;

SELECT CASE
    WHEN (SELECT count(*) FROM plpgsql_check_function('test_bad()')) > 0
    THEN 'PASS plpgsql_check: invalid function detected'
    ELSE 'FAIL plpgsql_check: invalid function detected'
END;

DROP FUNCTION test_good();
DROP FUNCTION test_bad();
