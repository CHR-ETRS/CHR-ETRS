-- =============================================================================
-- CHR-ETRS MVP v1.6.21 · tests/test_assign_authz.sql — security fix J-143 (rpc_assign_task authorization)
-- Run on a FRESH database after the pack:
--   psql -v ON_ERROR_STOP=1 -f ref_country_calendar.sql -f schema.sql -f rpc.sql -f tests/test_assign_authz.sql
-- rpc_assign_task is SECURITY DEFINER (RLS does not protect spoon_budget), so only the employee herself or her
-- DIRECT manager (users.reports_to, solid line) may assign; anyone else → 403 access_denied BEFORE any read or
-- write: כפיות unchanged, no spoon_budget row created, no task row, no early_leave_log row.
-- J-146 A (Karin 04.11): for the authorized direct manager every refusal after that check is ONE neutral 403
-- assignment_unavailable (J-152 = A, Karin); only self-assignment shows the exact reason; strangers
-- always get the identical 403 access_denied (J-153 = A).
-- Section 10 (v1.6.21, Karin, relayed 23.11 — J-156 A / J-169 / J-170): ONE uniform manager unavailability list —
-- byte-identical rows for every source, today and future only, no time / כפיות / type / count; coordinate-only RPC;
-- vp_hr J-80 team input unchanged.
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
SELECT FROM t_mk('dept_head', 'Mgmt', 'manager', 'department_manager');
SELECT FROM t_mk('mgr_a', 'TeamA', 'manager', 'direct_manager', 'dept_head');
SELECT FROM t_mk('mgr_b', 'TeamB', 'manager', 'direct_manager', 'dept_head');
SELECT FROM t_mk('emp_a1', 'TeamA', 'employee', 'employee', 'mgr_a', 'mgr_b');
SELECT FROM t_mk('emp_a2', 'TeamA', 'employee', 'employee', 'mgr_a');
SELECT FROM t_mk('emp_a3', 'TeamA', 'employee', 'employee', 'mgr_a');
SELECT FROM t_mk('emp_b1', 'TeamB', 'employee', 'employee', 'mgr_b');
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
SELECT t_expect_http('J-146 A: the direct manager at ≤3 כפיות gets the neutral 403 assignment_unavailable (was circuit_breaker_active)',
  t_assign_sql('emp_a1', 'farming'), 'assignment_unavailable', 403);
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

-- =============================================================================
-- J-146 A (Karin 04.11): ONE neutral answer for the direct manager; exact reason only for self;
-- J-153 = A: strangers always the identical 403 access_denied. Responses are compared field by field.
-- =============================================================================

