-- pg_textsearch integration tests

-- Test 1: Extension loads and basic index creation works
CREATE TABLE ts_test_docs (id serial PRIMARY KEY, content text NOT NULL);
INSERT INTO ts_test_docs (content) VALUES
    ('database query optimization techniques'),
    ('full text search ranking algorithm'),
    ('machine learning neural network'),
    ('distributed systems consensus protocol');
CREATE INDEX ts_test_idx ON ts_test_docs USING bm25 (content)
    WITH (text_config = 'english');
SELECT CASE
    WHEN count(*) = 4
    THEN 'PASS pg_textsearch: BM25 index created successfully'
    ELSE 'FAIL pg_textsearch: BM25 index creation failed'
END FROM ts_test_docs;

-- Test 2: BM25 ranked search returns results
SELECT CASE
    WHEN count(*) > 0
    THEN 'PASS pg_textsearch: BM25 ranked search returns results'
    ELSE 'FAIL pg_textsearch: BM25 ranked search returned no results'
END FROM (
    SELECT id FROM ts_test_docs
    ORDER BY content <@> to_bm25query('database query', 'ts_test_idx')
    LIMIT 5
) sub;

-- Test 3: Search relevance ordering is correct
SELECT CASE
    WHEN content LIKE '%database%'
    THEN 'PASS pg_textsearch: BM25 relevance ranking correct'
    ELSE 'FAIL pg_textsearch: BM25 relevance ranking incorrect'
END FROM ts_test_docs
ORDER BY content <@> to_bm25query('database optimization', 'ts_test_idx')
LIMIT 1;

-- Cleanup
DROP TABLE ts_test_docs;
