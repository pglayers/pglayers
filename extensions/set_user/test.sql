-- set_user (privilege escalation control; requires shared_preload_libraries) tests.
-- Statements run in autocommit (piped) mode -- set_user()/reset_user() are not
-- allowed inside a transaction block.
CREATE EXTENSION IF NOT EXISTS set_user;

SELECT CASE WHEN (SELECT count(*) FROM pg_extension WHERE extname='set_user')=1
    THEN 'PASS set_user: extension loads' ELSE 'FAIL set_user: extension loads' END;

CREATE ROLE set_user_alice NOSUPERUSER;
SELECT set_user('set_user_alice');
SELECT CASE WHEN current_user = 'set_user_alice'
    THEN 'PASS set_user: switches to target role' ELSE 'FAIL set_user: switches to target role' END;
SELECT reset_user();
SELECT CASE WHEN current_user = 'postgres'
    THEN 'PASS set_user: resets to original role' ELSE 'FAIL set_user: resets to original role' END;
DROP ROLE set_user_alice;
