-- pg_wait_sampling integration tests
CREATE EXTENSION IF NOT EXISTS pg_wait_sampling;

-- Test: pg_wait_sampling_profile view exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_views WHERE viewname = 'pg_wait_sampling_profile') > 0
    THEN 'PASS pg_wait_sampling: pg_wait_sampling_profile view exists'
    ELSE 'FAIL pg_wait_sampling: pg_wait_sampling_profile view exists'
END;

-- Test: can query the profile view without error
SELECT CASE
    WHEN (SELECT count(*) FROM pg_wait_sampling_profile) >= 0
    THEN 'PASS pg_wait_sampling: profile view is queryable'
    ELSE 'FAIL pg_wait_sampling: profile view is queryable'
END;

-- Test: pg_wait_sampling_reset_profile function exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc WHERE proname = 'pg_wait_sampling_reset_profile') > 0
    THEN 'PASS pg_wait_sampling: reset_profile function exists'
    ELSE 'FAIL pg_wait_sampling: reset_profile function exists'
END;
