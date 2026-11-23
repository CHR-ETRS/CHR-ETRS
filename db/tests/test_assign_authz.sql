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

-- Near the early-leave threshold: 6 כפיות + farming with +3 → 3 would log 'יציאה מוקדמת מאושרת' (J-260 A: the direct
-- manager is refused at ≤ 5, so the control starts at 6).
SELECT t_set_spoons('emp_a1', 6);
DROP TABLE t_before;
CREATE TEMP TABLE t_before AS SELECT t_spoons('emp_a1') AS spoons, t_task_rows('emp_a1') AS tasks, t_leave_rows('emp_a1') AS leaves;
SELECT t_assert('J-143: fixture — at 6 כפיות, no early-leave row yet', (SELECT spoons = 6 AND leaves = 0 FROM t_before));
SELECT t_as(t_u('emp_a2'));
SET ROLE authenticated;
SELECT t_expect_http('J-143: peer assigns farming +3 at the threshold → 403 access_denied',
  t_assign_sql('emp_a1', 'farming', '[3]'), 'access_denied', 403);
RESET ROLE;
SELECT t_as(t_u('mgr_b'));
SET ROLE authenticated;
SELECT t_expect_http('J-143: other-team manager assigns farming +3 at the threshold → 403 access_denied',
  t_assign_sql('emp_a1', 'farming', '[3]'), 'access_denied', 403);
RESET ROLE;
SELECT t_assert('J-143: after the failed attempts early_leave_log count unchanged (before = after)',
  t_leave_rows('emp_a1') = (SELECT leaves FROM t_before));
SELECT t_assert('J-143: after the failed attempts כפיות unchanged (6) and no task row',
  t_spoons('emp_a1') = (SELECT spoons FROM t_before) AND t_task_rows('emp_a1') = (SELECT tasks FROM t_before));
-- Control: the SAME call by the direct manager does log — so the test above is meaningful.
SELECT t_as(t_u('mgr_a'));
SET ROLE authenticated;
SELECT t_assert('J-143 control: direct manager, same call → allowed (6 → 3)',
  (SELECT s_final = 3 FROM rpc_assign_task(t_u('emp_a1'), 'farm+3', 'farming', false, false, '[3]')));
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

-- ---------- 6b. J-260 A (Karin 23.11): the direct manager is refused at 0–5 כפיות for EVERY task kind ----------
-- Fresh employee emp_a4 (team A). Farming and Fighting at each of 0, 1, 2, 3, 4, 5 → 12 refusals, all identical to
-- each other and to the J-146 A neutral answer above; nothing written. Above 5 the existing behaviour stays.
SELECT FROM t_mk('emp_a4', 'TeamA', 'employee', 'employee', 'mgr_a');
CREATE OR REPLACE FUNCTION t_j260_round(p_n int) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM t_set_spoons('emp_a4', p_n);
  PERFORM t_as(t_u('mgr_a'));
  SET LOCAL ROLE authenticated;
  INSERT INTO t_sig SELECT 'j260', p_n || ' farming', t_err_sig(t_assign_sql('emp_a4', 'farming'));
  INSERT INTO t_sig SELECT 'j260', p_n || ' fighting', t_err_sig(t_assign_sql('emp_a4', 'fighting'));
  RESET ROLE;
END $$;
DROP TABLE t_snap;
CREATE TEMP TABLE t_snap AS SELECT md5(concat_ws('|', (SELECT string_agg(t::text, ',' ORDER BY t::text) FROM task t WHERE assignee_id = t_u('emp_a4')),
                                                  (SELECT string_agg(l::text, ',' ORDER BY l::text) FROM early_leave_log l WHERE user_id = t_u('emp_a4')))) AS db;
SELECT t_j260_round(n) FROM generate_series(0, 5) n;
SELECT t_assert('J-260 A: at 0–5 כפיות the direct manager is refused for Farming AND Fighting (12 calls, 12 refusals)',
  (SELECT count(*) = 12 AND bool_and(NOT sig ? 'no_error') FROM t_sig WHERE grp = 'j260'));
SELECT t_assert('J-260 A: the 12 refusals are IDENTICAL to each other and to the J-146 A neutral answer (code, message, details, hint, context) — Farming vs Fighting no longer differ',
  (SELECT count(DISTINCT sig) = 1 FROM t_sig WHERE grp IN ('j260', 'mgr')));
SELECT t_assert('J-260 A: the refusals wrote nothing (no task, no early_leave_log for the employee; כפיות still 5)',
  md5(concat_ws('|', (SELECT string_agg(t::text, ',' ORDER BY t::text) FROM task t WHERE assignee_id = t_u('emp_a4')),
                     (SELECT string_agg(l::text, ',' ORDER BY l::text) FROM early_leave_log l WHERE user_id = t_u('emp_a4'))))
  = (SELECT db FROM t_snap) AND t_spoons('emp_a4') = 5);
SELECT t_set_spoons('emp_a4', 6);
SELECT t_as(t_u('mgr_a'));
SET ROLE authenticated;
SELECT t_assert('J-260 A: above 5 unchanged — the direct manager assigns Farming at 6 (cost 0, stays 6)',
  (SELECT task_kind = 'farming' FROM rpc_assign_task(t_u('emp_a4'), 'farm6', 'farming')));
SELECT t_assert('J-260 A: above 5 unchanged — the direct manager assigns Fighting at 6 (6 → 5)',
  (SELECT task_kind = 'fighting' FROM rpc_assign_task(t_u('emp_a4'), 'fight6', 'fighting')));
SELECT t_expect_http('J-260 A: …and at the resulting 5 the next Farming is refused with the neutral answer',
  t_assign_sql('emp_a4', 'farming'), 'assignment_unavailable', 403);
RESET ROLE;
SELECT t_assert('J-260 A: self-assignment unchanged — the J-260 check applies to someone else only (code reading: NOT v_self)',
  pg_get_functiondef('rpc_assign_task(uuid, varchar, task_kind_enum, boolean, boolean, jsonb, boolean, varchar, varchar)'::regprocedure)
    LIKE '%v_reason IS NULL AND NOT v_self AND fn_manager_assign_blocked(v_budget.current_spoon_count)%'
  AND NOT has_function_privilege('authenticated', 'fn_manager_assign_blocked(integer)', 'EXECUTE'));
SELECT t_assert('J-260 A: no cost refusal can occur above 5 for any caller — the task cost is capped at 4 (LEAST(…, 4)), so cost > כפיות needs ≤ 3',
  pg_get_functiondef('rpc_assign_task(uuid, varchar, task_kind_enum, boolean, boolean, jsonb, boolean, varchar, varchar)'::regprocedure)
    LIKE '%v_cost := LEAST(v_s_base + v_mod_sum, 4)::smallint;%');

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

