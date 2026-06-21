-- pg_hint_plan integration tests
CREATE EXTENSION IF NOT EXISTS pg_hint_plan;

-- Test: GUC available
SELECT CASE
    WHEN current_setting('pg_hint_plan.enable_hint') IS NOT NULL
    THEN 'PASS pg_hint_plan: GUC accessible'
    ELSE 'FAIL pg_hint_plan: GUC accessible'
END;

-- Test: can enable/disable
SET pg_hint_plan.enable_hint = off;
SELECT CASE
    WHEN current_setting('pg_hint_plan.enable_hint') = 'off'
    THEN 'PASS pg_hint_plan: can disable hints'
    ELSE 'FAIL pg_hint_plan: can disable hints'
END;
SET pg_hint_plan.enable_hint = on;

-- Test: debug mode available
SELECT CASE
    WHEN current_setting('pg_hint_plan.debug_print') IS NOT NULL
    THEN 'PASS pg_hint_plan: debug_print GUC available'
    ELSE 'FAIL pg_hint_plan: debug_print GUC available'
END;
