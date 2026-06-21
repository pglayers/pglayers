-- pg_cron integration tests
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Test: schedule a job
SELECT CASE
    WHEN cron.schedule('test_job_1', '*/5 * * * *', 'SELECT 1') > 0
    THEN 'PASS pg_cron: schedule job'
    ELSE 'FAIL pg_cron: schedule job'
END;

-- Test: job appears in cron.job
SELECT CASE
    WHEN (SELECT count(*) FROM cron.job WHERE jobname = 'test_job_1') = 1
    THEN 'PASS pg_cron: job visible in cron.job table'
    ELSE 'FAIL pg_cron: job visible in cron.job table'
END;

-- Test: unschedule
SELECT CASE
    WHEN cron.unschedule('test_job_1')
    THEN 'PASS pg_cron: unschedule job'
    ELSE 'FAIL pg_cron: unschedule job'
END;
