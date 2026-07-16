-- pgnodemx integration tests (requires shared_preload_libraries = 'pgnodemx').
CREATE EXTENSION IF NOT EXISTS pgnodemx;

SELECT CASE
    WHEN (SELECT count(*) FROM pg_extension WHERE extname = 'pgnodemx') = 1
    THEN 'PASS pgnodemx: extension loads'
    ELSE 'FAIL pgnodemx: extension loads'
END;

-- cgroup mode is reported (legacy / unified / etc.)
SELECT CASE
    WHEN cgroup_mode() IS NOT NULL
    THEN 'PASS pgnodemx: cgroup_mode() returns a value'
    ELSE 'FAIL pgnodemx: cgroup_mode() returns a value'
END;

-- environment variable readout works
SELECT CASE
    WHEN envvar_text('PGDATA') IS NOT NULL
    THEN 'PASS pgnodemx: envvar_text reads an environment variable'
    ELSE 'FAIL pgnodemx: envvar_text reads an environment variable'
END;