-- Expect any error with SQLSTATE p_state (for 400 / permission errors that are not the 403 business contract).
CREATE OR REPLACE FUNCTION t_expect_err_any(p_name text, p_sql text, p_state text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_state text;
BEGIN
  EXECUTE p_sql;
  RAISE EXCEPTION 'FAIL % — no error (expected %)', p_name, p_state;
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE 'FAIL %' THEN RAISE; END IF;
  GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
  IF v_state = p_state THEN PERFORM t_pass(p_name); ELSE RAISE EXCEPTION 'FAIL % — got [%] %', p_name, v_state, SQLERRM; END IF;
END $$;
GRANT EXECUTE ON FUNCTION t_expect_err_any(text, text, text) TO authenticated;

-- ============ 10. v1.6.21 J-156 A / J-169 / J-170 + J-255 A / J-262 A / J-263 B (Karin 23.11) · ONE uniform manager list ============
-- Real clock (no libfaketime): every date is relative to each employee's own local today.
-- mgr_u's team, one source per employee (the HR days carry kind 'sick' for emp_sk / emp_mx and 'other' for emp_hr — J-267 C):
--   emp_el early leave via rpc_assign_task (today) · emp_gh go-home (today) · emp_ab approved absence (today, +9, past)
--   emp_tb time benefit = approved entry (+9) and a past early leave · emp_sk HR-entered sick leave (today, +9)
--   emp_hr HR-entered other absence (today, +9) · emp_mx three sources on ONE day (approved + go-home + HR, today)
-- vp_u is the company's vp_hr (enters the HR days; J-80 input).
SELECT FROM t_mk('mgr_u', 'TeamU', 'manager', 'direct_manager', 'dept_head');
SELECT count(t_mk(k, 'TeamU', 'employee', 'employee', 'mgr_u')) = 7 AS team_u_ok
  FROM unnest(ARRAY['emp_el', 'emp_gh', 'emp_ab', 'emp_tb', 'emp_sk', 'emp_hr', 'emp_mx']) k;
SELECT FROM t_mk('vp_u', 'HR', 'vp_hr', 'employee');
CREATE OR REPLACE FUNCTION t_today(p_key text) RETURNS date LANGUAGE sql SECURITY DEFINER AS $$ SELECT fn_user_local_date(t_u(p_key)) $$;
GRANT EXECUTE ON FUNCTION t_today(text) TO authenticated;
-- emp_el: the direct manager's allowed assignment (6 כפיות, cost 3 → 3 left) writes the early-leave entry.
SELECT t_set_spoons('emp_el', 6);
SELECT t_as(t_u('mgr_u'));
SET ROLE authenticated;
SELECT t_assert('J-156 A fixture: mgr_u assigns a task of cost 3 at 6 כפיות → allowed (3 left → early leave logged)',
  (SELECT assignee_id = t_u('emp_el') FROM rpc_assign_task(t_u('emp_el'), 'u-task', 'fighting', false, false, '[2]'::jsonb)));
RESET ROLE;
-- emp_gh and emp_mx go home themselves.
SELECT t_set_spoons('emp_gh', 2);
SELECT t_set_spoons('emp_mx', 2);
SELECT t_as(t_u('emp_gh'));
SET ROLE authenticated;
SELECT t_assert('J-156 A fixture: emp_gh goes home (rpc_log_go_home)', (SELECT log_id IS NOT NULL FROM rpc_log_go_home()));
SELECT t_as(t_u('emp_mx'));
SELECT t_assert('J-262 fixture: emp_mx goes home (rpc_log_go_home)', (SELECT log_id IS NOT NULL FROM rpc_log_go_home()));
RESET ROLE;
INSERT INTO approved_absence_entry (user_id, requested_date) VALUES
  (t_u('emp_ab'), t_today('emp_ab')), (t_u('emp_ab'), t_today('emp_ab') + 9), (t_u('emp_tb'), t_today('emp_tb') + 9),
  (t_u('emp_mx'), t_today('emp_mx')),
  (t_u('emp_ab'), t_today('emp_ab') - 1);                                                -- past: never listed
INSERT INTO early_leave_log (user_id, local_date) VALUES (t_u('emp_tb'), t_today('emp_tb') - 2);  -- past
-- HR days, entered by vp_hr through the RPC (sick leave for emp_sk, other HR absence for emp_hr, one for emp_mx).
CREATE TEMP TABLE t_hr (label text, j jsonb);
GRANT SELECT, INSERT ON t_hr TO authenticated;
SELECT t_as(t_u('vp_u'));
SET ROLE authenticated;
INSERT INTO t_hr SELECT k || ' ' || d, rpc_hr_absence_put('00000000-0000-0000-0000-0000000a5c01', t_u(k), t_today(k) + d,
                                                   CASE k WHEN 'emp_sk' THEN 'sick' ELSE 'other' END)
  FROM unnest(ARRAY['emp_sk', 'emp_hr']) k CROSS JOIN unnest(ARRAY[0, 9]) d;
INSERT INTO t_hr SELECT 'emp_mx 0', rpc_hr_absence_put('00000000-0000-0000-0000-0000000a5c01', t_u('emp_mx'), t_today('emp_mx'), 'sick');
INSERT INTO t_hr SELECT 'emp_sk past', rpc_hr_absence_put('00000000-0000-0000-0000-0000000a5c01', t_u('emp_sk'), t_today('emp_sk') - 3, 'sick');
INSERT INTO t_hr SELECT 'again', rpc_hr_absence_put('00000000-0000-0000-0000-0000000a5c01', t_u('emp_sk'), t_today('emp_sk'), 'sick');
RESET ROLE;
CREATE TEMP TABLE t_hr_ids AS SELECT label AS k, (j->>'entry_id')::uuid AS entry_id FROM t_hr;
GRANT SELECT ON t_hr_ids TO authenticated;
SELECT t_assert('J-263 B: vp_hr records HR days → status saved; the answer holds only entry_id, absence_date, status (no person field); re-recording an active day is idempotent (same entry)',
  (SELECT count(*) = 7 AND bool_and(j->>'status' = 'saved'
          AND (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(j) k) = ARRAY['absence_date', 'entry_id', 'status']) FROM t_hr)
  AND (SELECT j->>'entry_id' FROM t_hr WHERE label = 'again') = (SELECT j->>'entry_id' FROM t_hr WHERE label = 'emp_sk 0')
  AND (SELECT count(*) = 6 FROM hr_absence_entry));
SELECT t_assert('J-263 B: every HR write is audited (action, company, date; the employee as the audit subject), one row per call',
  (SELECT count(*) = 7 FROM access_audit_log WHERE action = 'hr_absence_put' AND viewer_id = t_u('vp_u')
          AND scope ? 'absence_date' AND scope ? 'company_id' AND subject_user_id IS NOT NULL));

-- The manager's list.
CREATE TEMP TABLE t_unav (label text, j jsonb, ord int);
GRANT SELECT, INSERT ON t_unav TO authenticated;
SELECT t_as(t_u('mgr_u'));
SET ROLE authenticated;
INSERT INTO t_unav SELECT 'v', to_jsonb(v), row_number() OVER () FROM manager_unavailability_v v;
INSERT INTO t_unav SELECT 'el', to_jsonb(v), row_number() OVER () FROM early_leave_manager_v v;
INSERT INTO t_unav SELECT 'ab', to_jsonb(v), row_number() OVER () FROM approved_absence_manager_v v;
RESET ROLE;
CREATE TEMP TABLE t_who AS
  SELECT k, (SELECT display_pseudonym FROM users WHERE user_id = t_u(k)) AS ps, t_today(k) AS today
    FROM unnest(ARRAY['emp_el', 'emp_gh', 'emp_ab', 'emp_tb', 'emp_sk', 'emp_hr', 'emp_mx']) k;
GRANT SELECT ON t_who TO authenticated;
SELECT t_assert('J-156 A / J-170 / J-262 A: 10 rows — today: early leave, go-home, approved, sick (HR), other HR, merged day; +9: approved, time benefit, sick, other HR — no past day',
  (SELECT count(*) = 10 FROM t_unav WHERE label = 'v')
  AND (SELECT count(*) = 6 FROM t_unav u JOIN t_who w ON w.ps = u.j->>'display_pseudonym'
        WHERE u.label = 'v' AND (u.j->>'unavailable_date')::date = w.today)
  AND NOT EXISTS (SELECT 1 FROM t_unav u JOIN t_who w ON w.ps = u.j->>'display_pseudonym'
                   WHERE (u.j->>'unavailable_date')::date < w.today));
SELECT t_assert('J-156 A / J-255 A / J-263 B: ALL 10 rows (7 absence types incl. sick and HR, today and future) are byte-identical apart from entry id, pseudonym and date: same keys, "לא זמינה", pending_coordination',
  (SELECT count(DISTINCT (j - 'entry_id' - 'display_pseudonym' - 'unavailable_date')::text) = 1
          AND bool_and(j->>'availability_he' = 'לא זמינה' AND j->>'coordination_status' = 'pending_coordination')
     FROM t_unav WHERE label = 'v'));
SELECT t_assert('J-263 B: the sick-leave row and the other-HR row are byte-identical to the early-leave and approved rows of the same day (only id / pseudonym differ)',
  (SELECT count(*) = 4 AND count(DISTINCT (j - 'entry_id' - 'display_pseudonym')::text) = 1
     FROM t_unav u JOIN t_who w ON w.ps = u.j->>'display_pseudonym'
    WHERE u.label = 'v' AND w.k IN ('emp_el', 'emp_ab', 'emp_sk', 'emp_hr') AND (u.j->>'unavailable_date')::date = w.today));
SELECT t_assert('J-262 A: three sources of emp_mx on one day → ONE row; its entry_id is the smallest id of the three parts',
  (SELECT count(*) = 1 FROM t_unav u JOIN t_who w ON w.ps = u.j->>'display_pseudonym' WHERE u.label = 'v' AND w.k = 'emp_mx')
  AND (SELECT u.j->>'entry_id' FROM t_unav u JOIN t_who w ON w.ps = u.j->>'display_pseudonym' WHERE u.label = 'v' AND w.k = 'emp_mx')
      = (SELECT min(id::text) FROM (SELECT absence_id AS id FROM approved_absence_entry WHERE user_id = t_u('emp_mx')
                                    UNION ALL SELECT log_id FROM early_leave_log WHERE user_id = t_u('emp_mx')
                                    UNION ALL SELECT entry_id FROM hr_absence_entry WHERE user_id = t_u('emp_mx')) x));
SELECT t_assert('J-262 A: …and that merged row is byte-identical to a single-source row of the same day (no count, no hint of several sources)',
  (SELECT count(DISTINCT (j - 'entry_id' - 'display_pseudonym')::text) = 1
     FROM t_unav u JOIN t_who w ON w.ps = u.j->>'display_pseudonym'
    WHERE u.label = 'v' AND w.k IN ('emp_mx', 'emp_gh') AND (u.j->>'unavailable_date')::date = w.today));
SELECT t_assert('J-156 A: every row has exactly the 5 uniform keys (entry_id, display_pseudonym, unavailable_date, availability_he, coordination_status)',
  (SELECT bool_and((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(j) k)
                   = ARRAY['availability_he', 'coordination_status', 'display_pseudonym', 'entry_id', 'unavailable_date'])
     FROM t_unav));
SELECT t_assert('J-156 A / J-255 A: no time, כפיות, type, source text, count or history in the manager output (no "להמשך היום", "יציאה מוקדמת", "זמן התרעננות", sick / HR wording, clock time)',
  (SELECT bool_and(j::text !~* '(left_at|spoon|entry_type|entry_text|created_at|count|history|sick|hr_|להמשך|יציאה|מוקדמת|התרעננות|היעדרות|מחלה|[0-9]{2}:[0-9]{2})')
     FROM t_unav));
SELECT t_assert('J-156 A: no manager-facing column exposes time, כפיות, type, source text, a count or a person (catalog: the 3 views + the coordinate RPC result)',
  NOT EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name IN ('manager_unavailability_v', 'early_leave_manager_v', 'approved_absence_manager_v')
                 AND column_name ~* '(left_at|spoon|entry_type|entry_text|created_at|count|reason|user_id|person|kind)')
  AND (SELECT pg_get_function_result('rpc_coordinate_approved_absence(uuid)'::regprocedure)
       = 'TABLE(entry_id uuid, display_pseudonym character varying, unavailable_date date, availability_he text, coordination_status text)'));
