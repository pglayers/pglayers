-- pgvectorscale integration tests
-- Requires pgvector (installed via CASCADE)
CREATE EXTENSION IF NOT EXISTS vectorscale CASCADE;

-- Test: diskann index access method is available
SELECT CASE
    WHEN (SELECT count(*) FROM pg_am WHERE amname = 'diskann') > 0
    THEN 'PASS pgvectorscale: diskann access method available'
    ELSE 'FAIL pgvectorscale: diskann access method available'
END;

-- Test: create a table with vectors and build a diskann index
DO $$
BEGIN
    CREATE TABLE IF NOT EXISTS test_vectorscale (
        id serial PRIMARY KEY,
        embedding vector(3)
    );
    INSERT INTO test_vectorscale (embedding)
    VALUES ('[1,2,3]'), ('[4,5,6]'), ('[7,8,9]');
    CREATE INDEX ON test_vectorscale USING diskann (embedding vector_cosine_ops);
END $$;

SELECT CASE
    WHEN (SELECT count(*) FROM pg_indexes
          WHERE tablename = 'test_vectorscale' AND indexdef LIKE '%diskann%') > 0
    THEN 'PASS pgvectorscale: diskann index created'
    ELSE 'FAIL pgvectorscale: diskann index created'
END;

-- Test: vector similarity search using the diskann index
SELECT CASE
    WHEN (SELECT count(*) FROM (
          SELECT * FROM test_vectorscale
          ORDER BY embedding <=> '[1,2,3]' LIMIT 3
    ) sub) = 3
    THEN 'PASS pgvectorscale: diskann cosine search works'
    ELSE 'FAIL pgvectorscale: diskann cosine search works'
END;

-- Cleanup
DROP TABLE IF EXISTS test_vectorscale;
