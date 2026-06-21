-- pgvector integration tests
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE test_pgvector (id serial PRIMARY KEY, embedding vector(3));
INSERT INTO test_pgvector (embedding) VALUES ('[1,2,3]'), ('[4,5,6]'), ('[7,8,9]');

-- Test: nearest neighbor search
SELECT CASE
    WHEN (SELECT id FROM test_pgvector ORDER BY embedding <-> '[1,2,3]' LIMIT 1) = 1
    THEN 'PASS pgvector: nearest neighbor returns closest vector'
    ELSE 'FAIL pgvector: nearest neighbor returns closest vector'
END;

-- Test: HNSW index creation and use
CREATE INDEX ON test_pgvector USING hnsw (embedding vector_l2_ops);
SELECT CASE
    WHEN (SELECT count(*) FROM pg_indexes WHERE tablename = 'test_pgvector' AND indexdef LIKE '%hnsw%') = 1
    THEN 'PASS pgvector: HNSW index created'
    ELSE 'FAIL pgvector: HNSW index created'
END;

-- Test: cosine distance operator
SELECT CASE
    WHEN ('[1,0,0]'::vector <=> '[0,1,0]'::vector) > 0.9
    THEN 'PASS pgvector: cosine distance between orthogonal vectors'
    ELSE 'FAIL pgvector: cosine distance between orthogonal vectors'
END;

DROP TABLE test_pgvector;
