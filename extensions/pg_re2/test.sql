-- re2 (pg_re2) integration tests
-- ClickHouse-compatible regex functions backed by Google RE2.

-- 1. Load / sanity: the extension's core matcher works (smoke test).
SELECT CASE
    WHEN re2match('hello world', 'h.*o') IS TRUE
     AND re2match('hello world', '^xyz') IS FALSE
    THEN 'PASS re2: re2match regex evaluation works'
    ELSE 'FAIL re2: re2match regex evaluation broken'
END;

-- 2. Extraction returns the first captured group.
SELECT CASE
    WHEN re2extract('2024-08-12', '([0-9]{4})') = '2024'
    THEN 'PASS re2: re2extract captures group'
    ELSE 'FAIL re2: re2extract broken'
END;

-- 3. Match counting.
SELECT CASE
    WHEN re2countmatches('a1b2c3', '[0-9]') = 3
     AND re2countmatches('no digits here', '[0-9]') = 0
    THEN 'PASS re2: re2countmatches works'
    ELSE 'FAIL re2: re2countmatches broken'
END;

-- 4. Works over a table column (integration with normal SQL evaluation).
CREATE TEMP TABLE re2_test_urls(u text);
INSERT INTO re2_test_urls VALUES ('http://a.com'), ('https://b.org'), ('ftp://c.net');
SELECT CASE
    WHEN (SELECT count(*) FROM re2_test_urls WHERE re2match(u, '^https?://')) = 2
    THEN 'PASS re2: re2match filters table rows correctly'
    ELSE 'FAIL re2: re2match table filtering broken'
END;
DROP TABLE re2_test_urls;
