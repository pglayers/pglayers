-- plv8 integration tests
CREATE EXTENSION IF NOT EXISTS plv8;

-- Test: basic JavaScript function
CREATE OR REPLACE FUNCTION test_plv8_add(a int, b int) RETURNS int AS $$
    return a + b;
$$ LANGUAGE plv8;

SELECT CASE
    WHEN test_plv8_add(2, 3) = 5
    THEN 'PASS plv8: basic JS function'
    ELSE 'FAIL plv8: basic JS function'
END;

-- Test: JSON manipulation
CREATE OR REPLACE FUNCTION test_plv8_json(data jsonb) RETURNS text AS $$
    var obj = JSON.parse(data);
    return obj.name.toUpperCase();
$$ LANGUAGE plv8;

SELECT CASE
    WHEN test_plv8_json('{"name": "hello"}') = 'HELLO'
    THEN 'PASS plv8: JSON manipulation in JS'
    ELSE 'FAIL plv8: JSON manipulation in JS'
END;

-- Test: array handling
CREATE OR REPLACE FUNCTION test_plv8_sum(arr int[]) RETURNS int AS $$
    return arr.reduce(function(a,b) { return a+b; }, 0);
$$ LANGUAGE plv8;

SELECT CASE
    WHEN test_plv8_sum(ARRAY[1,2,3,4,5]) = 15
    THEN 'PASS plv8: array sum in JS'
    ELSE 'FAIL plv8: array sum in JS'
END;

DROP FUNCTION test_plv8_add(int, int);
DROP FUNCTION test_plv8_json(jsonb);
DROP FUNCTION test_plv8_sum(int[]);
