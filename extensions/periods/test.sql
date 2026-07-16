-- periods integration tests.
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS periods;

SELECT CASE
    WHEN (SELECT count(*) FROM pg_extension WHERE extname = 'periods') = 1
    THEN 'PASS periods: extension loads'
    ELSE 'FAIL periods: extension loads'
END;

-- register an application-time period on a table
CREATE TABLE periods_test (id int, valid_from date, valid_to date);
SELECT periods.add_period('periods_test', 'validity', 'valid_from', 'valid_to');

SELECT CASE
    WHEN (SELECT count(*) = 1 FROM periods.periods
          WHERE table_name = 'periods_test'::regclass AND period_name = 'validity')
    THEN 'PASS periods: add_period registers the period'
    ELSE 'FAIL periods: add_period registers the period'
END;

DROP TABLE periods_test;
