-- pg_background (run queries in background workers) tests.
CREATE EXTENSION IF NOT EXISTS pg_background;

SELECT CASE WHEN (SELECT count(*) FROM pg_extension WHERE extname='pg_background')=1
    THEN 'PASS pg_background: extension loads' ELSE 'FAIL pg_background: extension loads' END;

-- launch a query in a background worker and read back its result
SELECT CASE WHEN (
        WITH h AS (SELECT pg_background_launch('SELECT 42') AS x)
        SELECT v FROM h, pg_background_result((h.x).pid, (h.x).cookie) AS r(v int)
    ) = 42
    THEN 'PASS pg_background: launch + result round-trip'
    ELSE 'FAIL pg_background: launch + result round-trip'
END;
