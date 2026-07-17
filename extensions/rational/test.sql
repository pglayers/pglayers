-- rational (pg_rational) integration tests.
CREATE EXTENSION IF NOT EXISTS pg_rational;

-- Load/sanity
SELECT CASE
    WHEN (SELECT count(*) FROM pg_extension WHERE extname = 'pg_rational') = 1
    THEN 'PASS rational: extension loads'
    ELSE 'FAIL rational: extension loads'
END;

-- exact rational arithmetic: 1/3 + 1/6 = 1/2
SELECT CASE
    WHEN ('1/3'::rational + '1/6'::rational) = '1/2'::rational
    THEN 'PASS rational: 1/3 + 1/6 = 1/2'
    ELSE 'FAIL rational: 1/3 + 1/6 = 1/2'
END;

-- equality is by value (2/4 = 1/2)
SELECT CASE
    WHEN '2/4'::rational = '1/2'::rational
    THEN 'PASS rational: 2/4 equals 1/2 by value'
    ELSE 'FAIL rational: 2/4 equals 1/2 by value'
END;

-- ordering
SELECT CASE
    WHEN '1/3'::rational < '1/2'::rational
    THEN 'PASS rational: 1/3 < 1/2 ordering'
    ELSE 'FAIL rational: 1/3 < 1/2 ordering'
END;
