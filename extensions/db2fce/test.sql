-- db2fce (DB2 compatibility functions, installed in the db2 schema) tests.
CREATE EXTENSION IF NOT EXISTS db2fce;

SELECT CASE WHEN (SELECT count(*) FROM pg_extension WHERE extname='db2fce')=1
    THEN 'PASS db2fce: extension loads' ELSE 'FAIL db2fce: extension loads' END;

SELECT CASE WHEN db2.day(DATE '2020-03-15') = 15
    THEN 'PASS db2fce: day() extracts day of month' ELSE 'FAIL db2fce: day() extracts day of month' END;

SELECT CASE WHEN db2.months_between(DATE '2020-03-15', DATE '2020-01-15') = 2
    THEN 'PASS db2fce: months_between()' ELSE 'FAIL db2fce: months_between()' END;
