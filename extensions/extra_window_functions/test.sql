-- extra_window_functions integration tests.
CREATE EXTENSION IF NOT EXISTS extra_window_functions;

-- Load/sanity
SELECT CASE
    WHEN (SELECT count(*) FROM pg_extension WHERE extname = 'extra_window_functions') = 1
    THEN 'PASS extra_window_functions: extension loads'
    ELSE 'FAIL extra_window_functions: extension loads'
END;

-- last_value_ignore_nulls returns the last non-NULL value in the frame
SELECT CASE
    WHEN (
        SELECT last_value_ignore_nulls(x)
                 OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
        FROM (VALUES (1, 10), (2, NULL::int)) t(id, x)
        ORDER BY id DESC
        LIMIT 1
    ) = 10
    THEN 'PASS extra_window_functions: last_value_ignore_nulls skips NULLs'
    ELSE 'FAIL extra_window_functions: last_value_ignore_nulls skips NULLs'
END;