SELECT t_assert('J-256: neutral order — by date, then pseudonym, then id (never by type / source / time)',
  (SELECT array_agg(j ORDER BY ord) = array_agg(j ORDER BY (j->>'unavailable_date')::date, j->>'display_pseudonym', j->>'entry_id')
     FROM t_unav WHERE label = 'v'));
SELECT t_assert('J-258 A: early_leave_manager_v and approved_absence_manager_v are byte-identical aliases of the one list (same rows, same order)',
  (SELECT array_agg(j ORDER BY ord) FROM t_unav WHERE label = 'el') = (SELECT array_agg(j ORDER BY ord) FROM t_unav WHERE label = 'v')
  AND (SELECT array_agg(j ORDER BY ord) FROM t_unav WHERE label = 'ab') = (SELECT array_agg(j ORDER BY ord) FROM t_unav WHERE label = 'v'));

-- Coordination: every source; a merged day by ANY of its parts' ids coordinates all parts.
CREATE TEMP TABLE t_coord AS
  SELECT (SELECT log_id FROM early_leave_log WHERE user_id = t_u('emp_el') AND local_date = t_today('emp_el')) AS el_id,
         (SELECT absence_id FROM approved_absence_entry WHERE user_id = t_u('emp_ab') AND requested_date = t_today('emp_ab')) AS ab_id,
         (SELECT entry_id FROM hr_absence_entry WHERE user_id = t_u('emp_sk') AND absence_date = t_today('emp_sk')) AS sk_id,
         (SELECT entry_id FROM hr_absence_entry WHERE user_id = t_u('emp_sk') AND absence_date < t_today('emp_sk')) AS sk_past_id,
         (SELECT log_id FROM early_leave_log WHERE user_id = t_u('emp_tb') AND local_date < t_today('emp_tb')) AS past_id,
         (SELECT log_id FROM early_leave_log WHERE user_id = t_u('emp_gh')) AS gh_id,
         (SELECT max(id::text)::uuid FROM (SELECT absence_id AS id FROM approved_absence_entry WHERE user_id = t_u('emp_mx')
                                           UNION ALL SELECT log_id FROM early_leave_log WHERE user_id = t_u('emp_mx')
                                           UNION ALL SELECT entry_id FROM hr_absence_entry WHERE user_id = t_u('emp_mx')) x) AS mx_part_id;
