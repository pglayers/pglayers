-- orafce integration tests
CREATE EXTENSION IF NOT EXISTS orafce;

-- Test: NVL
SELECT CASE
    WHEN oracle.nvl(NULL::text, 'fallback') = 'fallback'
    THEN 'PASS orafce: NVL with NULL'
    ELSE 'FAIL orafce: NVL with NULL'
END;

-- Test: DECODE
SELECT CASE
    WHEN oracle.decode(2, 1,'one', 2,'two', 3,'three') = 'two'
    THEN 'PASS orafce: DECODE function'
    ELSE 'FAIL orafce: DECODE function'
END;

-- Test: last_day
SELECT CASE
    WHEN oracle.last_day('2026-02-15'::date) = '2026-02-28'::date
    THEN 'PASS orafce: last_day of February'
    ELSE 'FAIL orafce: last_day of February'
END;

-- Test: LPAD
SELECT CASE
    WHEN oracle.lpad('hi', 5, '*') = '***hi'
    THEN 'PASS orafce: LPAD padding'
    ELSE 'FAIL orafce: LPAD padding'
END;
