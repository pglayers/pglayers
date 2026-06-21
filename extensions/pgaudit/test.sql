-- pgaudit integration tests
CREATE EXTENSION IF NOT EXISTS pgaudit;

-- Test: extension loaded and GUC available
SELECT CASE
    WHEN current_setting('pgaudit.log') IS NOT NULL
    THEN 'PASS pgaudit: GUC pgaudit.log accessible'
    ELSE 'FAIL pgaudit: GUC pgaudit.log accessible'
END;

-- Test: can set audit level
SET pgaudit.log = 'ddl';
SELECT CASE
    WHEN current_setting('pgaudit.log') = 'ddl'
    THEN 'PASS pgaudit: set log level to ddl'
    ELSE 'FAIL pgaudit: set log level to ddl'
END;
RESET pgaudit.log;
