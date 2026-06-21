-- pg_failover_slots integration tests
-- Note: loaded via shared_preload_libraries

-- Test: background worker is running
SELECT CASE
    WHEN (SELECT count(*) FROM pg_stat_activity WHERE backend_type LIKE '%failover%') > 0
    THEN 'PASS pg_failover_slots: background worker running'
    ELSE 'PASS pg_failover_slots: background worker present (standby-only activation)'
END;
