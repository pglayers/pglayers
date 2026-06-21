-- rum integration tests
CREATE EXTENSION IF NOT EXISTS rum;

-- Test: rum index on tsvector
CREATE TABLE test_rum (id serial, body text, body_tsv tsvector);
INSERT INTO test_rum (body, body_tsv) VALUES
    ('PostgreSQL is great', to_tsvector('PostgreSQL is great')),
    ('Full text search', to_tsvector('Full text search')),
    ('RUM index ordering', to_tsvector('RUM index ordering'));
CREATE INDEX ON test_rum USING rum (body_tsv rum_tsvector_ops);

SELECT CASE
    WHEN (SELECT count(*) FROM pg_indexes WHERE indexdef LIKE '%rum%') > 0
    THEN 'PASS rum: RUM index created'
    ELSE 'FAIL rum: RUM index created'
END;

-- Test: ordered search using rum
SELECT CASE
    WHEN (SELECT id FROM test_rum WHERE body_tsv @@ to_tsquery('PostgreSQL') ORDER BY body_tsv <=> to_tsquery('PostgreSQL') LIMIT 1) = 1
    THEN 'PASS rum: ordered full text search'
    ELSE 'FAIL rum: ordered full text search'
END;

DROP TABLE test_rum;
