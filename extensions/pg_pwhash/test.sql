-- pg_pwhash (password hashing: scrypt, argon2, yescrypt) tests.
CREATE EXTENSION IF NOT EXISTS pg_pwhash;

SELECT CASE WHEN (SELECT count(*) FROM pg_extension WHERE extname='pg_pwhash')=1
    THEN 'PASS pg_pwhash: extension loads' ELSE 'FAIL pg_pwhash: extension loads' END;

-- scrypt hashing produces a long hash string
SELECT CASE WHEN length(pwhash_scrypt_crypt('secret', pwhash_gen_salt('scrypt'))) > 20
    THEN 'PASS pg_pwhash: scrypt hashing produces a hash'
    ELSE 'FAIL pg_pwhash: scrypt hashing produces a hash'
END;

-- a salt is generated
SELECT CASE WHEN length(pwhash_gen_salt('scrypt')) > 0
    THEN 'PASS pg_pwhash: gen_salt produces a salt'
    ELSE 'FAIL pg_pwhash: gen_salt produces a salt'
END;
