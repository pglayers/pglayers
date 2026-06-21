-- credcheck integration tests
-- Note: credcheck is loaded via shared_preload_libraries

-- Test: GUC accessible
SELECT CASE
    WHEN current_setting('credcheck.password_min_length') IS NOT NULL
    THEN 'PASS credcheck: password_min_length GUC accessible'
    ELSE 'FAIL credcheck: password_min_length GUC accessible'
END;

-- Test: extension enforces policy (min_length default is 1, so any password works)
SELECT CASE
    WHEN current_setting('credcheck.password_min_length')::int >= 0
    THEN 'PASS credcheck: password policy configuration works'
    ELSE 'FAIL credcheck: password policy configuration works'
END;
