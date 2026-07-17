-- prioritize integration tests.
CREATE EXTENSION IF NOT EXISTS prioritize;

SELECT CASE
    WHEN (SELECT count(*) FROM pg_extension WHERE extname = 'prioritize') = 1
    THEN 'PASS prioritize: extension loads'
    ELSE 'FAIL prioritize: extension loads'
END;

-- read the OS scheduling priority of the current backend
SELECT CASE
    WHEN get_backend_priority(pg_backend_pid()) IS NOT NULL
    THEN 'PASS prioritize: get_backend_priority returns a value'
    ELSE 'FAIL prioritize: get_backend_priority returns a value'
END;