GRANT SELECT ON t_coord TO authenticated;
SELECT t_as(t_u('mgr_u'));
SET ROLE authenticated;
INSERT INTO t_unav SELECT 'c_el', to_jsonb(r), 1 FROM rpc_coordinate_approved_absence((SELECT el_id FROM t_coord)) r;
INSERT INTO t_unav SELECT 'c_ab', to_jsonb(r), 1 FROM rpc_coordinate_approved_absence((SELECT ab_id FROM t_coord)) r;
INSERT INTO t_unav SELECT 'c_sk', to_jsonb(r), 1 FROM rpc_coordinate_approved_absence((SELECT sk_id FROM t_coord)) r;
INSERT INTO t_unav SELECT 'c_mx', to_jsonb(r), 1 FROM rpc_coordinate_approved_absence((SELECT mx_part_id FROM t_coord)) r;
INSERT INTO t_unav SELECT 'c_el2', to_jsonb(r), 1 FROM rpc_coordinate_approved_absence((SELECT el_id FROM t_coord)) r;   -- idempotent
SELECT t_expect_http('J-169: a past day of a direct report cannot be coordinated (not in the list) → 403 anti_get_blocked',
  $$SELECT * FROM rpc_coordinate_approved_absence((SELECT past_id FROM t_coord))$$, 'anti_get_blocked', 403);
SELECT t_expect_http('J-263 B: a past HR day of a direct report → the same 403 anti_get_blocked',
  $$SELECT * FROM rpc_coordinate_approved_absence((SELECT sk_past_id FROM t_coord))$$, 'anti_get_blocked', 403);
SELECT t_expect_http('J-169: an unknown entry → 403 access_denied',
  $$SELECT * FROM rpc_coordinate_approved_absence('00000000-0000-0000-0000-00000000dead')$$, 'access_denied', 403);
INSERT INTO t_unav SELECT 'v2', to_jsonb(v), row_number() OVER () FROM manager_unavailability_v v;
RESET ROLE;
SELECT t_assert('J-169: coordinating an early-leave, an approved, an HR (sick) and a merged row returns ONE row each, byte-identical apart from id / pseudonym, status coordinated; repeating is idempotent',
  (SELECT count(*) = 5 AND bool_and(j->>'coordination_status' = 'coordinated') FROM t_unav WHERE label LIKE 'c\_%')
  AND (SELECT count(DISTINCT (j - 'entry_id' - 'display_pseudonym')::text) = 1 FROM t_unav WHERE label LIKE 'c\_%')
  AND (SELECT j FROM t_unav WHERE label = 'c_el') = (SELECT j FROM t_unav WHERE label = 'c_el2'));
SELECT t_assert('J-262 A: coordinating the merged day by one part id (not the row id) coordinated ALL 3 parts and returned the merged row (its entry_id = the smallest part id)',
  (SELECT schedule_status = 'coordinated' FROM approved_absence_entry WHERE user_id = t_u('emp_mx'))
  AND EXISTS (SELECT 1 FROM early_leave_coordination c JOIN early_leave_log l USING (log_id) WHERE l.user_id = t_u('emp_mx'))
  AND (SELECT coordination_status = 'coordinated' FROM hr_absence_entry WHERE user_id = t_u('emp_mx'))
  AND (SELECT j->>'entry_id' FROM t_unav WHERE label = 'c_mx')
      = (SELECT u.j->>'entry_id' FROM t_unav u JOIN t_who w ON w.ps = u.j->>'display_pseudonym' WHERE u.label = 'v' AND w.k = 'emp_mx')
  AND (SELECT j->>'entry_id' FROM t_unav WHERE label = 'c_mx') <> (SELECT mx_part_id::text FROM t_coord));
SELECT t_assert('J-169: the list now shows 4 coordinated rows (early leave, approved, sick, merged day) and 6 pending; the WORM early_leave_log is untouched',
  (SELECT count(*) = 4 FROM t_unav WHERE label = 'v2' AND j->>'coordination_status' = 'coordinated')
  AND (SELECT count(*) = 6 FROM t_unav WHERE label = 'v2' AND j->>'coordination_status' = 'pending_coordination')
  AND (SELECT count(*) = 2 FROM early_leave_coordination));
-- A new part on an already coordinated day makes the merged row pending again (J-262 A: coordinated only when all are).
SELECT t_as(t_u('vp_u'));
SET ROLE authenticated;
SELECT t_assert('J-262 A fixture: vp_hr adds an HR day for emp_el on her already coordinated early-leave day',
  (SELECT rpc_hr_absence_put('00000000-0000-0000-0000-0000000a5c01', t_u('emp_el'), t_today('emp_el'), 'other')->>'status' = 'saved'));
