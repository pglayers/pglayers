-- Test TimescaleDB in a private schema: pg_duckdb installs overlapping
-- time_bucket functions in public. Roll back all fixtures after the checks.
BEGIN;
CREATE SCHEMA pglayers_timescaledb_test;
CREATE EXTENSION IF NOT EXISTS timescaledb WITH SCHEMA pglayers_timescaledb_test;

SELECT CASE
    WHEN (SELECT count(*) FROM pg_extension WHERE extname = 'timescaledb') = 1
    THEN 'PASS timescaledb: extension loads'
    ELSE 'FAIL timescaledb: extension loads'
END;

-- Respect an extension that was already installed in a different schema.
SELECT n.nspname AS timescaledb_schema
FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace
WHERE e.extname = 'timescaledb' \gset

SELECT CASE
    WHEN :"timescaledb_schema".time_bucket(INTERVAL '1 hour', TIMESTAMPTZ '2026-01-01 01:23:00+00')
         = TIMESTAMPTZ '2026-01-01 01:00:00+00'
    THEN 'PASS timescaledb: hourly time bucket'
    ELSE 'FAIL timescaledb: hourly time bucket'
END;

CREATE TABLE pglayers_timescaledb_test.metrics (recorded_at timestamptz NOT NULL, reading int);
SELECT :"timescaledb_schema".create_hypertable('pglayers_timescaledb_test.metrics', 'recorded_at');
INSERT INTO pglayers_timescaledb_test.metrics VALUES
    ('2026-01-01 01:23:00+00', 42), ('2026-01-01 02:34:00+00', 58);

SELECT CASE
    WHEN EXISTS (SELECT 1 FROM timescaledb_information.hypertables
                 WHERE hypertable_schema = 'pglayers_timescaledb_test' AND hypertable_name = 'metrics')
         AND (SELECT count(*) = 2 AND sum(reading) = 100 FROM pglayers_timescaledb_test.metrics)
    THEN 'PASS timescaledb: hypertable stores and aggregates rows'
    ELSE 'FAIL timescaledb: hypertable stores and aggregates rows'
END;
ROLLBACK;
