-- pg_incremental integration tests
-- Requires pg_cron (DEPENDS): pipelines are scheduled as pg_cron jobs.
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_incremental;
SET client_min_messages = warning;

-- Test 1: Extension loads and its pipeline catalog is in place
SELECT CASE
    WHEN to_regclass('incremental.pipelines') IS NOT NULL
    THEN 'PASS pg_incremental: extension loaded with pipeline catalog'
    ELSE 'FAIL pg_incremental: extension loaded with pipeline catalog'
END;

CREATE SCHEMA pgi_test;
CREATE TABLE pgi_test.events (
    event_id bigint GENERATED ALWAYS AS IDENTITY,
    event_time timestamptz NOT NULL DEFAULT now(),
    client_id int NOT NULL
);
CREATE TABLE pgi_test.client_counts (
    client_id int PRIMARY KEY,
    event_count bigint NOT NULL
);
CREATE TABLE pgi_test.daily_counts (
    day timestamptz PRIMARY KEY,
    event_count bigint NOT NULL
);
INSERT INTO pgi_test.events (client_id)
SELECT s % 10 FROM generate_series(1, 100) s;

-- Test 2: Sequence pipeline processes the existing rows on creation
-- (the yearly schedule keeps pg_cron from running it during the test)
SELECT incremental.create_sequence_pipeline('pgi-sequence', 'pgi_test.events', $$
    INSERT INTO pgi_test.client_counts
    SELECT client_id, count(*) FROM pgi_test.events
    WHERE event_id BETWEEN $1 AND $2
    GROUP BY client_id
    ON CONFLICT (client_id) DO UPDATE
    SET event_count = client_counts.event_count + excluded.event_count
$$, schedule := '0 0 1 1 *');
SELECT CASE
    WHEN (SELECT sum(event_count) FROM pgi_test.client_counts) = 100
    THEN 'PASS pg_incremental: sequence pipeline processes existing rows'
    ELSE 'FAIL pg_incremental: sequence pipeline processes existing rows'
END;

-- Test 3: Later runs process only new rows, each exactly once
INSERT INTO pgi_test.events (client_id)
SELECT s % 10 FROM generate_series(1, 50) s;
CALL incremental.execute_pipeline('pgi-sequence');
CALL incremental.execute_pipeline('pgi-sequence');
SELECT CASE
    WHEN (SELECT sum(event_count) FROM pgi_test.client_counts) = 150
    THEN 'PASS pg_incremental: sequence pipeline processes new rows exactly once'
    ELSE 'FAIL pg_incremental: sequence pipeline processes new rows exactly once'
END;

-- Test 4: Time interval pipeline aggregates completed past intervals
INSERT INTO pgi_test.events (client_id, event_time)
SELECT 0, date_bin('1 day', now(), '2001-01-01') - interval '2 days' + interval '1 hour'
FROM generate_series(1, 7);
SELECT incremental.create_time_interval_pipeline('pgi-daily', '1 day', $$
    INSERT INTO pgi_test.daily_counts
    SELECT date_bin('1 day', event_time, '2001-01-01'), count(*)
    FROM pgi_test.events
    WHERE event_time >= $1 AND event_time < $2
    GROUP BY 1
$$, start_time := date_bin('1 day', now(), '2001-01-01') - interval '2 days',
    source_table_name := 'pgi_test.events', schedule := NULL);
SELECT CASE
    WHEN (SELECT sum(event_count) FROM pgi_test.daily_counts) = 7
    THEN 'PASS pg_incremental: time interval pipeline aggregates past intervals'
    ELSE 'FAIL pg_incremental: time interval pipeline aggregates past intervals'
END;

-- Test 5: Pipelines are scheduled in pg_cron and unscheduled when dropped
CREATE TABLE pgi_test.cron_jobs AS
SELECT count(*) AS scheduled FROM cron.job
WHERE jobname = 'pipeline:pgi-sequence'
  AND command = 'call incremental.execute_pipeline(''pgi-sequence'')';
SELECT incremental.drop_pipeline('pgi-sequence');
SELECT CASE
    WHEN (SELECT scheduled FROM pgi_test.cron_jobs) = 1
     AND NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'pipeline:pgi-sequence')
     AND NOT EXISTS (SELECT 1 FROM incremental.pipelines WHERE pipeline_name = 'pgi-sequence')
    THEN 'PASS pg_incremental: pipeline scheduled in pg_cron and unscheduled on drop'
    ELSE 'FAIL pg_incremental: pipeline scheduled in pg_cron and unscheduled on drop'
END;

-- Cleanup
SELECT incremental.drop_pipeline('pgi-daily');
DROP SCHEMA pgi_test CASCADE;