SELECT t_as(t_u('mgr_u'));
SELECT t_assert('J-262 A: emp_el still has ONE row today, now pending_coordination (a part is not coordinated yet)',
  (SELECT count(*) = 1 AND bool_and(coordination_status = 'pending_coordination') FROM manager_unavailability_v
    WHERE display_pseudonym = (SELECT ps FROM t_who WHERE k = 'emp_el')));
RESET ROLE;
-- Strangers, the skip level and the employee herself cannot coordinate.
SELECT t_as(t_u('mgr_a'));
SET ROLE authenticated;
SELECT t_expect_http('J-169: another team''s manager cannot coordinate → 403 access_denied',
  $$SELECT * FROM rpc_coordinate_approved_absence((SELECT gh_id FROM t_coord))$$, 'access_denied', 403);
SELECT t_assert('J-169: …and sees none of mgr_u''s team rows',
  NOT EXISTS (SELECT 1 FROM manager_unavailability_v v WHERE v.entry_id IN (SELECT el_id FROM t_coord UNION ALL SELECT gh_id FROM t_coord UNION ALL SELECT sk_id FROM t_coord)));
SELECT t_as(t_u('dept_head'));
SELECT t_expect_http('J-169: the skip-level manager cannot coordinate → 403 access_denied',
  $$SELECT * FROM rpc_coordinate_approved_absence((SELECT gh_id FROM t_coord))$$, 'access_denied', 403);
SELECT t_as(t_u('emp_gh'));
SELECT t_expect_http('J-169: the employee cannot coordinate her own row → 403 access_denied',
  $$SELECT * FROM rpc_coordinate_approved_absence((SELECT gh_id FROM t_coord))$$, 'access_denied', 403);
SELECT t_assert('J-169: the employee sees no manager list', NOT EXISTS (SELECT 1 FROM manager_unavailability_v));
RESET ROLE;

-- J-263 B: who may write HR days, cancellation, the employee's own rows, the table's shape.
SELECT t_as(t_u('mgr_u'));
SET ROLE authenticated;
SELECT t_expect_http('J-270: the direct manager cannot record an HR day → 403 insufficient_privilege (vp_hr only)',
  $$SELECT rpc_hr_absence_put('00000000-0000-0000-0000-0000000a5c01', t_u('emp_gh'), t_today('emp_gh') + 1, 'sick')$$, 'insufficient_privilege', 403);
SELECT t_as(t_u('emp_sk'));
SELECT t_expect_http('J-270: the employee cannot record an HR day for herself → 403 insufficient_privilege',
  $$SELECT rpc_hr_absence_put('00000000-0000-0000-0000-0000000a5c01', t_u('emp_sk'), t_today('emp_sk') + 1, 'sick')$$, 'insufficient_privilege', 403);
SELECT t_assert('J-269: the employee reads her OWN HR rows only (3: today, +9, past) and no one else''s',
  (SELECT count(*) = 3 AND bool_and(user_id = t_u('emp_sk')) FROM hr_absence_entry));
SELECT t_expect_err_any('J-263 B: no client may write the table directly (insert → permission denied)',
  $$INSERT INTO hr_absence_entry (user_id, company_id, absence_date) VALUES (t_u('emp_sk'), '00000000-0000-0000-0000-0000000a5c01', CURRENT_DATE + 20)$$, '42501');
SELECT t_as(t_u('mgr_u'));
SELECT t_assert('J-263 B: the manager reads no HR row directly (own-rows RLS)', NOT EXISTS (SELECT 1 FROM hr_absence_entry));
SELECT t_as(t_u('vp_u'));
SELECT t_expect_http('J-263 B: an ex-employee (or anyone outside the company) → 403 access_denied, no existence hint',
  $$SELECT rpc_hr_absence_put('00000000-0000-0000-0000-0000000a5c01', t_u('emp_a3'), CURRENT_DATE, 'sick')$$, 'access_denied', 403);
SELECT t_assert('J-263 B: vp_hr cancels emp_hr''s +9 day → cancelled (status only)',
  (SELECT rpc_hr_absence_cancel('00000000-0000-0000-0000-0000000a5c01', t_u('emp_hr'), t_today('emp_hr') + 9)->>'status' = 'cancelled'));
SELECT t_expect_err_any('J-263 B: cancelling a day with no entry → 400 invalid_requested_date',
  $$SELECT rpc_hr_absence_cancel('00000000-0000-0000-0000-0000000a5c01', t_u('emp_hr'), t_today('emp_hr') + 30)$$, '22023');
SELECT t_as(t_u('mgr_u'));
SELECT t_assert('J-263 B: the cancelled HR day is gone from the manager''s list (emp_hr keeps only today)',
  (SELECT count(*) = 1 FROM manager_unavailability_v WHERE display_pseudonym = (SELECT ps FROM t_who WHERE k = 'emp_hr')));
SELECT t_as(t_u('vp_u'));
SELECT t_assert('J-263 B: re-recording the cancelled day re-opens the SAME entry as pending_coordination',
  (SELECT (rpc_hr_absence_put('00000000-0000-0000-0000-0000000a5c01', t_u('emp_hr'), t_today('emp_hr') + 9, 'other')->>'entry_id')::uuid
          = (SELECT entry_id FROM t_hr_ids WHERE k = 'emp_hr 9')));
RESET ROLE;
SELECT t_assert('J-263 B: the re-opened row is active and pending; cancelling never deleted a row (6 + 1 HR rows exist)',
  (SELECT cancelled_at IS NULL AND coordination_status = 'pending_coordination' FROM hr_absence_entry
    WHERE user_id = t_u('emp_hr') AND absence_date = t_today('emp_hr') + 9)
  AND (SELECT count(*) = 7 FROM hr_absence_entry)
  AND (SELECT count(*) = 1 FROM access_audit_log WHERE action = 'hr_absence_cancel'));
SELECT t_assert('J-267 C / J-263 B: hr_absence_entry has the required kind (sick / other) but no reason, text, diagnosis or person-name column; RLS forced; no client insert / update / delete; the write RPCs are vp_hr-checked SECURITY DEFINER',
  (SELECT array_agg(column_name::text ORDER BY column_name) FROM information_schema.columns WHERE table_name = 'hr_absence_entry')
    = ARRAY['absence_date', 'absence_kind', 'cancelled_at', 'company_id', 'coordination_status', 'entered_at', 'entry_id', 'user_id']
  AND (SELECT is_nullable = 'NO' FROM information_schema.columns WHERE table_name = 'hr_absence_entry' AND column_name = 'absence_kind')
  AND (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE relname = 'hr_absence_entry')
  AND NOT has_table_privilege('authenticated', 'hr_absence_entry', 'INSERT')
  AND NOT has_table_privilege('authenticated', 'hr_absence_entry', 'UPDATE')
  AND NOT has_table_privilege('authenticated', 'hr_absence_entry', 'DELETE')
  AND NOT has_table_privilege('anon', 'hr_absence_entry', 'SELECT')
  AND (SELECT bool_and(prosecdef AND prosrc LIKE '%fn_assert_vp_hr(p_company_id)%') FROM pg_proc
        WHERE proname IN ('rpc_hr_absence_put', 'rpc_hr_absence_cancel'))
  AND obj_description('hr_absence_entry'::regclass) LIKE '%Retention: לא הוגדר%');

