-- =============================================================================
-- CHR-ETRS MVP v1.6.21 · tests/test_assign_authz.sql — security fix J-143 (rpc_assign_task authorization)
-- Run on a FRESH database after the pack:
--   psql -v ON_ERROR_STOP=1 -f ref_country_calendar.sql -f schema.sql -f rpc.sql -f tests/test_assign_authz.sql
-- rpc_assign_task is SECURITY DEFINER (RLS does not protect spoon_budget), so only the employee herself or her
-- DIRECT manager (users.reports_to, solid line) may assign; anyone else → 403 access_denied BEFORE any read or
-- write: כפיות unchanged, no spoon_budget row created, no task row, no early_leave_log row.
-- Same harness as tests/test_v1_5.sql (pgTAP-style PASS lines; pgTAP itself is not installed). Every check
-- prints "PASS <name>"; any failure aborts. No identifier is printed.
-- =============================================================================
\set QUIET on
SET client_min_messages = warning;

-- ---------- helpers (same contract as tests/test_v1_5.sql) ----------
-- Print one PASS line.
CREATE OR REPLACE FUNCTION t_pass(p_name text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN RAISE WARNING 'PASS %', p_name; END $$;

-- Expect p_code with the Error Contract DETAIL 'http_hint=<p_http>;code=<p_code>'.
CREATE OR REPLACE FUNCTION t_expect_http(p_name text, p_sql text, p_code text, p_http int) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_detail text; v_state text;
BEGIN
  EXECUTE p_sql;
  RAISE EXCEPTION 'FAIL % — no error (expected % %)', p_name, p_http, p_code;
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE 'FAIL %' THEN RAISE; END IF;
  GET STACKED DIAGNOSTICS v_detail = PG_EXCEPTION_DETAIL, v_state = RETURNED_SQLSTATE;
  IF SQLERRM = p_code AND v_state = '42501' AND v_detail = format('http_hint=%s;code=%s', p_http, p_code) THEN
    PERFORM t_pass(p_name);
  ELSE
    RAISE EXCEPTION 'FAIL % — got [%] % / %, expected % %', p_name, v_state, SQLERRM, v_detail, p_http, p_code;
  END IF;
END $$;

-- Assert a boolean.
CREATE OR REPLACE FUNCTION t_assert(p_name text, p_ok boolean) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_ok IS NOT TRUE THEN RAISE EXCEPTION 'FAIL %', p_name; END IF;
  PERFORM t_pass(p_name);
END $$;

-- Impersonate a user for auth.uid() (NULL = anonymous).
CREATE OR REPLACE FUNCTION t_as(p_uid uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', COALESCE(p_uid::text, ''), false);
$$;

-- Deterministic fixture uuid of a key.
CREATE OR REPLACE FUNCTION t_u(p_key text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT md5('assign-authz-' || p_key)::uuid
$$;

-- Create one fixture user (auth + users) reporting to p_mgr (solid line) and optionally dotted to p_dotted.
CREATE OR REPLACE FUNCTION t_mk(p_key text, p_team text, p_role text, p_org_role text,
                                p_mgr text DEFAULT NULL, p_dotted text DEFAULT NULL) RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id) VALUES (t_u(p_key));
  INSERT INTO users (user_id, company_id, reports_to, dotted_line_to, email, full_name, department, app_role,
                     org_role_code, timezone, hire_date)
  VALUES (t_u(p_key), '00000000-0000-0000-0000-0000000a5c01',
          CASE WHEN p_mgr IS NOT NULL THEN t_u(p_mgr) END, CASE WHEN p_dotted IS NOT NULL THEN t_u(p_dotted) END,
          p_key || '@authz.test', 'Fixture ' || p_key, p_team, p_role, p_org_role, 'Asia/Jerusalem', DATE '2025-01-01');
  RETURN t_u(p_key);
END $$;

-- Today's כפיות of a fixture user (NULL = no spoon_budget row today). Superuser read.
CREATE OR REPLACE FUNCTION t_spoons(p_key text) RETURNS int LANGUAGE sql AS $$
  SELECT sb.current_spoon_count FROM spoon_budget sb
   WHERE sb.user_id = t_u(p_key) AND sb.budget_date = fn_user_local_date(t_u(p_key))
$$;

-- Set today's כפיות of a fixture user (creates the row first).
CREATE OR REPLACE FUNCTION t_set_spoons(p_key text, p_n int) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM fn_ensure_local_spoon_budget(t_u(p_key));
  UPDATE spoon_budget SET current_spoon_count = p_n
   WHERE user_id = t_u(p_key) AND budget_date = fn_user_local_date(t_u(p_key));
END $$;

-- Row counts of the tables a refused call must never touch, for one assignee.
CREATE OR REPLACE FUNCTION t_leave_rows(p_key text) RETURNS bigint LANGUAGE sql AS $$
  SELECT count(*) FROM early_leave_log WHERE user_id = t_u(p_key)
$$;
CREATE OR REPLACE FUNCTION t_task_rows(p_key text) RETURNS bigint LANGUAGE sql AS $$
  SELECT count(*) FROM task WHERE assignee_id = t_u(p_key)
$$;

-- SQL text of one rpc_assign_task call (for t_expect_http), run by whoever t_as() set as the caller.
CREATE OR REPLACE FUNCTION t_assign_sql(p_assignee text, p_kind text, p_mods text DEFAULT '[]') RETURNS text LANGUAGE sql AS $$
  SELECT format($q$SELECT rpc_assign_task(t_u(%L), 'authz', %L::task_kind_enum, false, false, %L::jsonb)$q$,
                p_assignee, p_kind, p_mods)
$$;

GRANT EXECUTE ON FUNCTION t_pass(text), t_expect_http(text, text, text, int), t_assert(text, boolean),
  t_as(uuid), t_u(text), t_assign_sql(text, text, text) TO authenticated;

-- ---------- fixtures ----------
-- One company; team A (direct manager mgr_a, employees emp_a1 / emp_a2), team B (direct manager mgr_b,
-- employee emp_b1); mgr_a and mgr_b report to dept_head (skip level for emp_a1); emp_a1 has a dotted line to mgr_b;
-- emp_a3 (team A) has ended employment.
INSERT INTO companies (company_id, company_name, country, week_start_dow, last_workday_dow, timezone)
VALUES ('00000000-0000-0000-0000-0000000a5c01', 'AuthzCo', 'IL', 0, 4, 'Asia/Jerusalem');
SELECT t_mk('dept_head', 'Mgmt', 'manager', 'department_manager');
SELECT t_mk('mgr_a', 'TeamA', 'manager', 'direct_manager', 'dept_head');
SELECT t_mk('mgr_b', 'TeamB', 'manager', 'direct_manager', 'dept_head');
SELECT t_mk('emp_a1', 'TeamA', 'employee', 'employee', 'mgr_a', 'mgr_b');
SELECT t_mk('emp_a2', 'TeamA', 'employee', 'employee', 'mgr_a');
SELECT t_mk('emp_a3', 'TeamA', 'employee', 'employee', 'mgr_a');
SELECT t_mk('emp_b1', 'TeamB', 'employee', 'employee', 'mgr_b');
UPDATE users SET employment_ended_at = clock_timestamp() - interval '1 day' WHERE user_id = t_u('emp_a3');

-- ============ 1. allowed: self and direct manager ============
SELECT t_set_spoons('emp_a1', 12);
SELECT t_as(t_u('emp_a1'));
SET ROLE authenticated;
SELECT t_assert('J-143: employee assigns to herself → allowed, assigner = self',
  (SELECT assigner_id = t_u('emp_a1') AND assignee_id = t_u('emp_a1') FROM rpc_assign_task(t_u('emp_a1'), 'self', 'fighting')));
RESET ROLE;
SELECT t_assert('J-143: self-assignment debits her own כפיות (12 → 11)', t_spoons('emp_a1') = 11);

SELECT t_as(t_u('mgr_a'));
SET ROLE authenticated;
SELECT t_assert('J-143: direct manager assigns to her employee → allowed, assigner = manager',
  (SELECT assigner_id = t_u('mgr_a') AND assignee_id = t_u('emp_a1') FROM rpc_assign_task(t_u('emp_a1'), 'mgr', 'fighting')));
RESET ROLE;
SELECT t_assert('J-143: direct-manager assignment debits the employee (11 → 10)', t_spoons('emp_a1') = 10);

-- ============ 2. refused: anyone else → 403 access_denied, כפיות unchanged ============
CREATE TEMP TABLE t_before AS SELECT t_spoons('emp_a1') AS spoons, t_task_rows('emp_a1') AS tasks;
GRANT SELECT ON t_before TO authenticated;

SELECT t_as(t_u('emp_a2'));
SET ROLE authenticated;
SELECT t_expect_http('J-143: another employee of the same team (not a manager) → 403 access_denied',
  t_assign_sql('emp_a1', 'fighting'), 'access_denied', 403);
RESET ROLE;
SELECT t_assert('J-143: after the peer attempt כפיות unchanged (before = after) and no task row',
  t_spoons('emp_a1') = (SELECT spoons FROM t_before) AND t_task_rows('emp_a1') = (SELECT tasks FROM t_before));

SELECT t_as(t_u('mgr_b'));
SET ROLE authenticated;
SELECT t_expect_http('J-143: manager of a DIFFERENT team (also the dotted line) → 403 access_denied',
  t_assign_sql('emp_a1', 'fighting'), 'access_denied', 403);
RESET ROLE;
SELECT t_assert('J-143: after the other-team manager attempt כפיות unchanged and no task row',
  t_spoons('emp_a1') = (SELECT spoons FROM t_before) AND t_task_rows('emp_a1') = (SELECT tasks FROM t_before));

SELECT t_as(t_u('dept_head'));
SET ROLE authenticated;
SELECT t_expect_http('J-143: skip-level manager (manager of the manager) is not the direct manager → 403 access_denied',
  t_assign_sql('emp_a1', 'fighting'), 'access_denied', 403);
RESET ROLE;
SELECT t_assert('J-143: after the skip-level attempt כפיות unchanged',
  t_spoons('emp_a1') = (SELECT spoons FROM t_before));

SELECT t_as(t_u('emp_b1'));
SET ROLE authenticated;
SELECT t_expect_http('J-143: an employee of another team → 403 access_denied',
  t_assign_sql('emp_a1', 'farming'), 'access_denied', 403);
RESET ROLE;
SELECT t_assert('J-143: after the other-team employee attempt כפיות unchanged',
  t_spoons('emp_a1') = (SELECT spoons FROM t_before));

SELECT t_as(t_u('mgr_a'));
SET ROLE authenticated;
SELECT t_expect_http('J-143: direct manager of an employee whose employment ended → 403 access_denied',
  t_assign_sql('emp_a3', 'farming'), 'access_denied', 403);
RESET ROLE;

-- ============ 3. nothing is read or written before the check ============
SELECT t_assert('J-143: fixture — the other-team employee has no spoon_budget row today', t_spoons('emp_b1') IS NULL);
SELECT t_as(t_u('emp_a2'));
SET ROLE authenticated;
SELECT t_expect_http('J-143: unrelated user → 403 access_denied for an assignee without a budget row',
  t_assign_sql('emp_b1', 'farming'), 'access_denied', 403);
RESET ROLE;
SELECT t_assert('J-143: the refused call created no spoon_budget row (check runs before fn_ensure_local_spoon_budget)',
  t_spoons('emp_b1') IS NULL AND NOT EXISTS (SELECT 1 FROM spoon_budget WHERE user_id = t_u('emp_b1')));

-- Near the early-leave threshold: 4 כפיות + farming with +1 → 3 would log 'יציאה מוקדמת מאושרת'.
SELECT t_set_spoons('emp_a1', 4);
DROP TABLE t_before;
CREATE TEMP TABLE t_before AS SELECT t_spoons('emp_a1') AS spoons, t_task_rows('emp_a1') AS tasks, t_leave_rows('emp_a1') AS leaves;
SELECT t_assert('J-143: fixture — at 4 כפיות, no early-leave row yet', (SELECT spoons = 4 AND leaves = 0 FROM t_before));
SELECT t_as(t_u('emp_a2'));
SET ROLE authenticated;
SELECT t_expect_http('J-143: peer assigns farming +1 at the threshold → 403 access_denied',
  t_assign_sql('emp_a1', 'farming', '[1]'), 'access_denied', 403);
RESET ROLE;
SELECT t_as(t_u('mgr_b'));
SET ROLE authenticated;
SELECT t_expect_http('J-143: other-team manager assigns farming +1 at the threshold → 403 access_denied',
  t_assign_sql('emp_a1', 'farming', '[1]'), 'access_denied', 403);
RESET ROLE;
SELECT t_assert('J-143: after the failed attempts early_leave_log count unchanged (before = after)',
  t_leave_rows('emp_a1') = (SELECT leaves FROM t_before));
SELECT t_assert('J-143: after the failed attempts כפיות unchanged (4) and no task row',
  t_spoons('emp_a1') = (SELECT spoons FROM t_before) AND t_task_rows('emp_a1') = (SELECT tasks FROM t_before));
-- Control: the SAME call by the direct manager does log — so the test above is meaningful.
SELECT t_as(t_u('mgr_a'));
SET ROLE authenticated;
SELECT t_assert('J-143 control: direct manager, same call → allowed (4 → 3)',
  (SELECT s_final = 1 FROM rpc_assign_task(t_u('emp_a1'), 'farm+1', 'farming', false, false, '[1]')));
RESET ROLE;
SELECT t_assert('J-143 control: the allowed call wrote exactly one early_leave_log row',
  t_leave_rows('emp_a1') = (SELECT leaves FROM t_before) + 1 AND t_spoons('emp_a1') = 3);

-- ============ 4. the refusal leaks nothing about energy ============
-- At 3 כפיות the circuit breaker would answer circuit_breaker_active; an unrelated caller still gets access_denied.
SELECT t_as(t_u('mgr_b'));
SET ROLE authenticated;
SELECT t_expect_http('J-143: at ≤3 כפיות an unrelated caller gets access_denied, never circuit_breaker_active',
  t_assign_sql('emp_a1', 'farming'), 'access_denied', 403);
RESET ROLE;
SELECT t_as(t_u('mgr_a'));
SET ROLE authenticated;
SELECT t_expect_http('J-143: unchanged — the direct manager at ≤3 כפיות still gets circuit_breaker_active',
  t_assign_sql('emp_a1', 'farming'), 'circuit_breaker_active', 403);
RESET ROLE;

-- ============ 5. unchanged paths ============
SELECT t_as(NULL);
SET ROLE authenticated;
SELECT t_expect_http('J-143: unchanged — anonymous caller still → 403 anti_get_blocked',
  t_assign_sql('emp_a1', 'farming'), 'anti_get_blocked', 403);
RESET ROLE;
SELECT t_assert('J-143: helpers are not callable by clients',
  NOT has_function_privilege('authenticated', 'fn_is_direct_manager_of(uuid)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'fn_assert_may_assign_task(uuid)', 'EXECUTE'));
SELECT t_assert('J-143: rpc_assign_task calls the authorization check before any spoon_budget / early_leave_log / task access',
  (SELECT a > 0 AND a < strpos(d, 'fn_ensure_local_spoon_budget') AND a < strpos(d, 'FROM spoon_budget')
          AND a < strpos(d, 'UPDATE spoon_budget') AND a < strpos(d, 'INSERT INTO task') AND a < strpos(d, 'fn_log_early_leave')
     FROM (SELECT d, strpos(d, 'PERFORM fn_assert_may_assign_task') AS a FROM (SELECT pg_get_functiondef('rpc_assign_task(uuid, varchar, task_kind_enum, boolean, boolean, jsonb, boolean, varchar, varchar)'::regprocedure) d) y) x));
