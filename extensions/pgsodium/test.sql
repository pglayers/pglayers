-- pgsodium integration tests
CREATE EXTENSION IF NOT EXISTS pgsodium;

-- Test: pgsodium schema exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_namespace WHERE nspname = 'pgsodium') = 1
    THEN 'PASS pgsodium: pgsodium schema created'
    ELSE 'FAIL pgsodium: pgsodium schema created'
END;

-- Test: crypto_secretbox function available
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc p
          JOIN pg_namespace n ON p.pronamespace = n.oid
          WHERE n.nspname = 'pgsodium' AND p.proname = 'crypto_secretbox') > 0
    THEN 'PASS pgsodium: crypto_secretbox function available'
    ELSE 'FAIL pgsodium: crypto_secretbox function available'
END;

-- Test: random bytes generation works
SELECT CASE
    WHEN length(pgsodium.randombytes_buf(32)) = 32
    THEN 'PASS pgsodium: randombytes_buf generates correct length'
    ELSE 'FAIL pgsodium: randombytes_buf generates correct length'
END;
