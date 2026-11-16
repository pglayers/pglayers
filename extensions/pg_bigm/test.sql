-- pg_bigm integration tests
CREATE EXTENSION IF NOT EXISTS pg_bigm;

SELECT CASE
    WHEN bigm_similarity('PostgreSQL', 'PostgreSQL') = 1
      AND bigm_similarity('日本語', '日本語') = 1
    THEN 'PASS pg_bigm: extension loads and identical strings match'
    ELSE 'FAIL pg_bigm: extension loads and identical strings match'
END;

-- Test: bigram search
CREATE TABLE test_bigm (id serial, content text);
INSERT INTO test_bigm (content) VALUES
    ('PostgreSQL'), ('full text search'), ('bigram index'), ('日本語の全文検索');
CREATE INDEX test_bigm_content_idx ON test_bigm USING gin (content gin_bigm_ops);
SET enable_seqscan = off;

SELECT CASE
    WHEN (SELECT count(*) FROM test_bigm WHERE content LIKE '%text%') = 1
      AND (SELECT count(*) FROM test_bigm WHERE content LIKE '%全文%') = 1
    THEN 'PASS pg_bigm: LIKE search with gin_bigm_ops'
    ELSE 'FAIL pg_bigm: LIKE search with gin_bigm_ops'
END;

-- Test: similarity function
SELECT CASE
    WHEN bigm_similarity('PostgreSQL', 'PostgreSQ') > 0.5
    THEN 'PASS pg_bigm: bigm_similarity function'
    ELSE 'FAIL pg_bigm: bigm_similarity function'
END;

-- Exercise the buffer-lock and transient TupleDesc APIs changed in PG19.
SELECT CASE
    WHEN pages >= 0 AND tuples >= 0
    THEN 'PASS pg_bigm: GIN pending-list statistics use compatible PostgreSQL APIs'
    ELSE 'FAIL pg_bigm: GIN pending-list statistics use compatible PostgreSQL APIs'
END FROM pg_gin_pending_stats('test_bigm_content_idx');

RESET enable_seqscan;
DROP TABLE test_bigm;