SELECT t_assert('J-257 A: the manager cannot change a date — the coordinate RPC has ONE parameter (p_absence_id) and the old (uuid, date) form is gone',
  to_regprocedure('rpc_coordinate_approved_absence(uuid, date)') IS NULL
  AND to_regprocedure('rpc_coordinate_approved_absence(uuid)') IS NOT NULL);
SELECT t_assert('J-156 A: the internal helpers / coordination table are closed to clients; the old type-revealing feeds and the date-based text are gone',
  NOT has_function_privilege('authenticated', 'fn_unavailability_rows_of(uuid)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'fn_manager_unavailability_parts()', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'fn_unavailability_entry_state(uuid)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'fn_coordinate_unavailability_entry(uuid)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'fn_assert_hr_absence_target(uuid, uuid)', 'EXECUTE')
  AND NOT has_table_privilege('authenticated', 'early_leave_coordination', 'SELECT')
  AND (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'early_leave_coordination')
  AND to_regproc('fn_early_leave_manager_feed') IS NULL AND to_regproc('fn_approved_absence_manager_feed') IS NULL
  AND to_regprocedure('fn_unavailable_text_he(date, date)') IS NULL AND fn_unavailable_text_he() = 'לא זמינה');

-- vp_hr J-80 team input still works (team totals only; the HR days do not feed it — J-272).
SELECT t_as(t_u('vp_u'));
SET ROLE authenticated;
SELECT t_assert('J-80: vp_hr still enters the team month total (sickness + unplanned + unapproved early leave) → saved',
  (SELECT r->>'status' = 'saved' AND r->>'team' = 'TeamU'
     FROM rpc_put_team_absences('00000000-0000-0000-0000-0000000a5c01', 'TeamU', CURRENT_DATE, 1.0, 0.5, 2.0) r));
RESET ROLE;
SELECT t_assert('J-80: the team input row holds team totals only (no person column), unchanged by the HR days',
  (SELECT count(*) = 1 AND bool_and(sickness_days = 1.0 AND unplanned_absence_days = 0.5) FROM team_absence_input WHERE team_id = 'TeamU')
  AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'team_absence_input'
                   AND column_name ~* '(person|user|employee|pseudonym)'));

-- ============ 11. J-267 C / J-269 A / J-270 A (Karin 23.11) · who can read the kind (health data) ============
-- Readers allowed: the company's vp_hr (rpc_hr_absence_list, audited) and the employee herself (own rows). Nobody
-- else — not the direct manager, another employee, cfo, legal_ethics, board_chair, board_member, owner_shareholder,
-- or the vp_hr of another company — and no view. (Test helpers t_* are excluded from the catalog checks.)
SELECT count(t_mk(k, 'Gov', r, 'employee')) = 5 AS roles_ok
  FROM (VALUES ('cfo_u', 'cfo'), ('le_u', 'legal_ethics'), ('bc_u', 'board_chair'), ('bm_u', 'board_member'),
               ('os_u', 'owner_shareholder')) v(k, r);
INSERT INTO companies (company_id, company_name, country, week_start_dow, last_workday_dow, timezone)
VALUES ('00000000-0000-0000-0000-0000000a5c02', 'SickCo', 'IL', 0, 4, 'Asia/Jerusalem');
-- Create one fixture user of SickCo (same shape as t_mk, other company).
CREATE OR REPLACE FUNCTION t_mk2(p_key text, p_team text, p_role text) RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id) VALUES (t_u(p_key));
  INSERT INTO users (user_id, company_id, email, full_name, department, app_role, org_role_code, timezone, hire_date)
  VALUES (t_u(p_key), '00000000-0000-0000-0000-0000000a5c02', p_key || '@sick.test', 'Fixture ' || p_key, p_team, p_role,
          'employee', 'Asia/Jerusalem', DATE '2025-01-01');
  RETURN t_u(p_key);
END $$;
SELECT t_mk2('vp_s', 'S1', 'vp_hr') IS NOT NULL AS vp_s_ok;
CREATE TEMP TABLE t_kind (label text, j jsonb);
GRANT SELECT, INSERT ON t_kind TO authenticated;
SELECT t_as(t_u('vp_u'));
SET ROLE authenticated;
INSERT INTO t_kind SELECT 'vp sk', jsonb_agg(to_jsonb(r) ORDER BY r.absence_date) FROM rpc_hr_absence_list('00000000-0000-0000-0000-0000000a5c01', t_u('emp_sk')) r;
INSERT INTO t_kind SELECT 'vp hr', jsonb_agg(to_jsonb(r) ORDER BY r.absence_date) FROM rpc_hr_absence_list('00000000-0000-0000-0000-0000000a5c01', t_u('emp_hr')) r;
SELECT t_expect_err_any('J-267 C: an unknown kind is refused → 400 invalid_absence_kind',
  $$SELECT rpc_hr_absence_put('00000000-0000-0000-0000-0000000a5c01', t_u('emp_gh'), t_today('emp_gh') + 2, 'flu')$$, '22023');
SELECT t_expect_err_any('J-267 C: the kind is required (NULL) → 400 invalid_absence_kind',
  $$SELECT rpc_hr_absence_put('00000000-0000-0000-0000-0000000a5c01', t_u('emp_gh'), t_today('emp_gh') + 2, NULL)$$, '22023');
RESET ROLE;
SELECT t_assert('J-267 C: vp_hr reads the kind per day of the employee she names — emp_sk: 3 sick days (today, +9, past); emp_hr: 2 other days; no person field in the rows',
  (SELECT jsonb_array_length(j) = 3 AND (SELECT bool_and(e->>'absence_kind' = 'sick') FROM jsonb_array_elements(j) e) FROM t_kind WHERE label = 'vp sk')
  AND (SELECT jsonb_array_length(j) = 2 AND (SELECT bool_and(e->>'absence_kind' = 'other') FROM jsonb_array_elements(j) e) FROM t_kind WHERE label = 'vp hr')
  AND (SELECT bool_and(NOT (j::text ~* '(user_id|person|pseudonym|full_name|email)')) FROM t_kind));
