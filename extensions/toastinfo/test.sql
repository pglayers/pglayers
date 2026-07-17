-- toastinfo (inspect TOAST storage of values) integration tests.
CREATE EXTENSION IF NOT EXISTS toastinfo;

SELECT CASE
    WHEN (SELECT count(*) FROM pg_extension WHERE extname = 'toastinfo') = 1
    THEN 'PASS toastinfo: extension loads'
    ELSE 'FAIL toastinfo: extension loads'
END;

-- pg_toastinfo describes a large (toasted) value
CREATE TEMP TABLE toastinfo_test (id int, v text);
INSERT INTO toastinfo_test VALUES (1, repeat('x', 10000));

SELECT CASE
    WHEN (SELECT pg_toastinfo(v) FROM toastinfo_test WHERE id = 1) IS NOT NULL
    THEN 'PASS toastinfo: pg_toastinfo returns storage info'
    ELSE 'FAIL toastinfo: pg_toastinfo returns storage info'
END;

DROP TABLE toastinfo_test;
