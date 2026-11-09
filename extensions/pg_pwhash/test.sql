-- pg_pwhash (password hashing: scrypt, argon2, yescrypt) tests.
CREATE EXTENSION IF NOT EXISTS pg_pwhash;

SELECT CASE WHEN (SELECT count(*) FROM pg_extension WHERE extname='pg_pwhash')=1
    THEN 'PASS pg_pwhash: extension loads' ELSE 'FAIL pg_pwhash: extension loads' END;

-- The crypt backend requires $7$ salts, not the libscrypt/OpenSSL "scrypt" format.
SELECT CASE WHEN length(pwhash_scrypt_crypt('secret', pwhash_gen_salt('$7$'))) > 20
    THEN 'PASS pg_pwhash: scrypt hashing produces a hash'
    ELSE 'FAIL pg_pwhash: scrypt hashing produces a hash'
END;

-- a salt is generated
SELECT CASE WHEN pwhash_gen_salt('$7$') LIKE '$7$%'
    THEN 'PASS pg_pwhash: gen_salt produces a salt'
    ELSE 'FAIL pg_pwhash: gen_salt produces a salt'
END;

-- A stored hash accepts the original password and rejects a different one.
WITH hashed AS MATERIALIZED (
    SELECT pwhash_scrypt_crypt('secret', pwhash_gen_salt('$7$')) AS value
)
SELECT CASE
    WHEN pwhash_scrypt_crypt('secret', value) = value
         AND pwhash_scrypt_crypt('wrong', value) <> value
    THEN 'PASS pg_pwhash: password verification'
    ELSE 'FAIL pg_pwhash: password verification'
END FROM hashed;