SELECT t_assert('J-280: every vp_hr read is audited (hr_absence_read, the employee as subject) and NO audit row holds the kind',
  (SELECT count(*) = 2 FROM access_audit_log WHERE action = 'hr_absence_read' AND viewer_id = t_u('vp_u') AND subject_user_id IS NOT NULL)
  AND NOT EXISTS (SELECT 1 FROM access_audit_log WHERE action LIKE 'hr_absence%' AND (scope::text ~* '(sick|other|kind)' OR reason IS NOT NULL)));
SELECT t_as(t_u('emp_sk'));
SET ROLE authenticated;
SELECT t_assert('J-269 A: the employee reads her OWN HR days WITH the kind (3 sick) and nothing of anyone else',
  (SELECT count(*) = 3 AND bool_and(user_id = t_u('emp_sk') AND absence_kind = 'sick') FROM hr_absence_entry));
SELECT t_expect_http('J-267 C: the employee cannot use the vp_hr reader, not even for herself → 403 insufficient_privilege',
  $$SELECT * FROM rpc_hr_absence_list('00000000-0000-0000-0000-0000000a5c01', t_u('emp_sk'))$$, 'insufficient_privilege', 403);
SELECT t_as(t_u('emp_hr'));
SELECT t_assert('J-269 A: another employee sees only her own days (2 other) — never emp_sk''s sick days',
  (SELECT count(*) = 2 AND bool_and(user_id = t_u('emp_hr') AND absence_kind = 'other') FROM hr_absence_entry));
RESET ROLE;
-- Every other role: no row through the table, refused by the reader.
CREATE OR REPLACE FUNCTION t_kind_probe(p_key text, p_company uuid DEFAULT '00000000-0000-0000-0000-0000000a5c01') RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_rows int; v_sig jsonb;
BEGIN
  PERFORM t_as(t_u(p_key));
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_rows FROM hr_absence_entry WHERE user_id <> t_u(p_key);
  v_sig := t_err_sig(format('SELECT * FROM rpc_hr_absence_list(%L, %L)', p_company, t_u('emp_sk')));
  RESET ROLE;
  INSERT INTO t_kind VALUES ('probe ' || p_key, jsonb_build_object('rows', v_rows, 'msg', v_sig->>'message'));
END $$;
SELECT t_kind_probe(k) FROM unnest(ARRAY['mgr_u', 'emp_gh', 'cfo_u', 'le_u', 'bc_u', 'bm_u', 'os_u', 'dept_head']) k;
SELECT t_kind_probe('vp_s', '00000000-0000-0000-0000-0000000a5c01');
SELECT t_kind_probe('vp_s', '00000000-0000-0000-0000-0000000a5c02');
SELECT t_assert('J-267 C: the direct manager, another employee, cfo, legal_ethics, board_chair, board_member, owner_shareholder, the skip level and another company''s vp_hr read NO HR row and are refused by the reader',
  (SELECT count(*) = 10 AND bool_and((j->>'rows')::int = 0 AND j->>'msg' IN ('insufficient_privilege', 'access_denied'))
     FROM t_kind WHERE label LIKE 'probe %'));
SELECT t_assert('J-267 C: catalog — the kind is in no view, and the only client-callable functions that touch hr_absence_entry are the three vp_hr RPCs (only put / list name the kind)',
  NOT EXISTS (SELECT 1 FROM information_schema.columns c JOIN information_schema.views v
                ON v.table_schema = c.table_schema AND v.table_name = c.table_name
               WHERE c.column_name = 'absence_kind')
  AND (SELECT array_agg(p.proname::text ORDER BY p.proname) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname !~ '^t_' AND p.prosrc LIKE '%hr_absence_entry%'
          AND (has_function_privilege('authenticated', p.oid, 'EXECUTE') OR has_function_privilege('anon', p.oid, 'EXECUTE')))
      = ARRAY['rpc_hr_absence_cancel', 'rpc_hr_absence_list', 'rpc_hr_absence_put']
  AND (SELECT array_agg(p.proname::text ORDER BY p.proname) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname !~ '^t_' AND (p.prosrc LIKE '%absence_kind%' OR pg_get_function_result(p.oid) LIKE '%absence_kind%')
          AND has_function_privilege('authenticated', p.oid, 'EXECUTE'))
      = ARRAY['rpc_hr_absence_list', 'rpc_hr_absence_put']);
-- A kind correction is invisible to the manager (her row stays byte-identical).
CREATE TEMP TABLE t_kind_mgr (label text, j jsonb);
GRANT SELECT, INSERT ON t_kind_mgr TO authenticated;
SELECT t_as(t_u('mgr_u'));
SET ROLE authenticated;
INSERT INTO t_kind_mgr SELECT 'before', jsonb_agg(to_jsonb(v) ORDER BY v.entry_id) FROM manager_unavailability_v v;
SELECT t_as(t_u('vp_u'));
INSERT INTO t_kind_mgr SELECT 'put', rpc_hr_absence_put('00000000-0000-0000-0000-0000000a5c01', t_u('emp_mx'), t_today('emp_mx'), 'other');
SELECT t_as(t_u('mgr_u'));
INSERT INTO t_kind_mgr SELECT 'after', jsonb_agg(to_jsonb(v) ORDER BY v.entry_id) FROM manager_unavailability_v v;
RESET ROLE;
SELECT t_assert('J-279: vp_hr corrects emp_mx''s day from sick to other → same entry, coordination kept; the manager''s whole list is byte-identical before and after',
  (SELECT absence_kind = 'other' AND coordination_status = 'coordinated' FROM hr_absence_entry WHERE user_id = t_u('emp_mx'))
  AND (SELECT j FROM t_kind_mgr WHERE label = 'before') = (SELECT j FROM t_kind_mgr WHERE label = 'after'));

-- ============ 12. J-272 B / J-276 / J-277 (Karin 23.11) · HR sick days in the J-80 / J-53 team and board totals ============
-- SickCo: team S1 (vp_s + s1–s6 = 7 members), team S2 (t1–t5 = 5 members). Month = the current calendar month.
SELECT count(t_mk2(k, 'S1', 'employee')) = 6 AS s1_ok FROM unnest(ARRAY['s1', 's2', 's3', 's4', 's5', 's6']) k;
SELECT count(t_mk2(k, 'S2', 'employee')) = 5 AS s2_ok FROM unnest(ARRAY['t1', 't2', 't3', 't4', 't5']) k;
CREATE TEMP TABLE t_m AS SELECT date_trunc('month', CURRENT_DATE)::date AS m;
GRANT SELECT ON t_m TO authenticated;
CREATE TEMP TABLE t_tot (label text, j jsonb);
GRANT SELECT, INSERT ON t_tot TO authenticated;
SELECT t_as(t_u('vp_s'));
SET ROLE authenticated;
INSERT INTO t_tot SELECT 'put ' || k || ' ' || d || ' ' || kind,
       rpc_hr_absence_put('00000000-0000-0000-0000-0000000a5c02', t_u(k), (SELECT m FROM t_m) + d, kind)
  FROM (VALUES ('s1', 0, 'sick'), ('s1', 1, 'sick'), ('s1', 2, 'sick'), ('s1', 3, 'other'), ('s2', 0, 'sick'),
               ('s3', 4, 'sick'), ('t1', 0, 'sick'), ('s1', -5, 'sick'), ('s1', 0, 'sick')) v(k, d, kind);
