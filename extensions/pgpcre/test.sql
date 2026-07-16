-- pgpcre integration tests.
CREATE EXTENSION IF NOT EXISTS pgpcre;

SELECT CASE
    WHEN (SELECT count(*) FROM pg_extension WHERE extname = 'pgpcre') = 1
    THEN 'PASS pgpcre: extension loads'
    ELSE 'FAIL pgpcre: extension loads'
END;

-- PCRE match operator
SELECT CASE
    WHEN 'foobar' ~ 'f.ob'::pcre
    THEN 'PASS pgpcre: pattern matches via ~ operator'
    ELSE 'FAIL pgpcre: pattern matches via ~ operator'
END;

-- capture group extraction
SELECT CASE
    WHEN pcre_match('([0-9]+)', 'abc123') = '123'
    THEN 'PASS pgpcre: pcre_match extracts capture group'
    ELSE 'FAIL pgpcre: pcre_match extracts capture group'
END;

-- non-match returns false
SELECT CASE
    WHEN NOT ('abc' ~ '[0-9]+'::pcre)
    THEN 'PASS pgpcre: non-matching pattern is false'
    ELSE 'FAIL pgpcre: non-matching pattern is false'
END;
