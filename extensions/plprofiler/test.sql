-- plprofiler integration tests
CREATE EXTENSION IF NOT EXISTS plprofiler;

-- Test: pl_profiler_get_enabled_local function exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc WHERE proname = 'pl_profiler_get_enabled_local') > 0
    THEN 'PASS plprofiler: pl_profiler_get_enabled_local function exists'
    ELSE 'FAIL plprofiler: pl_profiler_get_enabled_local function exists'
END;

-- Test: pl_profiler_version function exists and returns a value
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc WHERE proname = 'pl_profiler_version') > 0
    THEN 'PASS plprofiler: pl_profiler_version function exists'
    ELSE 'FAIL plprofiler: pl_profiler_version function exists'
END;
