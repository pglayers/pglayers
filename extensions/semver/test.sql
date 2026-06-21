-- semver integration tests
CREATE EXTENSION IF NOT EXISTS semver;

-- Test: comparison
SELECT CASE
    WHEN '2.0.0'::semver > '1.9.9'::semver
    THEN 'PASS semver: major version comparison'
    ELSE 'FAIL semver: major version comparison'
END;

-- Test: sorting
SELECT CASE
    WHEN (SELECT array_agg(v ORDER BY v) FROM (VALUES ('1.0.0'::semver), ('0.9.0'::semver), ('1.1.0'::semver)) t(v))
         = ARRAY['0.9.0'::semver, '1.0.0'::semver, '1.1.0'::semver]
    THEN 'PASS semver: correct sort order'
    ELSE 'FAIL semver: correct sort order'
END;

-- Test: range query
CREATE TABLE test_semver (name text, version semver);
INSERT INTO test_semver VALUES ('a', '1.0.0'), ('b', '2.3.4'), ('c', '0.5.1');
SELECT CASE
    WHEN (SELECT count(*) FROM test_semver WHERE version >= '1.0.0'::semver) = 2
    THEN 'PASS semver: range query'
    ELSE 'FAIL semver: range query'
END;

DROP TABLE test_semver;