-- The error a statement raises, as the client-visible fields (code = SQLSTATE, message, details, hint) plus the
-- server context up to rpc_assign_task (proves one raise site). '{"no_error": true}' when it succeeds.
CREATE OR REPLACE FUNCTION t_err_sig(p_sql text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_state text; v_msg text; v_detail text; v_hint text; v_ctx text;
BEGIN
  EXECUTE p_sql;
  RETURN '{"no_error": true}'::jsonb;
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT, v_detail = PG_EXCEPTION_DETAIL,
                          v_hint = PG_EXCEPTION_HINT, v_ctx = PG_EXCEPTION_CONTEXT;
  RETURN jsonb_build_object('code', v_state, 'message', v_msg, 'details', v_detail, 'hint', v_hint,
                            'ctx', (regexp_match(v_ctx, '^(.*?PL/pgSQL function rpc_assign_task\([^\n]*)', 's'))[1]);
END $$;

-- Fingerprint of every table a refused call could touch (superuser read): task, spoon_budget, early_leave_log,
-- notification, access_audit_log. Equal before / after ⇒ nothing was written.
CREATE OR REPLACE FUNCTION t_snapshot() RETURNS text LANGUAGE sql AS $$
  SELECT md5(concat_ws('|',
    (SELECT string_agg(t::text, ',' ORDER BY t::text) FROM task t),
    (SELECT string_agg(b::text, ',' ORDER BY b::text) FROM spoon_budget b),
    (SELECT string_agg(l::text, ',' ORDER BY l::text) FROM early_leave_log l),
    (SELECT string_agg(n::text, ',' ORDER BY n::text) FROM notification n),
    (SELECT string_agg(a::text, ',' ORDER BY a::text) FROM access_audit_log a)))
$$;

-- What the CURRENT caller can see that could hint at a refusal: her task rows (RLS), the direct-manager
-- early-leave feed, her notifications. Run under SET ROLE authenticated.
CREATE OR REPLACE FUNCTION t_visible() RETURNS text LANGUAGE sql AS $$
  SELECT md5(concat_ws('|',
    (SELECT string_agg(t::text, ',' ORDER BY t::text) FROM task t),
    (SELECT string_agg(e::text, ',' ORDER BY e::text) FROM early_leave_manager_v e),
    (SELECT string_agg(n::text, ',' ORDER BY n::text) FROM notification n)))
$$;

-- SQL text of an assignment with a given task name / modifiers (for the "other refusal" cases).
CREATE OR REPLACE FUNCTION t_assign_sql2(p_assignee uuid, p_kind text, p_name text, p_mods text) RETURNS text LANGUAGE sql AS $$
  SELECT format($q$SELECT rpc_assign_task(%L::uuid, %L, %L::task_kind_enum, false, false, %L::jsonb)$q$,
                p_assignee, p_name, p_kind, p_mods)
$$;

GRANT EXECUTE ON FUNCTION t_err_sig(text), t_visible(), t_assign_sql2(uuid, text, text, text) TO authenticated;
CREATE TEMP TABLE t_sig (grp text, label text, sig jsonb);
GRANT SELECT, INSERT ON t_sig TO authenticated;

-- ---------- 6. direct manager: every refusal → the identical neutral 403 ----------
SELECT t_set_spoons('emp_a2', 3);
CREATE TEMP TABLE t_snap AS SELECT t_snapshot() AS db;
SELECT t_as(t_u('mgr_a'));
SET ROLE authenticated;
CREATE TEMP TABLE t_vis AS SELECT t_visible() AS v;
INSERT INTO t_sig SELECT 'mgr', 'cb go-home farming', t_err_sig(t_assign_sql('emp_a2', 'farming'));
INSERT INTO t_sig SELECT 'mgr', 'cb go-home fighting', t_err_sig(t_assign_sql('emp_a2', 'fighting'));
RESET ROLE;
SELECT t_set_spoons('emp_a2', 5);
SELECT t_as(t_u('mgr_a'));
SET ROLE authenticated;
INSERT INTO t_sig SELECT 'mgr', 'cb fighting at 4-5', t_err_sig(t_assign_sql('emp_a2', 'fighting'));
RESET ROLE;
SELECT t_set_spoons('emp_a2', 12);
SELECT t_as(t_u('mgr_a'));
SET ROLE authenticated;
INSERT INTO t_sig SELECT 'mgr', 'invalid modifier', t_err_sig(t_assign_sql2(t_u('emp_a2'), 'fighting', 'x', '[{"delta": "x"}]'));
INSERT INTO t_sig SELECT 'mgr', 'task name too long', t_err_sig(t_assign_sql2(t_u('emp_a2'), 'fighting', repeat('x', 300), '[]'));
INSERT INTO t_sig SELECT 'mgr', 'task name missing', t_err_sig(t_assign_sql2(t_u('emp_a2'), 'fighting', NULL, '[]'));
RESET ROLE;
SELECT t_set_spoons('emp_a2', 3);

SELECT t_assert('J-146 A: the direct manager is refused in all 6 cases (CB ≤3 farming / fighting, CB 4–5 fighting, bad modifier, long name, no name)',
  (SELECT count(*) = 6 AND bool_and(NOT sig ? 'no_error') FROM t_sig WHERE grp = 'mgr'));
SELECT t_assert('J-146 A: all 6 refusals are IDENTICAL (code, message, details, hint and server context)',
  (SELECT count(DISTINCT sig) = 1 FROM t_sig WHERE grp = 'mgr'));
SELECT t_assert('J-146 A: identical field list in every refusal',
  (SELECT count(DISTINCT (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(sig) k)) = 1 FROM t_sig WHERE grp = 'mgr'));
SELECT t_assert('J-146 A: the neutral answer is 403 assignment_unavailable (SQLSTATE 42501, Error Contract DETAIL / HINT)',
  (SELECT bool_and(sig->>'code' = '42501' AND sig->>'message' = 'assignment_unavailable'
                   AND sig->>'details' = 'http_hint=403;code=assignment_unavailable' AND sig->>'hint' = 'assignment_unavailable')
     FROM t_sig WHERE grp = 'mgr'));
SELECT t_assert('J-146 A: the neutral answer never names circuit_breaker_active / anti_get_blocked / a SQL error',
  (SELECT bool_and(sig::text !~ '(circuit_breaker|anti_get|invalid input|value too long|null value)') FROM t_sig WHERE grp = 'mgr'));
SELECT t_assert('J-146 A: message / hint of the neutral answer carry no digit and no id',
  (SELECT bool_and((sig->>'message') || (sig->>'hint') !~ '[0-9]') FROM t_sig WHERE grp = 'mgr'));
SELECT t_assert('J-146 A: after the 6 refusals nothing changed — task, spoon_budget, early_leave_log, notification, access_audit_log (before = after)',
  t_snapshot() = (SELECT db FROM t_snap));
SELECT t_as(t_u('mgr_a'));
SET ROLE authenticated;
SELECT t_assert('J-146 A: nothing new is visible to the manager (her task rows, early-leave feed, notifications: before = after)',
  t_visible() = (SELECT v FROM t_vis));
SELECT t_assert('J-146 A: the manager sees no task row of the refused employee marked as blocked',
  NOT EXISTS (SELECT 1 FROM task WHERE assignee_id = t_u('emp_a2') AND (is_blocked_by_circuit_breaker OR task_name IN ('authz', 'x'))));
SELECT t_assert('J-146 A: the manager feed still holds only the one entry the earlier ALLOWED call wrote (nothing for the refused employee)',
  (SELECT count(*) = 1 FROM early_leave_manager_v));
-- The Hebrew text, served like every fixed text (rpc_notification_message_he).
SELECT t_assert('J-146 A: rpc_notification_message_he(assignment_unavailable) = the exact approved text',
  rpc_notification_message_he('assignment_unavailable') = 'לא ניתן להקצות לה את המשימה כרגע. אפשר להקצות למישהי אחרת בצוות או לנסות שוב מחר.');
SELECT t_assert('J-146 A: the neutral Hebrew text has no digit and no id',
  rpc_notification_message_he('assignment_unavailable') !~ '[0-9]');
RESET ROLE;
SELECT t_assert('J-146 A: no early_leave_log row was written for the refused employee',
  (SELECT count(*) FROM early_leave_log WHERE user_id = t_u('emp_a2')) = 0);

-- ---------- 7. self-assignment still sees the exact reason ----------
SELECT t_as(t_u('emp_a2'));
SET ROLE authenticated;
SELECT t_expect_http('J-146 A: self at ≤3 כפיות (farming) → circuit_breaker_active (unchanged)',
  t_assign_sql('emp_a2', 'farming'), 'circuit_breaker_active', 403);
SELECT t_expect_http('J-146 A: self at ≤3 כפיות (fighting) → circuit_breaker_active (unchanged)',
  t_assign_sql('emp_a2', 'fighting'), 'circuit_breaker_active', 403);
RESET ROLE;
SELECT t_set_spoons('emp_a2', 5);
SELECT t_as(t_u('emp_a2'));
SET ROLE authenticated;
SELECT t_expect_http('J-146 A: self at 5 כפיות (fighting) → circuit_breaker_active (unchanged)',
  t_assign_sql('emp_a2', 'fighting'), 'circuit_breaker_active', 403);
SELECT t_assert('J-146 A: self at 5 כפיות, farming → allowed (unchanged)',
  (SELECT task_kind = 'farming' FROM rpc_assign_task(t_u('emp_a2'), 'self-farm', 'farming')));
SELECT t_assert('J-146 A: self with a bad modifier still sees the exact SQL error (22P02), not the neutral code',
  (SELECT sig->>'code' = '22P02' FROM (SELECT t_err_sig(t_assign_sql2(t_u('emp_a2'), 'farming', 'x', '[{"delta": "x"}]')) sig) s));
RESET ROLE;

-- ---------- 8. J-153 = A: strangers — the identical 403 access_denied whatever the target's כפיות ----------
DROP TABLE t_snap;
CREATE TEMP TABLE t_snap AS SELECT t_snapshot() AS db;
CREATE OR REPLACE FUNCTION t_stranger_round(p_label text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE k text;
BEGIN
  FOREACH k IN ARRAY ARRAY['emp_b1', 'mgr_b', 'dept_head', 'emp_a1'] LOOP
    PERFORM t_as(t_u(k));
    SET LOCAL ROLE authenticated;
    INSERT INTO t_sig SELECT 'stranger', p_label || ' fighting', t_err_sig(t_assign_sql('emp_a2', 'fighting'));
    INSERT INTO t_sig SELECT 'stranger', p_label || ' farming', t_err_sig(t_assign_sql('emp_a2', 'farming', '[1]'));
    RESET ROLE;
  END LOOP;
END $$;
SELECT t_set_spoons('emp_a2', 12);
DROP TABLE t_snap;
CREATE TEMP TABLE t_snap AS SELECT t_snapshot() AS db;
SELECT t_stranger_round('at 12');
SELECT t_assert('J-153 = A: strangers at 12 כפיות changed nothing (before = after)', t_snapshot() = (SELECT db FROM t_snap));
SELECT t_set_spoons('emp_a2', 5);
DROP TABLE t_snap;
CREATE TEMP TABLE t_snap AS SELECT t_snapshot() AS db;
SELECT t_stranger_round('at 5');
SELECT t_assert('J-153 = A: strangers at 5 כפיות changed nothing (before = after)', t_snapshot() = (SELECT db FROM t_snap));
SELECT t_set_spoons('emp_a2', 3);
DROP TABLE t_snap;
CREATE TEMP TABLE t_snap AS SELECT t_snapshot() AS db;
SELECT t_stranger_round('at 3');
SELECT t_assert('J-153 = A: strangers at 3 כפיות changed nothing — no early_leave_log, no task (before = after)', t_snapshot() = (SELECT db FROM t_snap));
-- Targets that are not a current employee of the caller's line at all.
SELECT t_as(t_u('mgr_b'));
SET ROLE authenticated;
INSERT INTO t_sig SELECT 'stranger', 'ended employee', t_err_sig(t_assign_sql('emp_a3', 'fighting'));
INSERT INTO t_sig SELECT 'stranger', 'unknown id', t_err_sig(t_assign_sql2('00000000-0000-0000-0000-00000000dead', 'fighting', 'x', '[]'));
RESET ROLE;
SELECT t_assert('J-153 = A: 26 stranger calls (4 strangers × 2 kinds × 3 כפיות states + ended + unknown) are all refused',
  (SELECT count(*) = 26 AND bool_and(NOT sig ? 'no_error') FROM t_sig WHERE grp = 'stranger'));
SELECT t_assert('J-153 = A: all 26 stranger refusals are IDENTICAL (code, message, details, hint, context)',
  (SELECT count(DISTINCT sig) = 1 FROM t_sig WHERE grp = 'stranger'));
SELECT t_assert('J-153 = A: the stranger answer is 403 access_denied (42501), never the neutral code or a CB code',
  (SELECT bool_and(sig->>'code' = '42501' AND sig->>'message' = 'access_denied'
                   AND sig->>'details' = 'http_hint=403;code=access_denied' AND sig->>'hint' = 'access_denied')
     FROM t_sig WHERE grp = 'stranger'));

-- ---------- 9. structure ----------
SELECT t_assert('J-146 A: the new helpers are not callable by clients',
  NOT has_function_privilege('authenticated', 'fn_assign_neutral_refusal(boolean)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'fn_assign_refusal_reason(integer, task_kind_enum, integer)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'fn_cb_task_blocked(integer, task_kind_enum)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'fn_assignment_unavailable_he()', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'fn_assign_neutral_refusal(boolean)', 'EXECUTE'));
SELECT t_assert('J-146 A: assignment_unavailable is raised from ONE place (the rpc_assign_task handler → fn_assign_neutral_refusal)',
  (SELECT count(*) = 1 FROM pg_proc p WHERE p.prosrc LIKE '%fn_raise_business(''assignment_unavailable'')%')
  AND pg_get_functiondef('rpc_assign_task(uuid, varchar, task_kind_enum, boolean, boolean, jsonb, boolean, varchar, varchar)'::regprocedure)
      LIKE '%EXCEPTION WHEN OTHERS THEN%fn_assign_neutral_refusal(v_self)%');

-- ============ 10. v1.6.21 J-156 A / J-169 / J-170 (Karin, relayed 23.11) · ONE uniform manager unavailability list ============
-- Real clock (no libfaketime): every date is relative to each employee's own local today.
-- mgr_u's team: emp_el (early leave today, via rpc_assign_task), emp_gh (go-home today, rpc_log_go_home),
-- emp_ab (approved absence today + a future day), emp_tb (EverStore-style time benefit = approved entry, future day);
-- plus a past early leave and a past approved entry that must never show.
SELECT FROM t_mk('mgr_u', 'TeamU', 'manager', 'direct_manager', 'dept_head');
SELECT FROM t_mk('emp_el', 'TeamU', 'employee', 'employee', 'mgr_u');
SELECT FROM t_mk('emp_gh', 'TeamU', 'employee', 'employee', 'mgr_u');
SELECT FROM t_mk('emp_ab', 'TeamU', 'employee', 'employee', 'mgr_u');
SELECT FROM t_mk('emp_tb', 'TeamU', 'employee', 'employee', 'mgr_u');
SELECT FROM t_mk('vp_u', 'HR', 'vp_hr', 'employee');
-- emp_el: the direct manager's allowed assignment that leaves her at 3 כפיות writes the early-leave entry.
SELECT t_set_spoons('emp_el', 6);
SELECT t_as(t_u('mgr_u'));
SET ROLE authenticated;
SELECT t_assert('J-156 A fixture: mgr_u assigns a task of cost 3 at 6 כפיות → allowed (3 left → early leave logged)',
  (SELECT assignee_id = t_u('emp_el') FROM rpc_assign_task(t_u('emp_el'), 'u-task', 'fighting', false, false, '[2]'::jsonb)));
RESET ROLE;
-- emp_gh goes home herself.
SELECT t_set_spoons('emp_gh', 2);
SELECT t_as(t_u('emp_gh'));
SET ROLE authenticated;
SELECT t_assert('J-156 A fixture: emp_gh goes home (rpc_log_go_home)', (SELECT log_id IS NOT NULL FROM rpc_log_go_home()));
RESET ROLE;
INSERT INTO approved_absence_entry (user_id, requested_date) VALUES
  (t_u('emp_ab'), fn_user_local_date(t_u('emp_ab'))),
  (t_u('emp_ab'), fn_user_local_date(t_u('emp_ab')) + 9),
  (t_u('emp_tb'), fn_user_local_date(t_u('emp_tb')) + 9),
  (t_u('emp_ab'), fn_user_local_date(t_u('emp_ab')) - 1);           -- past: never listed
INSERT INTO early_leave_log (user_id, local_date) VALUES (t_u('emp_tb'), fn_user_local_date(t_u('emp_tb')) - 2);  -- past
SELECT t_assert('J-156 A fixture: 2 early-leave days today, 2 past rows, 3 current approved entries exist in the sources',
  (SELECT count(*) = 2 FROM early_leave_log l JOIN users u USING (user_id) WHERE u.reports_to = t_u('mgr_u') AND l.local_date = fn_user_local_date(l.user_id))
  AND (SELECT count(*) = 3 FROM approved_absence_entry a JOIN users u USING (user_id) WHERE u.reports_to = t_u('mgr_u') AND a.requested_date >= fn_user_local_date(a.user_id)));

CREATE TEMP TABLE t_unav (label text, j jsonb, ord int);
GRANT SELECT, INSERT ON t_unav TO authenticated;
SELECT t_as(t_u('mgr_u'));
SET ROLE authenticated;
INSERT INTO t_unav SELECT 'v', to_jsonb(v), row_number() OVER () FROM manager_unavailability_v v;
INSERT INTO t_unav SELECT 'el', to_jsonb(v), row_number() OVER () FROM early_leave_manager_v v;
INSERT INTO t_unav SELECT 'ab', to_jsonb(v), row_number() OVER () FROM approved_absence_manager_v v;
RESET ROLE;
SELECT t_assert('J-156 A / J-170: the manager sees 5 rows — today (go-home, task early leave, approved) and the 2 future approved days; no past day',
  (SELECT count(*) = 5 FROM t_unav WHERE label = 'v')
  AND (SELECT bool_and((j->>'unavailable_date')::date >= CURRENT_DATE - 1) FROM t_unav WHERE label = 'v')
  AND NOT EXISTS (SELECT 1 FROM t_unav u JOIN approved_absence_entry a ON a.absence_id = (u.j->>'entry_id')::uuid
                   WHERE a.requested_date < fn_user_local_date(a.user_id))
  AND NOT EXISTS (SELECT 1 FROM t_unav u JOIN early_leave_log l ON l.log_id = (u.j->>'entry_id')::uuid
                   WHERE l.local_date < fn_user_local_date(l.user_id)));
SELECT t_assert('J-156 A: the 3 rows of TODAY are byte-identical apart from entry id and pseudonym (early leave via task, go-home, approved absence): same columns, date, text, status',
  (SELECT count(*) = 3 AND count(DISTINCT (j - 'entry_id' - 'display_pseudonym')::text) = 1
     FROM t_unav u WHERE label = 'v' AND (j->>'unavailable_date')::date = fn_user_local_date(t_u('emp_el')))
  AND (SELECT bool_and(j->>'availability_he' = 'לא זמינה להמשך היום' AND j->>'coordination_status' = 'pending_coordination')
         FROM t_unav WHERE label = 'v' AND (j->>'unavailable_date')::date = fn_user_local_date(t_u('emp_el'))));
SELECT t_assert('J-170: the 2 future rows (approved absence, time benefit) are byte-identical apart from id / pseudonym: "לא זמינה", pending_coordination',
  (SELECT count(*) = 2 AND count(DISTINCT (j - 'entry_id' - 'display_pseudonym')::text) = 1
          AND bool_and(j->>'availability_he' = 'לא זמינה')
     FROM t_unav WHERE label = 'v' AND (j->>'unavailable_date')::date > fn_user_local_date(t_u('emp_el'))));
SELECT t_assert('J-156 A: every row has exactly the 5 uniform keys (entry_id, display_pseudonym, unavailable_date, availability_he, coordination_status)',
  (SELECT bool_and((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(j) k)
                   = ARRAY['availability_he', 'coordination_status', 'display_pseudonym', 'entry_id', 'unavailable_date'])
     FROM t_unav));
SELECT t_assert('J-156 A: no time, כפיות, type, source text, count or history in the manager output (no left_at / spoons / entry_type / entry_text / created_at; no "יציאה מוקדמת" / "זמן התרעננות" wording; no clock time)',
  (SELECT bool_and(j::text !~* '(left_at|spoon|entry_type|entry_text|created_at|count|history|יציאה|מוקדמת|התרעננות|היעדרות|[0-9]{2}:[0-9]{2})')
     FROM t_unav));
SELECT t_assert('J-156 A: no manager-facing column anywhere exposes time, כפיות, type, source text or a count (catalog: the 3 views + the coordinate RPC result)',
  NOT EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name IN ('manager_unavailability_v', 'early_leave_manager_v', 'approved_absence_manager_v')
                 AND column_name ~* '(left_at|spoon|entry_type|entry_text|created_at|count|reason|user_id|person)')
  AND (SELECT pg_get_function_result('rpc_coordinate_approved_absence(uuid)'::regprocedure)
       = 'TABLE(entry_id uuid, display_pseudonym character varying, unavailable_date date, availability_he text, coordination_status text)'));
SELECT t_assert('J-156 A: neutral order — by date, then pseudonym (never by type / source / time)',
  (SELECT array_agg(j ORDER BY ord) = array_agg(j ORDER BY (j->>'unavailable_date')::date, j->>'display_pseudonym', j->>'entry_id')
     FROM t_unav WHERE label = 'v'));
SELECT t_assert('J-258: early_leave_manager_v and approved_absence_manager_v are byte-identical aliases of the one list (same rows, same order)',
  (SELECT array_agg(j ORDER BY ord) FROM t_unav WHERE label = 'el') = (SELECT array_agg(j ORDER BY ord) FROM t_unav WHERE label = 'v')
  AND (SELECT array_agg(j ORDER BY ord) FROM t_unav WHERE label = 'ab') = (SELECT array_agg(j ORDER BY ord) FROM t_unav WHERE label = 'v'));

-- Coordination works for every source and returns the same uniform row.
CREATE TEMP TABLE t_coord AS
  SELECT (SELECT log_id FROM early_leave_log WHERE user_id = t_u('emp_el') AND local_date = fn_user_local_date(t_u('emp_el'))) AS el_id,
         (SELECT absence_id FROM approved_absence_entry WHERE user_id = t_u('emp_ab') AND requested_date = fn_user_local_date(t_u('emp_ab'))) AS ab_id,
         (SELECT log_id FROM early_leave_log WHERE user_id = t_u('emp_tb') AND local_date < fn_user_local_date(t_u('emp_tb'))) AS past_id,
         (SELECT log_id FROM early_leave_log WHERE user_id = t_u('emp_gh')) AS gh_id;
GRANT SELECT ON t_coord TO authenticated;
SELECT t_as(t_u('mgr_u'));
SET ROLE authenticated;
INSERT INTO t_unav SELECT 'c_el', to_jsonb(r), 1 FROM rpc_coordinate_approved_absence((SELECT el_id FROM t_coord)) r;
INSERT INTO t_unav SELECT 'c_ab', to_jsonb(r), 1 FROM rpc_coordinate_approved_absence((SELECT ab_id FROM t_coord)) r;
INSERT INTO t_unav SELECT 'c_el2', to_jsonb(r), 1 FROM rpc_coordinate_approved_absence((SELECT el_id FROM t_coord)) r;   -- idempotent
SELECT t_expect_http('J-169: a past day of a direct report cannot be coordinated (not in the list) → 403 anti_get_blocked',
  $$SELECT * FROM rpc_coordinate_approved_absence((SELECT past_id FROM t_coord))$$, 'anti_get_blocked', 403);
SELECT t_expect_http('J-169: an unknown entry → 403 access_denied',
  $$SELECT * FROM rpc_coordinate_approved_absence('00000000-0000-0000-0000-00000000dead')$$, 'access_denied', 403);
INSERT INTO t_unav SELECT 'v2', to_jsonb(v), row_number() OVER () FROM manager_unavailability_v v;
RESET ROLE;
SELECT t_assert('J-169: coordinating an early-leave row and an approved row returns ONE row each, byte-identical apart from id / pseudonym, status coordinated; repeating is idempotent',
  (SELECT count(*) = 3 AND bool_and(j->>'coordination_status' = 'coordinated') FROM t_unav WHERE label LIKE 'c\_%')
  AND (SELECT count(DISTINCT (j - 'entry_id' - 'display_pseudonym')::text) = 1 FROM t_unav WHERE label LIKE 'c\_%')
  AND (SELECT j FROM t_unav WHERE label = 'c_el') = (SELECT j FROM t_unav WHERE label = 'c_el2'));
SELECT t_assert('J-169: the list now shows the 2 rows as coordinated, the rest unchanged; the WORM early_leave_log is untouched (coordination lives in early_leave_coordination)',
  (SELECT count(*) = 2 FROM t_unav WHERE label = 'v2' AND j->>'coordination_status' = 'coordinated')
  AND (SELECT count(*) = 3 FROM t_unav WHERE label = 'v2' AND j->>'coordination_status' = 'pending_coordination')
  AND (SELECT count(*) = 1 FROM early_leave_coordination)
  AND (SELECT schedule_status = 'coordinated' FROM approved_absence_entry WHERE absence_id = (SELECT ab_id FROM t_coord)));
-- Strangers, the employee herself, and the dotted / skip level cannot coordinate.
SELECT t_as(t_u('mgr_a'));
SET ROLE authenticated;
SELECT t_expect_http('J-169: another team''s manager cannot coordinate → 403 access_denied',
  $$SELECT * FROM rpc_coordinate_approved_absence((SELECT gh_id FROM t_coord))$$, 'access_denied', 403);
SELECT t_assert('J-169: …and sees none of mgr_u''s team rows',
  NOT EXISTS (SELECT 1 FROM manager_unavailability_v v WHERE v.entry_id IN (SELECT el_id FROM t_coord UNION ALL SELECT gh_id FROM t_coord)));
SELECT t_as(t_u('dept_head'));
SELECT t_expect_http('J-169: the skip-level manager cannot coordinate → 403 access_denied',
  $$SELECT * FROM rpc_coordinate_approved_absence((SELECT gh_id FROM t_coord))$$, 'access_denied', 403);
SELECT t_as(t_u('emp_gh'));
SELECT t_expect_http('J-169: the employee cannot coordinate her own row → 403 access_denied',
  $$SELECT * FROM rpc_coordinate_approved_absence((SELECT gh_id FROM t_coord))$$, 'access_denied', 403);
SELECT t_assert('J-169: the employee sees no manager list', NOT EXISTS (SELECT 1 FROM manager_unavailability_v));
RESET ROLE;
SELECT t_assert('J-170: the manager cannot change a date — the coordinate RPC has ONE parameter (p_absence_id) and the old (uuid, date) form is gone',
  to_regprocedure('rpc_coordinate_approved_absence(uuid, date)') IS NULL
  AND to_regprocedure('rpc_coordinate_approved_absence(uuid)') IS NOT NULL);
SELECT t_assert('J-156 A: the internal helpers / coordination table are closed to clients; the old type-revealing feeds are gone',
  NOT has_function_privilege('authenticated', 'fn_unavailability_rows_of(uuid)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'fn_unavailability_entry_state(uuid)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'fn_coordinate_unavailability_entry(uuid)', 'EXECUTE')
  AND NOT has_table_privilege('authenticated', 'early_leave_coordination', 'SELECT')
  AND (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'early_leave_coordination')
  AND to_regproc('fn_early_leave_manager_feed') IS NULL AND to_regproc('fn_approved_absence_manager_feed') IS NULL);

-- vp_hr J-80 team input still works (the team summary is where absence data lives — team totals only).
SELECT t_as(t_u('vp_u'));
SET ROLE authenticated;
SELECT t_assert('J-80: vp_hr still enters the team month total (sickness + unplanned + unapproved early leave) → saved',
  (SELECT r->>'status' = 'saved' AND r->>'team' = 'TeamU'
     FROM rpc_put_team_absences('00000000-0000-0000-0000-0000000a5c01', 'TeamU', CURRENT_DATE, 1.0, 0.5, 2.0) r));
RESET ROLE;
SELECT t_assert('J-80: the team input row holds team totals only (no person column)',
  (SELECT count(*) = 1 FROM team_absence_input WHERE team_id = 'TeamU')
  AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'team_absence_input'
                   AND column_name ~* '(person|user|employee|pseudonym)'));
