-- pg_similarity integration tests
CREATE EXTENSION IF NOT EXISTS pg_similarity;

-- Test: Levenshtein similarity
SELECT CASE
    WHEN lev('hello', 'hallo') > 0
    THEN 'PASS pg_similarity: levenshtein similarity works'
    ELSE 'FAIL pg_similarity: levenshtein similarity works'
END;

-- Test: Cosine similarity
SELECT CASE
    WHEN cosine('hello world', 'hello world') > 0.99
    THEN 'PASS pg_similarity: cosine similarity identical strings'
    ELSE 'FAIL pg_similarity: cosine similarity identical strings'
END;

-- Test: Jaccard similarity
SELECT CASE
    WHEN jaro('martha', 'marhta') > 0.9
    THEN 'PASS pg_similarity: jaro similarity works'
    ELSE 'FAIL pg_similarity: jaro similarity works'
END;