SELECT t_assert('J-272 fixture: s2''s sick day is cancelled', (SELECT rpc_hr_absence_cancel('00000000-0000-0000-0000-0000000a5c02', t_u('s2'), (SELECT m FROM t_m))->>'status' = 'cancelled'));
RESET ROLE;
-- The same employee-day of s1 also exists in two other sources (an approved absence and a go-home day).
INSERT INTO approved_absence_entry (user_id, requested_date) VALUES (t_u('s1'), (SELECT m FROM t_m));
INSERT INTO early_leave_log (user_id, local_date) VALUES (t_u('s1'), (SELECT m FROM t_m));
SELECT t_assert('J-272 B: HR sick days of S1 this month = 4 distinct employee-days (s1 × 3 + s3 × 1): the re-recorded day, the other-kind day, the cancelled day, the previous-month day and the same day in two other sources are NOT counted again',
  fn_hr_sick_days('00000000-0000-0000-0000-0000000a5c02', 'S1', (SELECT m FROM t_m)) = 4
  AND fn_hr_sick_days('00000000-0000-0000-0000-0000000a5c02', 'S2', (SELECT m FROM t_m)) = 1);
SELECT t_assert('J-277: without the vp_hr manual row the team total stays NULL (''חסר''), even with HR sick days; the board shows ''חסר''',
  fn_team_absence_days('00000000-0000-0000-0000-0000000a5c02', 'S1', (SELECT m FROM t_m)) IS NULL
  AND fn_board_absences_json('00000000-0000-0000-0000-0000000a5c02', (SELECT m FROM t_m))->>'display_he' = 'חסר: team_absence_input');
SELECT t_as(t_u('vp_s'));
SET ROLE authenticated;
INSERT INTO t_tot SELECT 'man S1', rpc_put_team_absences('00000000-0000-0000-0000-0000000a5c02', 'S1', (SELECT m FROM t_m), 2.0, 1.0, 1.0);
INSERT INTO t_tot SELECT 'man S2', rpc_put_team_absences('00000000-0000-0000-0000-0000000a5c02', 'S2', (SELECT m FROM t_m), 3.0, 0.0, 0.0);
RESET ROLE;
SELECT t_assert('J-276: team total = the LARGER of manual sickness and HR sick days + unplanned + unapproved early leave — S1: max(2, 4) + 1 + 1 = 6; S2: max(3, 1) + 0 + 0 = 3 (never 2 + 4 or 3 + 1)',
  fn_team_absence_days('00000000-0000-0000-0000-0000000a5c02', 'S1', (SELECT m FROM t_m)) = 6
  AND fn_team_absence_days('00000000-0000-0000-0000-0000000a5c02', 'S2', (SELECT m FROM t_m)) = 3
  AND fn_combined_sickness_days(2, 4) = 4 AND fn_combined_sickness_days(5, 4) = 5 AND fn_combined_sickness_days(NULL, 4) IS NULL);
SELECT t_assert('J-272 B / J-276: the board total sums the combined team sickness — sickness 4 + 3 = 7, days 7 + 1 + 1 = 9, 2 teams; no person field',
  (SELECT (j->>'sickness_days')::numeric = 7 AND (j->>'days')::numeric = 9 AND (j->>'teams_count')::int = 2
          AND NOT (j::text ~* '(user_id|person|pseudonym|[0-9a-f]{8}-[0-9a-f]{4})')
     FROM (SELECT fn_board_absences_json('00000000-0000-0000-0000-0000000a5c02', (SELECT m FROM t_m)) AS j) x));
-- Thresholds unchanged: a team of < 5 is not shown by the burnout signal; small teams whose combined size is 1–4
-- hide the board total — even when one of them has an HR sick day.
SELECT count(t_mk2(k, 'S3', 'employee')) = 2 AS s3_ok FROM unnest(ARRAY['u1', 'u2']) k;
SELECT t_as(t_u('vp_s'));
SET ROLE authenticated;
INSERT INTO t_tot SELECT 'put u1', rpc_hr_absence_put('00000000-0000-0000-0000-0000000a5c02', t_u('u1'), (SELECT m FROM t_m), 'sick');
INSERT INTO t_tot SELECT 'man S3', rpc_put_team_absences('00000000-0000-0000-0000-0000000a5c02', 'S3', (SELECT m FROM t_m), 0.0, 0.0, 0.0);
RESET ROLE;
SELECT t_assert('Thresholds: the 2-person team''s HR sick day counts in its own total (max(0, 1) = 1) but the board total is hidden (small teams of combined size 2) — "אין מספיק עובדים להצגה"',
  fn_team_absence_days('00000000-0000-0000-0000-0000000a5c02', 'S3', (SELECT m FROM t_m)) = 1
  AND fn_board_absences_json('00000000-0000-0000-0000-0000000a5c02', (SELECT m FROM t_m))->>'display_he' = 'אין מספיק עובדים להצגה'
  AND NOT (fn_board_absences_json('00000000-0000-0000-0000-0000000a5c02', (SELECT m FROM t_m)) ? 'days'));
SELECT t_assert('Thresholds: the burnout absences signal of a team with < 5 employees is not shown even with HR sick days (team threshold 5 unchanged)',
  fn_team_absence_signal('00000000-0000-0000-0000-0000000a5c02',
                         ARRAY[NULL, NULL, fn_team_absence_days('00000000-0000-0000-0000-0000000a5c02', 'S3', (SELECT m FROM t_m))]::numeric[],
                         3, 2, fn_absence_group_members('00000000-0000-0000-0000-0000000a5c02', 'S3', (SELECT m FROM t_m)))->>'display_he'
  = 'אין מספיק עובדים להצגה');
SELECT t_assert('J-272 B: the new total helpers are internal (no client grant)',
  NOT has_function_privilege('authenticated', 'fn_hr_sick_days(uuid, character varying, date)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'fn_combined_sickness_days(numeric, numeric)', 'EXECUTE'));
