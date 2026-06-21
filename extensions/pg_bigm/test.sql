-- pg_bigm integration tests
CREATE EXTENSION IF NOT EXISTS pg_bigm;

-- Test: bigram search
CREATE TABLE test_bigm (id serial, content text);
INSERT INTO test_bigm (content) VALUES ('PostgreSQL'), ('full text search'), ('bigram index');
CREATE INDEX ON test_bigm USING gin (content gin_bigm_ops);

SELECT CASE
    WHEN (SELECT count(*) FROM test_bigm WHERE content LIKE '%text%') = 1
    THEN 'PASS pg_bigm: LIKE search with gin_bigm_ops'
    ELSE 'FAIL pg_bigm: LIKE search with gin_bigm_ops'
END;

-- Test: similarity function
SELECT CASE
    WHEN bigm_similarity('PostgreSQL', 'PostgreSQ') > 0.5
    THEN 'PASS pg_bigm: bigm_similarity function'
    ELSE 'FAIL pg_bigm: bigm_similarity function'
END;

DROP TABLE test_bigm;
