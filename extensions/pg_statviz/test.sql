-- pg_statviz (time-series statistics snapshots; schema "pgstatviz") tests.
CREATE EXTENSION IF NOT EXISTS pg_statviz;

SELECT CASE WHEN (SELECT count(*) FROM pg_extension WHERE extname='pg_statviz')=1
    THEN 'PASS pg_statviz: extension loads' ELSE 'FAIL pg_statviz: extension loads' END;

-- taking a snapshot returns a timestamp
SELECT CASE WHEN pgstatviz.snapshot() IS NOT NULL
    THEN 'PASS pg_statviz: snapshot() captures stats' ELSE 'FAIL pg_statviz: snapshot() captures stats' END;

-- and records it in the snapshots table
SELECT CASE WHEN (SELECT count(*) > 0 FROM pgstatviz.snapshots)
    THEN 'PASS pg_statviz: snapshot recorded' ELSE 'FAIL pg_statviz: snapshot recorded' END;
