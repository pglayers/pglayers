-- plprofiler integration tests
CREATE EXTENSION IF NOT EXISTS plprofiler;

-- Test: plprofiler_enable function exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc WHERE proname = 'plprofiler_enable') > 0
    THEN 'PASS plprofiler: plprofiler_enable function exists'
    ELSE 'FAIL plprofiler: plprofiler_enable function exists'
END;

-- Test: plprofiler_get_source function exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc WHERE proname = 'plprofiler_get_source') > 0
    THEN 'PASS plprofiler: plprofiler_get_source function exists'
    ELSE 'FAIL plprofiler: plprofiler_get_source function exists'
END;

-- Test: plprofiler_reset_local function exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc WHERE proname = 'plprofiler_reset_local') > 0
    THEN 'PASS plprofiler: plprofiler_reset_local function exists'
    ELSE 'FAIL plprofiler: plprofiler_reset_local function exists'
END;
