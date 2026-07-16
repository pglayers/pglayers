-- icu_ext (ICU functions: names, transforms, spellout, collation) tests.
CREATE EXTENSION IF NOT EXISTS icu_ext;

SELECT CASE
    WHEN (SELECT count(*) FROM pg_extension WHERE extname = 'icu_ext') = 1
    THEN 'PASS icu_ext: extension loads'
    ELSE 'FAIL icu_ext: extension loads'
END;

-- Unicode character name lookup
SELECT CASE
    WHEN icu_char_name('A') = 'LATIN CAPITAL LETTER A'
    THEN 'PASS icu_ext: icu_char_name resolves a codepoint name'
    ELSE 'FAIL icu_ext: icu_char_name resolves a codepoint name'
END;

-- transliteration (Latin-ASCII fold)
SELECT CASE
    WHEN icu_transform('Æ', 'Latin-ASCII') = 'AE'
    THEN 'PASS icu_ext: icu_transform folds to ASCII'
    ELSE 'FAIL icu_ext: icu_transform folds to ASCII'
END;

-- number spellout
SELECT CASE
    WHEN icu_number_spellout(42, 'en') = 'forty-two'
    THEN 'PASS icu_ext: icu_number_spellout in English'
    ELSE 'FAIL icu_ext: icu_number_spellout in English'
END;
