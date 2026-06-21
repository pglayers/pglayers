-- timescaledb integration tests
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Test: create hypertable
CREATE TABLE test_ts (time timestamptz NOT NULL, value double precision);
SELECT create_hypertable('test_ts', 'time');

SELECT CASE
    WHEN (SELECT count(*) FROM timescaledb_information.hypertables WHERE hypertable_name = 'test_ts') = 1
    THEN 'PASS timescaledb: hypertable created'
    ELSE 'FAIL timescaledb: hypertable created'
END;

-- Test: insert and query
INSERT INTO test_ts VALUES
    (now() - interval '1 hour', 10.5),
    (now() - interval '30 min', 20.3),
    (now(), 15.8);

SELECT CASE
    WHEN (SELECT count(*) FROM test_ts) = 3
    THEN 'PASS timescaledb: data inserted into hypertable'
    ELSE 'FAIL timescaledb: data inserted into hypertable'
END;

-- Test: time_bucket aggregation
SELECT CASE
    WHEN (SELECT count(*) FROM (
        SELECT time_bucket('1 hour', time) AS bucket, avg(value)
        FROM test_ts GROUP BY bucket
    ) t) >= 1
    THEN 'PASS timescaledb: time_bucket aggregation'
    ELSE 'FAIL timescaledb: time_bucket aggregation'
END;

DROP TABLE test_ts;
