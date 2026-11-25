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
SELECT t_assert('J-269 / J-291 B: the employee reads her OWN HR rows only (3: today, +9, past) through the audited self-read RPC',
  (SELECT count(*) = 3 FROM rpc_hr_absence_my_list()));
SELECT t_expect_err_any('J-291 B: the direct table read is revoked — the employee cannot bypass the self-read log (permission denied)',
  $$SELECT count(*) FROM hr_absence_entry$$, '42501');
SELECT t_expect_err_any('J-263 B: no client may write the table directly (insert → permission denied)',
  $$INSERT INTO hr_absence_entry (user_id, company_id, absence_date) VALUES (t_u('emp_sk'), '00000000-0000-0000-0000-0000000a5c01', CURRENT_DATE + 20)$$, '42501');
SELECT t_as(t_u('mgr_u'));
SELECT t_expect_err_any('J-263 B / J-291 B: the manager cannot read the table directly (permission denied)',
  $$SELECT 1 FROM hr_absence_entry$$, '42501');
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
SELECT t_assert('J-267 C / J-278 B / J-263 B: hr_absence_entry has the kind (sick / other; NULL only while needs_review) and its review state, but no reason, text, diagnosis or person-name column; RLS forced; no client insert / update / delete; the write RPCs are vp_hr-checked SECURITY DEFINER',
  (SELECT array_agg(column_name::text ORDER BY column_name) FROM information_schema.columns WHERE table_name = 'hr_absence_entry')
    = ARRAY['absence_date', 'absence_kind', 'cancelled_at', 'company_id', 'coordination_status', 'entered_at', 'entry_id', 'kind_review_status', 'user_id']
  AND (SELECT count(*) = 3 FROM pg_constraint WHERE conrelid = 'hr_absence_entry'::regclass
        AND conname IN ('chk_hr_absence_kind', 'chk_hr_absence_review_status', 'chk_hr_absence_kind_reviewed'))
  AND NOT EXISTS (SELECT 1 FROM hr_absence_entry WHERE absence_kind IS NULL OR kind_review_status <> 'reviewed')
  AND (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE relname = 'hr_absence_entry')
  AND NOT has_table_privilege('authenticated', 'hr_absence_entry', 'INSERT')
  AND NOT has_table_privilege('authenticated', 'hr_absence_entry', 'UPDATE')
  AND NOT has_table_privilege('authenticated', 'hr_absence_entry', 'DELETE')
  AND NOT has_table_privilege('anon', 'hr_absence_entry', 'SELECT')
  AND NOT has_table_privilege('authenticated', 'hr_absence_entry', 'SELECT')   -- J-291 B
  AND NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid = 'hr_absence_entry'::regclass)
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
SELECT t_assert('J-280 B / J-292: vp_hr reads write NO audit row (J-292, replaced the read logging); every put / cancel audit row RECORDS the kind and review state of the row (sick for emp_sk, other for the cancelled emp_hr day)',
  NOT EXISTS (SELECT 1 FROM access_audit_log WHERE action = 'hr_absence_read')   -- J-292: vp_hr reads are not logged
  AND (SELECT count(*) > 0 AND bool_and(scope ? 'absence_kind' AND scope->>'absence_kind' IN ('sick', 'other')
                                        AND scope->>'kind_review_status' = 'reviewed')
         FROM access_audit_log WHERE action IN ('hr_absence_put', 'hr_absence_cancel'))
  AND (SELECT bool_and(scope->>'absence_kind' = 'sick') FROM access_audit_log
        WHERE action = 'hr_absence_put' AND subject_user_id = t_u('emp_sk'))
  AND (SELECT count(*) = 1 AND bool_and(scope->>'absence_kind' = 'other') FROM access_audit_log
        WHERE action = 'hr_absence_cancel' AND subject_user_id = t_u('emp_hr')));
SELECT t_as(t_u('emp_sk'));
SET ROLE authenticated;
SELECT t_assert('J-269 A / J-291 B: the employee reads her OWN HR days WITH the kind (3 sick) through rpc_hr_absence_my_list, nothing of anyone else; no person field',
  (SELECT count(*) = 3 AND bool_and(absence_kind = 'sick') AND NOT (jsonb_agg(to_jsonb(r))::text ~* '(user_id|full_name|pseudonym)')
     FROM rpc_hr_absence_my_list() r));
SELECT t_expect_http('J-267 C: the employee cannot use the vp_hr reader, not even for herself → 403 insufficient_privilege',
  $$SELECT * FROM rpc_hr_absence_list('00000000-0000-0000-0000-0000000a5c01', t_u('emp_sk'))$$, 'insufficient_privilege', 403);
SELECT t_as(t_u('emp_hr'));
SELECT t_assert('J-269 A / J-291 B: another employee sees only her own days (2 other) — never emp_sk''s sick days',
  (SELECT count(*) = 2 AND bool_and(absence_kind = 'other') FROM rpc_hr_absence_my_list()));
RESET ROLE;
-- Every other role: no direct table read (J-291 B: permission denied → rows 0), refused by both readers.
CREATE OR REPLACE FUNCTION t_kind_probe(p_key text, p_company uuid DEFAULT '00000000-0000-0000-0000-0000000a5c01') RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_rows int; v_sig jsonb; v_sig2 jsonb;
BEGIN
  PERFORM t_as(t_u(p_key));
  SET LOCAL ROLE authenticated;
  v_rows := CASE WHEN t_err_sig('SELECT count(*) FROM hr_absence_entry')->>'code' = '42501' THEN 0 ELSE -1 END;   -- J-291 B: no direct read
  v_sig := t_err_sig(format('SELECT * FROM rpc_hr_absence_list(%L, %L)', p_company, t_u('emp_sk')));
  v_sig2 := t_err_sig(format('SELECT * FROM rpc_hr_absence_list_company(%L)', p_company));   -- J-288 B
  RESET ROLE;
  INSERT INTO t_kind VALUES ('probe ' || p_key, jsonb_build_object('rows', v_rows, 'msg', v_sig->>'message',
                                                                  'msg_company', v_sig2->>'message'));
END $$;
SELECT t_kind_probe(k) FROM unnest(ARRAY['mgr_u', 'emp_gh', 'cfo_u', 'le_u', 'bc_u', 'bm_u', 'os_u', 'dept_head']) k;
SELECT t_kind_probe('vp_s', '00000000-0000-0000-0000-0000000a5c01');
SELECT t_kind_probe('vp_s', '00000000-0000-0000-0000-0000000a5c02');
SELECT t_assert('J-267 C / J-288 B: the direct manager, another employee, cfo, legal_ethics, board_chair, board_member, owner_shareholder, the skip level and another company''s vp_hr read NO HR row and are refused by the single AND the company reader',
  (SELECT count(*) = 10 AND bool_and((j->>'rows')::int = 0 AND j->>'msg' IN ('insufficient_privilege', 'access_denied')
                                     AND j->>'msg_company' = 'insufficient_privilege')
     FROM t_kind WHERE label LIKE 'probe %'));
SELECT t_assert('J-267 C / J-284 A / J-291 B: catalog — the kind is in no view, and the only client-callable functions that touch hr_absence_entry (directly, through the internal row reader or through the J-301 B import helpers) or name the kind are the vp_hr RPCs (single + import) and the employee''s audited self-read',
  NOT EXISTS (SELECT 1 FROM information_schema.columns c JOIN information_schema.views v
                ON v.table_schema = c.table_schema AND v.table_name = c.table_name
               WHERE c.column_name = 'absence_kind')
  AND (SELECT array_agg(p.proname::text ORDER BY p.proname) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname !~ '^t_' AND (p.prosrc LIKE '%hr_absence_entry%' OR p.prosrc LIKE '%fn_hr_absence_rows%' OR p.prosrc LIKE '%fn_hr_import_%')
          AND (has_function_privilege('authenticated', p.oid, 'EXECUTE') OR has_function_privilege('anon', p.oid, 'EXECUTE')))
      = ARRAY['rpc_hr_absence_cancel', 'rpc_hr_absence_import_commit', 'rpc_hr_absence_import_stage', 'rpc_hr_absence_import_validate',
              'rpc_hr_absence_list', 'rpc_hr_absence_list_company', 'rpc_hr_absence_my_list', 'rpc_hr_absence_put', 'rpc_hr_absence_set_kind']
  AND (SELECT array_agg(p.proname::text ORDER BY p.proname) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname !~ '^t_' AND (p.prosrc LIKE '%absence_kind%' OR pg_get_function_result(p.oid) LIKE '%absence_kind%')
          AND has_function_privilege('authenticated', p.oid, 'EXECUTE'))
      = ARRAY['rpc_hr_absence_import_stage', 'rpc_hr_absence_list', 'rpc_hr_absence_list_company', 'rpc_hr_absence_my_list',
              'rpc_hr_absence_put', 'rpc_hr_absence_set_kind']);   -- J-307 C: the stage names the CSV column absence_kind
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

-- ============ 13. J-278 B / J-280 B / J-284 A / J-288 B (Karin 23.11) · kind review, audit with the kind, company reader ============
-- emp_nr (mgr_u's team) has a row WITHOUT a kind, as the upgrade leaves it (needs_review) — written directly here,
-- exactly the state the J-278 B migration produces (the real upgrade path is tested by tests/test_hr_kind_upgrade_*.sql).
SELECT count(t_mk(k, 'TeamU', 'employee', 'employee', 'mgr_u')) = 1 AS emp_nr_ok FROM unnest(ARRAY['emp_nr']) k;
INSERT INTO hr_absence_entry (user_id, company_id, absence_date, absence_kind, kind_review_status)
VALUES (t_u('emp_nr'), '00000000-0000-0000-0000-0000000a5c01', t_today('emp_nr') + 9, NULL, 'needs_review');
SELECT t_expect_err_any('J-278 B: a row without a kind must be needs_review (constraint)',
  $$INSERT INTO hr_absence_entry (user_id, company_id, absence_date, absence_kind, kind_review_status)
    VALUES (t_u('emp_nr'), '00000000-0000-0000-0000-0000000a5c01', t_today('emp_nr') + 10, NULL, 'reviewed')$$, '23514');
SELECT t_expect_err_any('J-278 B: a needs_review row cannot carry a (guessed) kind (constraint)',
  $$INSERT INTO hr_absence_entry (user_id, company_id, absence_date, absence_kind, kind_review_status)
    VALUES (t_u('emp_nr'), '00000000-0000-0000-0000-0000000a5c01', t_today('emp_nr') + 10, 'other', 'needs_review')$$, '23514');
CREATE TEMP TABLE t_rv (label text, j jsonb);
GRANT SELECT, INSERT ON t_rv TO authenticated;
SELECT t_as(t_u('mgr_u'));
SET ROLE authenticated;
INSERT INTO t_rv SELECT 'mgr before', jsonb_agg(to_jsonb(v) ORDER BY v.entry_id) FROM manager_unavailability_v v;
SELECT t_as(t_u('vp_u'));
INSERT INTO t_rv SELECT 'review list', jsonb_agg(to_jsonb(r)) FROM rpc_hr_absence_list_company('00000000-0000-0000-0000-0000000a5c01', true) r;
INSERT INTO t_rv SELECT 'company list', jsonb_agg(to_jsonb(r)) FROM rpc_hr_absence_list_company('00000000-0000-0000-0000-0000000a5c01') r;
INSERT INTO t_rv SELECT 'single list', jsonb_agg(to_jsonb(r)) FROM rpc_hr_absence_list('00000000-0000-0000-0000-0000000a5c01', t_u('emp_nr')) r;
RESET ROLE;
SELECT t_assert('J-278 B / J-156 A: the needs_review day is in the manager list as the SAME uniform row — every row of the list is byte-identical apart from id, pseudonym, date and coordination; the emp_nr row is "לא זמינה" / pending_coordination',
  (SELECT count(DISTINCT (e - 'entry_id' - 'display_pseudonym' - 'unavailable_date' - 'coordination_status')::text) = 1
     FROM t_rv, jsonb_array_elements(j) e WHERE label = 'mgr before')
  AND (SELECT count(*) = 1 FROM t_rv, jsonb_array_elements(j) e
        WHERE label = 'mgr before' AND e->>'display_pseudonym' = (SELECT display_pseudonym FROM users WHERE user_id = t_u('emp_nr'))
          AND e->>'availability_he' = 'לא זמינה' AND e->>'coordination_status' = 'pending_coordination'));
SELECT t_assert('J-278 B / J-288 B / J-293: vp_hr lists the rows to review (exactly the emp_nr day: kind null, needs_review) and the whole company (every AuthzCo row incl. cancelled); company rows = the single reader''s 7 keys (J-296 B: + reviewable) + user_id + full_name (J-293 exception); the single reader has no person field',
  (SELECT jsonb_array_length(j) = 1 AND j->0->'absence_kind' = 'null'::jsonb AND j->0->>'kind_review_status' = 'needs_review'
     FROM t_rv WHERE label = 'review list')
  AND (SELECT jsonb_array_length(j) = (SELECT count(*) FROM hr_absence_entry WHERE company_id = '00000000-0000-0000-0000-0000000a5c01')
     FROM t_rv WHERE label = 'company list')
  AND (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys((SELECT j->0 FROM t_rv WHERE label = 'company list')) k)
      = ARRAY['absence_date', 'absence_kind', 'cancelled', 'coordination_status', 'entry_id', 'full_name', 'kind_review_status', 'reviewable', 'user_id']
  AND (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys((SELECT j->0 FROM t_rv WHERE label = 'single list')) k)
      = ARRAY['absence_date', 'absence_kind', 'cancelled', 'coordination_status', 'entry_id', 'kind_review_status', 'reviewable']
  AND NOT EXISTS (SELECT 1 FROM t_rv WHERE label = 'single list' AND j::text ~* '(user_id|person|pseudonym|full_name|email)'));
SELECT t_assert('J-292 (replaced the J-288 B read audit): the company reads and the single read wrote NO audit row',
  NOT EXISTS (SELECT 1 FROM access_audit_log WHERE action = 'hr_absence_read'));
-- The review RPC: refusals first (nothing changes), then vp_hr sets the kind.
CREATE OR REPLACE FUNCTION t_setkind_probe(p_key text, p_company uuid) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_sig jsonb; v_entry uuid := (SELECT entry_id FROM hr_absence_entry WHERE user_id = t_u('emp_nr'));   -- read as superuser (J-291 B)
BEGIN
  PERFORM t_as(t_u(p_key));
  SET LOCAL ROLE authenticated;
  v_sig := t_err_sig(format('SELECT rpc_hr_absence_set_kind(%L, %L, %L)', p_company, v_entry, 'sick'));
  RESET ROLE;
  RETURN v_sig->>'message';
END $$;
SELECT t_assert('J-278 B: only an active vp_hr of the row''s company sets the kind — manager, the employee herself, another employee, cfo, legal_ethics, board_chair, board_member, owner_shareholder, skip level → insufficient_privilege; another company''s vp_hr → insufficient_privilege (AuthzCo) / access_denied (her own company, foreign row); nothing changed',
  (SELECT bool_and(t_setkind_probe(k, '00000000-0000-0000-0000-0000000a5c01') = 'insufficient_privilege')
     FROM unnest(ARRAY['mgr_u', 'emp_nr', 'emp_gh', 'cfo_u', 'le_u', 'bc_u', 'bm_u', 'os_u', 'dept_head', 'vp_s']) k)
  AND t_setkind_probe('vp_s', '00000000-0000-0000-0000-0000000a5c02') = 'access_denied'
  AND (SELECT absence_kind IS NULL AND kind_review_status = 'needs_review' FROM hr_absence_entry WHERE user_id = t_u('emp_nr'))
  AND NOT EXISTS (SELECT 1 FROM access_audit_log WHERE action = 'hr_absence_kind_set'));
SELECT t_as(t_u('vp_u'));
SET ROLE authenticated;
SELECT t_expect_err_any('J-278 B: the review needs a valid kind → 400 invalid_absence_kind (never a guess)',
  $$SELECT rpc_hr_absence_set_kind('00000000-0000-0000-0000-0000000a5c01', (SELECT r.entry_id FROM rpc_hr_absence_list_company('00000000-0000-0000-0000-0000000a5c01', true) r), NULL)$$, '22023');
INSERT INTO t_rv SELECT 'set', rpc_hr_absence_set_kind('00000000-0000-0000-0000-0000000a5c01',
  (SELECT r.entry_id FROM rpc_hr_absence_list_company('00000000-0000-0000-0000-0000000a5c01', true) r), 'sick');
INSERT INTO t_rv SELECT 'review list after', COALESCE(jsonb_agg(to_jsonb(r)), '[]'::jsonb) FROM rpc_hr_absence_list_company('00000000-0000-0000-0000-0000000a5c01', true) r;
SELECT t_as(t_u('mgr_u'));
INSERT INTO t_rv SELECT 'mgr after', jsonb_agg(to_jsonb(v) ORDER BY v.entry_id) FROM manager_unavailability_v v;
RESET ROLE;
SELECT t_assert('J-278 B / J-280 B: vp_hr sets the kind → reviewed, nothing left to review; audited as hr_absence_kind_set WITH the kind (sick, reviewed), the employee as subject; the manager list is byte-identical before and after',
  (SELECT j->>'status' = 'reviewed' AND NOT (j::text ~* '(user_id|absence_kind|sick)') FROM t_rv WHERE label = 'set')
  AND (SELECT absence_kind = 'sick' AND kind_review_status = 'reviewed' FROM hr_absence_entry WHERE user_id = t_u('emp_nr'))
  AND (SELECT jsonb_array_length(j) = 0 FROM t_rv WHERE label = 'review list after')
  AND (SELECT count(*) = 1 AND bool_and(subject_user_id = t_u('emp_nr') AND scope->>'absence_kind' = 'sick'
                                        AND scope->>'kind_review_status' = 'reviewed')
         FROM access_audit_log WHERE action = 'hr_absence_kind_set')
  AND (SELECT j FROM t_rv WHERE label = 'mgr before') = (SELECT j FROM t_rv WHERE label = 'mgr after'));
-- J-289: a needs_review day is NOT a sick day in the totals until vp_hr sets the kind.
INSERT INTO hr_absence_entry (user_id, company_id, absence_date, absence_kind, kind_review_status)
VALUES (t_u('s4'), '00000000-0000-0000-0000-0000000a5c02', (SELECT m FROM t_m) + 6, NULL, 'needs_review');
SELECT t_assert('J-289: the needs_review day of s4 does not count (S1 HR sick days stay 4)',
  fn_hr_sick_days('00000000-0000-0000-0000-0000000a5c02', 'S1', (SELECT m FROM t_m)) = 4);
SELECT t_as(t_u('vp_s'));
SET ROLE authenticated;
INSERT INTO t_rv SELECT 'set s4', rpc_hr_absence_set_kind('00000000-0000-0000-0000-0000000a5c02',
  (SELECT r.entry_id FROM rpc_hr_absence_list_company('00000000-0000-0000-0000-0000000a5c02', true) r), 'sick');
RESET ROLE;
SELECT t_assert('J-289: once vp_hr sets it to sick, the day counts (S1 HR sick days 5; team total max(2, 5) + 1 + 1 = 7)',
  fn_hr_sick_days('00000000-0000-0000-0000-0000000a5c02', 'S1', (SELECT m FROM t_m)) = 5
  AND fn_team_absence_days('00000000-0000-0000-0000-0000000a5c02', 'S1', (SELECT m FROM t_m)) = 7);
SELECT t_assert('J-284 A / J-295 C: no export, CHRO, dossier, report, board or offboarding function returns or reads the kind (the offboarding pending list reads the table but never the kind)',
  NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
               WHERE n.nspname = 'public' AND p.proname ~* '(export|chro|dossier|report|csv|board|offboard)'
                 AND p.proname <> 'fn_hr_offboarding_pending'   -- J-295 C: reads the table, never the kind (checked below)
                 AND (p.prosrc ~* '(absence_kind|hr_absence_entry|fn_hr_absence_rows|rpc_hr_absence)'
                      OR pg_get_function_result(p.oid) LIKE '%absence_kind%'))
  AND EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_chro_named_view')
  AND (SELECT prosrc NOT LIKE '%absence_kind%' FROM pg_proc WHERE proname = 'fn_hr_offboarding_pending'));
SELECT t_assert('J-288 B / J-278 B: the shared row reader and the audit-scope builder are internal (no client grant)',
  NOT has_function_privilege('authenticated', 'fn_hr_absence_rows(uuid, uuid, boolean)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'fn_hr_absence_audit_scope(hr_absence_entry)', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'rpc_hr_absence_list_company(uuid, boolean)', 'EXECUTE'));

-- ============ 14. J-289 A / J-291 B / J-292 / J-293 / J-294 C (Karin 23.11) ============
-- J-291 B: every self-read writes ONE audit row (actor = subject = the employee), never the kind.
SELECT t_assert('J-291 B: each self-read so far wrote exactly one hr_absence_self_read row — emp_sk 2 calls, emp_hr 1 — viewer = subject = the employee, company in the scope, NO kind, no count',
  (SELECT count(*) = 2 FROM access_audit_log WHERE action = 'hr_absence_self_read' AND viewer_id = t_u('emp_sk') AND subject_user_id = t_u('emp_sk'))
  AND (SELECT count(*) = 1 FROM access_audit_log WHERE action = 'hr_absence_self_read' AND viewer_id = t_u('emp_hr') AND subject_user_id = t_u('emp_hr'))
  AND (SELECT bool_and(viewer_id = subject_user_id AND scope ? 'company_id' AND NOT (scope::text ~* '(sick|other|kind|count|absence_date)'))
         FROM access_audit_log WHERE action = 'hr_absence_self_read'));
SELECT t_as(t_u('emp_gh'));
SET ROLE authenticated;
SELECT t_assert('J-291 B: an employee with no HR rows gets an empty list (still logged)', (SELECT count(*) = 0 FROM rpc_hr_absence_my_list()));
SELECT t_as(NULL);
SELECT t_expect_http('J-291 B: not signed in → 403 access_denied', $$SELECT * FROM rpc_hr_absence_my_list()$$, 'access_denied', 403);
RESET ROLE;
SELECT t_assert('J-291 B: the empty read is logged too; anon cannot call the self-read',
  (SELECT count(*) = 1 FROM access_audit_log WHERE action = 'hr_absence_self_read' AND viewer_id = t_u('emp_gh'))
  AND NOT has_function_privilege('anon', 'rpc_hr_absence_my_list()', 'EXECUTE'));
-- J-292 / J-280 B: vp_hr reads leave no row; writes keep logging WITH the kind.
CREATE TEMP TABLE t_j292 AS SELECT count(*) AS n FROM access_audit_log;
GRANT SELECT ON t_j292 TO authenticated;
SELECT t_as(t_u('vp_u'));
SET ROLE authenticated;
SELECT t_assert('J-292 fixture: vp_hr reads one employee and the whole company', (SELECT count(*) > 0 FROM rpc_hr_absence_list('00000000-0000-0000-0000-0000000a5c01', t_u('emp_sk')))
  AND (SELECT count(*) > 0 FROM rpc_hr_absence_list_company('00000000-0000-0000-0000-0000000a5c01')));
RESET ROLE;
SELECT t_assert('J-292: the vp_hr reads wrote NO audit row at all', (SELECT count(*) FROM access_audit_log) = (SELECT n FROM t_j292));
SELECT t_as(t_u('vp_u'));
SET ROLE authenticated;
SELECT t_assert('J-292 fixture: vp_hr writes (put, cancel)', rpc_hr_absence_put('00000000-0000-0000-0000-0000000a5c01', t_u('emp_gh'), t_today('emp_gh') + 30, 'sick')->>'status' = 'saved'
  AND rpc_hr_absence_cancel('00000000-0000-0000-0000-0000000a5c01', t_u('emp_gh'), t_today('emp_gh') + 30)->>'status' = 'cancelled');
RESET ROLE;
SELECT t_assert('J-292 / J-280 B / J-274 A: writes still log — put and cancel rows WITH the kind (sick), the employee as subject; still no read row',
  (SELECT count(*) = 2 AND bool_and(scope->>'absence_kind' = 'sick') FROM access_audit_log
    WHERE action IN ('hr_absence_put', 'hr_absence_cancel') AND subject_user_id = t_u('emp_gh')
      AND (scope->>'absence_date')::date = t_today('emp_gh') + 30)
  AND NOT EXISTS (SELECT 1 FROM access_audit_log WHERE action = 'hr_absence_read'));
-- J-293: the company list names the employee (user_id + full name), for vp_hr of the same company only.
SELECT t_as(t_u('vp_u'));
SET ROLE authenticated;
INSERT INTO t_rv SELECT 'j293', jsonb_agg(to_jsonb(r)) FROM rpc_hr_absence_list_company('00000000-0000-0000-0000-0000000a5c01') r;
RESET ROLE;
SELECT t_assert('J-293: every company-list row carries the right user_id and full name (emp_sk''s 3 rows: her id, "Fixture emp_sk", sick)',
  (SELECT bool_and((e->>'user_id')::uuid = h.user_id AND e->>'full_name' = u.full_name)
     FROM t_rv, jsonb_array_elements(j) e JOIN hr_absence_entry h ON h.entry_id = (e->>'entry_id')::uuid JOIN users u ON u.user_id = h.user_id
    WHERE label = 'j293')
  AND (SELECT count(*) = 3 AND bool_and(e->>'full_name' = 'Fixture emp_sk' AND e->>'absence_kind' = 'sick')
         FROM t_rv, jsonb_array_elements(j) e WHERE label = 'j293' AND (e->>'user_id')::uuid = t_u('emp_sk')));
SELECT t_assert('J-293: every other role (manager, employee, cfo, legal_ethics, board_chair, board_member, owner_shareholder, skip level, another company''s vp_hr) is refused by the company list — 403 insufficient_privilege (section 11 probes)',
  (SELECT count(*) = 10 AND bool_and(j->>'msg_company' = 'insufficient_privilege') FROM t_kind WHERE label LIKE 'probe %'));
-- J-294 C: a leaver's row cannot be reviewed; the refusal is identical to an unknown entry id.
SELECT count(t_mk(k, 'Gov', 'employee', 'employee')) = 1 AS emp_lv_ok FROM unnest(ARRAY['emp_lv']) k;
INSERT INTO hr_absence_entry (user_id, company_id, absence_date, absence_kind, kind_review_status)
VALUES (t_u('emp_lv'), '00000000-0000-0000-0000-0000000a5c01', CURRENT_DATE - 40, NULL, 'needs_review');
UPDATE users SET employment_ended_at = clock_timestamp() - interval '1 day' WHERE user_id = t_u('emp_lv');
CREATE TEMP TABLE t_j294 (label text, sig jsonb);
GRANT SELECT, INSERT ON t_j294 TO authenticated;
SELECT t_as(t_u('vp_u'));
SET ROLE authenticated;
INSERT INTO t_j294 SELECT 'leaver', t_err_sig(format('SELECT rpc_hr_absence_set_kind(%L, %L, %L)', '00000000-0000-0000-0000-0000000a5c01',
  (SELECT r.entry_id FROM rpc_hr_absence_list_company('00000000-0000-0000-0000-0000000a5c01', true) r WHERE r.user_id = t_u('emp_lv')), 'sick'));
INSERT INTO t_j294 SELECT 'unknown', t_err_sig(format('SELECT rpc_hr_absence_set_kind(%L, %L, %L)', '00000000-0000-0000-0000-0000000a5c01',
  gen_random_uuid(), 'sick'));
RESET ROLE;
SELECT t_assert('J-294 C: vp_hr cannot set the kind of a leaver''s row → 403 access_denied, byte-identical to an unknown entry id (no hint that she left); the row stays needs_review; nothing audited',
  (SELECT sig->>'message' = 'access_denied' FROM t_j294 WHERE label = 'leaver')
  AND (SELECT sig FROM t_j294 WHERE label = 'leaver') = (SELECT sig FROM t_j294 WHERE label = 'unknown')
  AND (SELECT absence_kind IS NULL AND kind_review_status = 'needs_review' FROM hr_absence_entry WHERE user_id = t_u('emp_lv'))
  AND NOT EXISTS (SELECT 1 FROM access_audit_log WHERE action = 'hr_absence_kind_set' AND subject_user_id = t_u('emp_lv')));
SELECT t_assert('J-294 C: the rule sits in ONE internal guard (fn_hr_kind_settable, no client grant) used by rpc_hr_absence_set_kind',
  NOT has_function_privilege('authenticated', 'fn_hr_kind_settable(uuid, uuid)', 'EXECUTE')
  AND (SELECT prosrc LIKE '%fn_hr_kind_settable(p_company_id, p_entry_id)%' FROM pg_proc WHERE proname = 'rpc_hr_absence_set_kind'));
SELECT t_assert('J-294 C: an ACTIVE employee''s row is still reviewable (emp_nr, section 13: reviewed, sick, audited once)',
  (SELECT kind_review_status = 'reviewed' AND absence_kind = 'sick' FROM hr_absence_entry WHERE user_id = t_u('emp_nr'))
  AND (SELECT count(*) = 1 FROM access_audit_log WHERE action = 'hr_absence_kind_set' AND subject_user_id = t_u('emp_nr')));
-- J-289 A + J-294 C: a leaver's needs_review day in SickCo S1 stays out of the sick days AND the J-276 max.
SELECT count(t_mk2(k, 'S1', 'employee')) = 1 AS s7_ok FROM unnest(ARRAY['s7']) k;
INSERT INTO hr_absence_entry (user_id, company_id, absence_date, absence_kind, kind_review_status)
VALUES (t_u('s7'), '00000000-0000-0000-0000-0000000a5c02', (SELECT m FROM t_m) + 7, NULL, 'needs_review');
UPDATE users SET employment_ended_at = clock_timestamp() - interval '1 day' WHERE user_id = t_u('s7');
SELECT t_assert('J-289 A: needs_review days (s7, now a leaver) are NOT sick — S1 HR sick days stay 5 and the team total max(2, 5) + 1 + 1 = 7; a manual number above them still wins (max(6, 5))',
  fn_hr_sick_days('00000000-0000-0000-0000-0000000a5c02', 'S1', (SELECT m FROM t_m)) = 5
  AND fn_team_absence_days('00000000-0000-0000-0000-0000000a5c02', 'S1', (SELECT m FROM t_m)) = 7
  AND fn_combined_sickness_days(6, fn_hr_sick_days('00000000-0000-0000-0000-0000000a5c02', 'S1', (SELECT m FROM t_m))) = 6);
-- Manager rows still byte-identical across all types (after every change of this round).
CREATE TEMP TABLE t_mgr14 (j jsonb);
GRANT SELECT, INSERT ON t_mgr14 TO authenticated;
SELECT t_as(t_u('mgr_u'));
SET ROLE authenticated;
INSERT INTO t_mgr14 SELECT to_jsonb(v) FROM manager_unavailability_v v;
RESET ROLE;
SELECT t_assert('J-156 A / J-267 C: the manager list is still uniform — every row byte-identical apart from id, pseudonym, date and coordination; "לא זמינה"; no kind, name or person id; the leaver is not in it',
  (SELECT count(*) > 0 AND count(DISTINCT (j - 'entry_id' - 'display_pseudonym' - 'unavailable_date' - 'coordination_status')::text) = 1
          AND bool_and(j->>'availability_he' = 'לא זמינה' AND NOT (j::text ~* '(sick|other|kind|user_id|full_name)'))
     FROM t_mgr14)
  AND NOT EXISTS (SELECT 1 FROM t_mgr14 WHERE j->>'display_pseudonym' = (SELECT display_pseudonym FROM users WHERE user_id = t_u('emp_lv'))));

-- ============ 15. J-295 C / J-296 B / J-297 B (Karin 23.11) · offboarding pending list, reviewable, future end date ============
-- J-297 B boundary: employed while now < employment_ended_at; AT the end instant she has left (strict).
SELECT t_assert('J-297 B boundary: no end → employed; end in the future → employed; end == now → LEFT (strict <); end in the past → left',
  fn_hr_employed_at(NULL, now()) AND fn_hr_employed_at(now() + interval '1 second', now())
  AND NOT fn_hr_employed_at(now(), now()) AND NOT fn_hr_employed_at(now() - interval '1 second', now()));
-- Fixtures (team Gov, no manager): emp_fu leaves in 3 days, emp_pa left a second ago; each has one needs_review day.
SELECT count(t_mk(k, 'Gov', 'employee', 'employee')) = 2 AS j297_ok FROM unnest(ARRAY['emp_fu', 'emp_pa']) k;
INSERT INTO hr_absence_entry (user_id, company_id, absence_date, absence_kind, kind_review_status)
SELECT t_u(k), '00000000-0000-0000-0000-0000000a5c01', CURRENT_DATE - 50, NULL, 'needs_review' FROM unnest(ARRAY['emp_fu', 'emp_pa']) k;
UPDATE users SET employment_ended_at = clock_timestamp() + interval '3 days' WHERE user_id = t_u('emp_fu');
UPDATE users SET employment_ended_at = clock_timestamp() - interval '1 second' WHERE user_id = t_u('emp_pa');
CREATE TEMP TABLE t_j297 (label text, j jsonb);
GRANT SELECT, INSERT ON t_j297 TO authenticated;
-- Test helper: the entry id of a fixture's day 50 days ago, read as the superuser (no client table read since J-291 B).
CREATE OR REPLACE FUNCTION t_entry_of(p_key text) RETURNS uuid LANGUAGE sql SECURITY DEFINER AS $$
  SELECT entry_id FROM hr_absence_entry WHERE user_id = t_u(p_key) AND absence_date = CURRENT_DATE - 50 $$;   -- superuser read (J-291 B)
GRANT EXECUTE ON FUNCTION t_entry_of(text) TO authenticated;
SELECT t_as(t_u('vp_u'));
SET ROLE authenticated;
INSERT INTO t_j297 SELECT 'company', jsonb_agg(to_jsonb(r)) FROM rpc_hr_absence_list_company('00000000-0000-0000-0000-0000000a5c01') r;
INSERT INTO t_j297 SELECT 'fu put', rpc_hr_absence_put('00000000-0000-0000-0000-0000000a5c01', t_u('emp_fu'), t_today('emp_fu') + 1, 'sick');
INSERT INTO t_j297 SELECT 'fu cancel', rpc_hr_absence_cancel('00000000-0000-0000-0000-0000000a5c01', t_u('emp_fu'), t_today('emp_fu') + 1);
INSERT INTO t_j297 SELECT 'fu set', rpc_hr_absence_set_kind('00000000-0000-0000-0000-0000000a5c01', t_entry_of('emp_fu'), 'other');
INSERT INTO t_j297 SELECT 'fu read', jsonb_agg(to_jsonb(r)) FROM rpc_hr_absence_list('00000000-0000-0000-0000-0000000a5c01', t_u('emp_fu')) r;
INSERT INTO t_j297 SELECT 'pa put', t_err_sig(format('SELECT rpc_hr_absence_put(%L, %L, %L, %L)', '00000000-0000-0000-0000-0000000a5c01', t_u('emp_pa'), t_today('emp_fu') + 1, 'sick'));
INSERT INTO t_j297 SELECT 'pa cancel', t_err_sig(format('SELECT rpc_hr_absence_cancel(%L, %L, %L)', '00000000-0000-0000-0000-0000000a5c01', t_u('emp_pa'), CURRENT_DATE - 50));
INSERT INTO t_j297 SELECT 'pa set', t_err_sig(format('SELECT rpc_hr_absence_set_kind(%L, %L, %L)', '00000000-0000-0000-0000-0000000a5c01', t_entry_of('emp_pa'), 'sick'));
RESET ROLE;
SELECT t_assert('J-296 B: reviewable per company-list row = what the guard would accept — the leaver rows (emp_lv, emp_pa) false; emp_fu (future end) and every active employee true',
  (SELECT bool_and((e->>'reviewable')::boolean = ((e->>'user_id')::uuid NOT IN (t_u('emp_lv'), t_u('emp_pa'))))
          AND bool_or(NOT (e->>'reviewable')::boolean) AND count(*) FILTER (WHERE (e->>'user_id')::uuid = t_u('emp_fu')) = 1
     FROM t_j297, jsonb_array_elements(j) e WHERE label = 'company')
  AND (SELECT bool_and((e->>'reviewable')::boolean = fn_hr_kind_settable('00000000-0000-0000-0000-0000000a5c01', (e->>'entry_id')::uuid))
         FROM t_j297, jsonb_array_elements(j) e WHERE label = 'company'));
SELECT t_assert('J-297 B: an employee whose end date is in the FUTURE is still active — vp_hr puts, cancels and sets the kind (reviewed); the single reader works and shows reviewable true',
  (SELECT j->>'status' = 'saved' FROM t_j297 WHERE label = 'fu put')
  AND (SELECT j->>'status' = 'cancelled' FROM t_j297 WHERE label = 'fu cancel')
  AND (SELECT j->>'status' = 'reviewed' FROM t_j297 WHERE label = 'fu set')
  AND (SELECT absence_kind = 'other' AND kind_review_status = 'reviewed' FROM hr_absence_entry WHERE entry_id = t_entry_of('emp_fu'))
  AND (SELECT count(*) = 2 AND bool_and((e->>'reviewable')::boolean) FROM t_j297, jsonb_array_elements(j) e WHERE label = 'fu read'));
SELECT t_assert('J-297 B: an employee whose end date has PASSED is refused — put, cancel and set kind all → 403 access_denied; her row stays needs_review',
  (SELECT bool_and(j->>'message' = 'access_denied') FROM t_j297 WHERE label IN ('pa put', 'pa cancel', 'pa set'))
  AND (SELECT count(*) = 3 FROM t_j297 WHERE label IN ('pa put', 'pa cancel', 'pa set'))
  AND (SELECT kind_review_status = 'needs_review' FROM hr_absence_entry WHERE entry_id = t_entry_of('emp_pa')));
-- J-295 C: offboarding returns the pending list (service_role / server only).
SELECT count(t_mk(k, 'Gov', 'employee', 'employee')) = 3 AS j295_ok FROM unnest(ARRAY['emp_ob', 'emp_oi', 'emp_on']) k;
INSERT INTO hr_absence_entry (user_id, company_id, absence_date, absence_kind, kind_review_status) VALUES
  (t_u('emp_ob'), '00000000-0000-0000-0000-0000000a5c01', CURRENT_DATE - 60, NULL, 'needs_review'),
  (t_u('emp_ob'), '00000000-0000-0000-0000-0000000a5c01', CURRENT_DATE - 61, NULL, 'needs_review'),
  (t_u('emp_ob'), '00000000-0000-0000-0000-0000000a5c01', CURRENT_DATE - 62, 'sick', 'reviewed'),
  (t_u('emp_oi'), '00000000-0000-0000-0000-0000000a5c01', CURRENT_DATE - 60, NULL, 'needs_review');
CREATE TEMP TABLE t_j295 AS
  SELECT 'future'::text AS label, rpc_offboard_employee(t_u('emp_ob'), clock_timestamp() + interval '5 days') AS j
  UNION ALL SELECT 'immediate', rpc_offboard_employee(t_u('emp_oi'))
  UNION ALL SELECT 'none', rpc_offboard_employee(t_u('emp_on'), clock_timestamp() + interval '5 days');
GRANT SELECT ON t_j295 TO authenticated;
SELECT t_assert('J-295 C: offboarding with a FUTURE end still succeeds and returns terminated_at + the 2 needs_review days (entry_id, absence_date, kind_review_status, reviewable = true) — the reviewed day and any kind / name / person id are not in it',
  (SELECT (j->>'terminated_at')::timestamptz > clock_timestamp() AND (j->'hr_kind_review_pending'->>'count')::int = 2
          AND jsonb_array_length(j->'hr_kind_review_pending'->'entries') = 2
          AND (SELECT bool_and((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(e) k) = ARRAY['absence_date', 'entry_id', 'kind_review_status', 'reviewable']
                               AND e->>'kind_review_status' = 'needs_review' AND (e->>'reviewable')::boolean)
                 FROM jsonb_array_elements(j->'hr_kind_review_pending'->'entries') e)
          AND NOT (j::text ~* '(absence_kind|sick|other|full_name|user_id|Fixture)')
     FROM t_j295 WHERE label = 'future'));
SELECT t_as(t_u('vp_u'));
SET ROLE authenticated;
SELECT t_assert('J-295 C / J-297 B: until the future end date vp_hr sets the kind of a listed day',
  rpc_hr_absence_set_kind('00000000-0000-0000-0000-0000000a5c01',
    ((SELECT j FROM t_j295 WHERE label = 'future')->'hr_kind_review_pending'->'entries'->0->>'entry_id')::uuid, 'sick')->>'status' = 'reviewed');
RESET ROLE;
SELECT t_assert('J-295 C / J-310: an IMMEDIATE offboarding still succeeds; its pending day is listed with reviewable = false (vp_hr can no longer set it); no pending days → count 0, empty list',
  (SELECT (j->'hr_kind_review_pending'->>'count')::int = 1 AND NOT (j->'hr_kind_review_pending'->'entries'->0->>'reviewable')::boolean
     FROM t_j295 WHERE label = 'immediate')
  AND (SELECT (j->'hr_kind_review_pending'->>'count')::int = 0 AND j->'hr_kind_review_pending'->'entries' = '[]'::jsonb
     FROM t_j295 WHERE label = 'none'));
SELECT t_assert('J-295 C: nothing reaches anyone else — only service_role may call offboarding (no authenticated / anon EXECUTE); the employee_offboarded audit row holds no pending list or kind; the helper is internal',
  NOT has_function_privilege('authenticated', 'rpc_offboard_employee(uuid, timestamptz)', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'rpc_offboard_employee(uuid, timestamptz)', 'EXECUTE')
  AND has_function_privilege('service_role', 'rpc_offboard_employee(uuid, timestamptz)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'fn_hr_offboarding_pending(uuid)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'fn_hr_employed_at(timestamptz, timestamptz)', 'EXECUTE')
  AND NOT EXISTS (SELECT 1 FROM access_audit_log WHERE action = 'employee_offboarded'
                   AND subject_user_id IN (t_u('emp_ob'), t_u('emp_oi')) AND scope::text ~* '(pending|entries|kind|sick)'));
SELECT t_as(t_u('vp_u'));
SET ROLE authenticated;
SELECT t_expect_err_any('J-295 C: vp_hr (a client) cannot call offboarding herself — permission denied (she sees the pending days in rpc_hr_absence_list_company, reviewable flag)',
  format('SELECT rpc_offboard_employee(%L)', t_u('emp_gh')), '42501');
RESET ROLE;

-- ============ 16. J-300 B … J-308 A (Karin 23.11) · HR absence bulk import: employee number, stage → dry run → commit ============
-- Fixtures (company a5c01, team Imp): imp_a (number E-100), imp_b (e-mail match only), imp_lv (left yesterday,
-- E-LV), imp_fu (leaves in 3 days, E-FU), imp_ng (no employee profile, E-NG), imp_d1 / imp_d2 (the same e-mail in
-- two cases → ambiguous); SickCo: s_imp (number E-100 too — per company) and s_imp2 (S-1).
SELECT count(t_mk(k, 'Imp', 'employee', 'employee')) = 7 AS imp_ok
  FROM unnest(ARRAY['imp_a', 'imp_b', 'imp_lv', 'imp_fu', 'imp_ng', 'imp_d1', 'imp_d2']) k;
SELECT count(t_mk2(k, 'S1', 'employee')) = 2 AS imp_s_ok FROM unnest(ARRAY['s_imp', 's_imp2']) k;
UPDATE users SET email = 'Imp.Dup@authz.test' WHERE user_id = t_u('imp_d1');
UPDATE users SET email = 'imp.dup@AUTHZ.test' WHERE user_id = t_u('imp_d2');
UPDATE users SET employment_ended_at = clock_timestamp() - interval '1 day' WHERE user_id = t_u('imp_lv');
UPDATE users SET employment_ended_at = clock_timestamp() + interval '3 days' WHERE user_id = t_u('imp_fu');
UPDATE users SET has_employee_profile = false WHERE user_id = t_u('imp_ng');
-- Stored rows of imp_a before the import (superuser): a coordinated 'sick' day (J-279 re-put), a cancelled day
-- (re-opened by put), an active day (cancelled by the file), a needs_review day (reviewed by put).
INSERT INTO hr_absence_entry (user_id, company_id, absence_date, absence_kind, kind_review_status, coordination_status, cancelled_at)
VALUES (t_u('imp_a'), '00000000-0000-0000-0000-0000000a5c01', CURRENT_DATE - 205, 'sick', 'reviewed', 'coordinated', NULL),
       (t_u('imp_a'), '00000000-0000-0000-0000-0000000a5c01', CURRENT_DATE - 206, 'other', 'reviewed', 'coordinated', clock_timestamp()),
       (t_u('imp_a'), '00000000-0000-0000-0000-0000000a5c01', CURRENT_DATE - 207, 'sick', 'reviewed', 'pending_coordination', NULL),
       (t_u('imp_a'), '00000000-0000-0000-0000-0000000a5c01', CURRENT_DATE - 208, NULL, 'needs_review', 'pending_coordination', NULL);
CREATE TEMP TABLE t_imp (label text, j jsonb);
GRANT SELECT, INSERT ON t_imp TO authenticated;
-- Superuser views of the HR table and the audit (the client cannot read either).
-- One stored HR row of a fixture, p_days days ago (superuser read).
CREATE OR REPLACE FUNCTION t_imp_entry(p_key text, p_days int) RETURNS hr_absence_entry LANGUAGE sql SECURITY DEFINER AS $$
  SELECT * FROM hr_absence_entry WHERE user_id = t_u(p_key) AND absence_date = CURRENT_DATE - p_days $$;
-- Fingerprint of hr_absence_entry + the audit size (a dry run must change neither).
CREATE OR REPLACE FUNCTION t_imp_fp() RETURNS text LANGUAGE sql SECURITY DEFINER AS $$
  SELECT md5(COALESCE((SELECT string_agg(to_jsonb(h)::text, '|' ORDER BY h.entry_id) FROM hr_absence_entry h), ''))
         || ':' || (SELECT count(*) FROM access_audit_log) $$;
-- The CSV rows of the main test file (file order = row number).
CREATE OR REPLACE FUNCTION t_imp_file() RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_agg(r ORDER BY n) FROM (VALUES
    ( 1, jsonb_build_object('employee_number', 'E-100', 'absence_date', (CURRENT_DATE - 201)::text, 'absence_kind', 'sick', 'action', 'put')),
    ( 2, jsonb_build_object('employee_number', 'E-100', 'absence_date', (CURRENT_DATE - 201)::text, 'absence_kind', 'other', 'action', 'put')),
    ( 3, jsonb_build_object('email', 'IMP_A@AUTHZ.TEST', 'absence_date', (CURRENT_DATE - 201)::text, 'absence_kind', 'other', 'action', 'put')),
    ( 4, jsonb_build_object('email', ' Imp_B@Authz.Test ', 'absence_date', (CURRENT_DATE - 202)::text, 'absence_kind', 'sick', 'action', 'put')),
    ( 5, jsonb_build_object('employee_number', 'E-100', 'absence_date', (CURRENT_DATE - 205)::text, 'absence_kind', 'other', 'action', 'put')),
    ( 6, jsonb_build_object('employee_number', 'E-100', 'absence_date', (CURRENT_DATE - 206)::text, 'absence_kind', 'sick', 'action', 'put')),
    ( 7, jsonb_build_object('employee_number', 'E-100', 'absence_date', (CURRENT_DATE - 207)::text, 'action', 'cancel')),
    ( 8, jsonb_build_object('employee_number', 'E-100', 'absence_date', (CURRENT_DATE - 209)::text, 'action', 'cancel')),
    ( 9, jsonb_build_object('employee_number', 'E-LV', 'absence_date', (CURRENT_DATE - 201)::text, 'absence_kind', 'sick', 'action', 'put')),
    (10, jsonb_build_object('employee_number', 'E-FU', 'absence_date', (CURRENT_DATE - 201)::text, 'absence_kind', 'sick', 'action', 'put')),
    (11, jsonb_build_object('employee_number', 'S-1', 'absence_date', (CURRENT_DATE - 201)::text, 'absence_kind', 'sick', 'action', 'put')),
    (12, jsonb_build_object('email', 's_imp2@sick.test', 'absence_date', (CURRENT_DATE - 201)::text, 'absence_kind', 'sick', 'action', 'put')),
    (13, jsonb_build_object('employee_number', 'NOPE', 'absence_date', (CURRENT_DATE - 201)::text, 'absence_kind', 'sick', 'action', 'put')),
    (14, jsonb_build_object('employee_number', 'E-NG', 'absence_date', (CURRENT_DATE - 201)::text, 'absence_kind', 'sick', 'action', 'put')),
    (15, jsonb_build_object('absence_date', (CURRENT_DATE - 201)::text, 'absence_kind', 'sick', 'action', 'put')),
    (16, jsonb_build_object('employee_number', 'E-100', 'absence_date', (CURRENT_DATE - 203)::text, 'absence_kind', 'sick', 'action', 'delete')),
    (17, jsonb_build_object('employee_number', 'E-100', 'absence_date', '2026-02-30', 'absence_kind', 'sick', 'action', 'put')),
    (18, jsonb_build_object('employee_number', 'E-100', 'absence_date', '23/11/2026', 'absence_kind', 'sick', 'action', 'put')),
    (19, jsonb_build_object('employee_number', 'E-100', 'absence_date', (CURRENT_DATE - 203)::text, 'absence_kind', 'flu', 'action', 'put')),
    (20, jsonb_build_object('employee_number', 'E-100', 'absence_date', (CURRENT_DATE - 203)::text, 'action', 'put')),
    (21, jsonb_build_object('employee_number', 'E-100', 'absence_date', (CURRENT_DATE + 400)::text, 'absence_kind', 'other', 'action', 'put')),
    (22, jsonb_build_object('employee_number', 'E-100', 'absence_date', (CURRENT_DATE - 208)::text, 'absence_kind', 'Sick', 'action', 'PUT')),
    (23, jsonb_build_object('email', 'imp.dup@authz.test', 'absence_date', (CURRENT_DATE - 201)::text, 'absence_kind', 'sick', 'action', 'put'))
  ) v(n, r) $$;
GRANT EXECUTE ON FUNCTION t_imp_file(), t_imp_fp() TO authenticated;

-- J-300 B: the employee number — set by vp_hr of the same company only.
SELECT t_as(t_u('vp_u'));
SET ROLE authenticated;
INSERT INTO t_imp SELECT 'num ' || k, rpc_hr_set_employee_number('00000000-0000-0000-0000-0000000a5c01', t_u(k), n)
  FROM (VALUES ('imp_a', 'E-100'), ('imp_lv', 'E-LV'), ('imp_fu', 'E-FU'), ('imp_ng', 'E-NG')) v(k, n);
INSERT INTO t_imp SELECT 'num taken', t_err_sig(format('SELECT rpc_hr_set_employee_number(%L, %L, %L)', '00000000-0000-0000-0000-0000000a5c01', t_u('imp_b'), 'E-100'));
INSERT INTO t_imp SELECT 'num blank', t_err_sig(format('SELECT rpc_hr_set_employee_number(%L, %L, %L)', '00000000-0000-0000-0000-0000000a5c01', t_u('imp_b'), '  '));
INSERT INTO t_imp SELECT 'num other co user', t_err_sig(format('SELECT rpc_hr_set_employee_number(%L, %L, %L)', '00000000-0000-0000-0000-0000000a5c01', t_u('s_imp'), 'X-9'));
RESET ROLE;
SELECT t_as(t_u('vp_s'));
SET ROLE authenticated;
INSERT INTO t_imp SELECT 'num s ' || k, rpc_hr_set_employee_number('00000000-0000-0000-0000-0000000a5c02', t_u(k), n)
  FROM (VALUES ('s_imp', 'E-100'), ('s_imp2', 'S-1')) v(k, n);
INSERT INTO t_imp SELECT 'num vp_s on a5c01', t_err_sig(format('SELECT rpc_hr_set_employee_number(%L, %L, %L)', '00000000-0000-0000-0000-0000000a5c01', t_u('imp_b'), 'X-9'));
RESET ROLE;
SELECT t_as(t_u('mgr_u'));
SET ROLE authenticated;
INSERT INTO t_imp SELECT 'num mgr', t_err_sig(format('SELECT rpc_hr_set_employee_number(%L, %L, %L)', '00000000-0000-0000-0000-0000000a5c01', t_u('imp_b'), 'X-9'));
RESET ROLE;
SELECT t_assert('J-300 B: vp_hr sets employee numbers of her company (unique per company — E-100 also exists in SickCo); a taken number → 409 employee_number_taken; blank → 400; another company''s user → 403 access_denied; another company''s vp_hr → 403; a manager → 403; the number is not in the audit',
  (SELECT count(*) = 6 FROM t_imp WHERE label LIKE 'num %' AND j->>'status' = 'saved')
  AND (SELECT j->>'message' = 'employee_number_taken' AND j->>'details' = 'http_hint=409;code=employee_number_taken' FROM t_imp WHERE label = 'num taken')
  AND (SELECT j->>'message' = 'invalid_employee_number' AND j->>'code' = '22023' FROM t_imp WHERE label = 'num blank')
  AND (SELECT j->>'message' = 'access_denied' FROM t_imp WHERE label = 'num other co user')
  AND (SELECT j->>'message' = 'insufficient_privilege' FROM t_imp WHERE label = 'num vp_s on a5c01')
  AND (SELECT j->>'message' = 'insufficient_privilege' FROM t_imp WHERE label = 'num mgr')
  AND (SELECT employee_number = 'E-100' FROM users WHERE user_id = t_u('imp_a'))
  AND (SELECT employee_number IS NULL FROM users WHERE user_id = t_u('imp_b'))
  AND (SELECT count(*) = 6 AND bool_and(scope = jsonb_build_object('company_id', company_id)) FROM access_audit_log WHERE action = 'employee_number_set')
  AND NOT has_column_privilege('authenticated', 'users', 'employee_number', 'SELECT')
  AND (SELECT indisunique FROM pg_index WHERE indexrelid = 'uq_users_company_employee_number_ci'::regclass)
  AND to_regclass('idx_users_company_lower_email') IS NOT NULL);

-- Who may import: only an active vp_hr of the same company. Every other role (and another company's vp_hr) → 403
-- insufficient_privilege; anon cannot execute at all.
-- The SQL of a one-row stage call for company p_company (used by the refusal probes).
CREATE OR REPLACE FUNCTION t_imp_stage_sql(p_company text) RETURNS text LANGUAGE sql AS $$
  SELECT format('SELECT rpc_hr_absence_import_stage(%L, %L::jsonb)', p_company,
                '[{"employee_number":"E-100","absence_date":"2026-01-05","absence_kind":"sick","action":"put"}]') $$;
GRANT EXECUTE ON FUNCTION t_imp_stage_sql(text) TO authenticated, anon;
-- Try a stage as each non-vp_hr role (and another company's vp_hr); returns role → error message.
CREATE OR REPLACE FUNCTION t_imp_refusals() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE k text; v jsonb := '{}'::jsonb;
BEGIN
  FOREACH k IN ARRAY ARRAY['mgr_u', 'emp_gh', 'imp_a', 'cfo_u', 'le_u', 'bc_u', 'bm_u', 'os_u', 'dept_head', 'vp_s'] LOOP
    PERFORM t_as(t_u(k));
    SET LOCAL ROLE authenticated;
    v := v || jsonb_build_object(k, t_err_sig(t_imp_stage_sql('00000000-0000-0000-0000-0000000a5c01'))->>'message');
    RESET ROLE;
  END LOOP;
  RETURN v;
END $$;
SELECT t_assert('J-301 B: manager, employee, CFO, legal / ethics, board, owner, department head and another company''s vp_hr (CHRO there) cannot stage an import → 403 insufficient_privilege',
  (SELECT bool_and(value = '"insufficient_privilege"') AND count(*) = 10 FROM jsonb_each(t_imp_refusals())));
SELECT t_as(NULL);
SET ROLE anon;
SELECT t_expect_err_any('J-301 B: anon cannot execute the import RPCs', t_imp_stage_sql('00000000-0000-0000-0000-0000000a5c01'), '42501');
RESET ROLE;
SELECT t_assert('J-301 B: no client grant on the staging tables (RLS forced, no policy); only the 4 import / number RPCs are executable by authenticated; the internal helpers are not',
  NOT has_table_privilege('authenticated', 'hr_absence_import_batch', 'SELECT') AND NOT has_table_privilege('authenticated', 'hr_absence_import_row', 'SELECT')
  AND NOT has_table_privilege('authenticated', 'hr_absence_import_row', 'INSERT') AND NOT has_table_privilege('anon', 'hr_absence_import_row', 'SELECT')
  AND (SELECT bool_and(c.relrowsecurity AND c.relforcerowsecurity) FROM pg_class c WHERE c.relname IN ('hr_absence_import_batch', 'hr_absence_import_row'))
  AND NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid IN ('hr_absence_import_batch'::regclass, 'hr_absence_import_row'::regclass))
  AND (SELECT array_agg(p.proname::text ORDER BY p.proname) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND (p.proname LIKE 'fn_hr_import%' OR p.proname LIKE 'rpc_hr_absence_import%' OR p.proname IN ('rpc_hr_set_employee_number', 'rpc_hr_employee_numbers'))
          AND has_function_privilege('authenticated', p.oid, 'EXECUTE'))
      = ARRAY['rpc_hr_absence_import_commit', 'rpc_hr_absence_import_stage', 'rpc_hr_absence_import_validate', 'rpc_hr_employee_numbers', 'rpc_hr_set_employee_number']);

-- Input checks of the stage (400) — J-307 C: CSV columns only, no reason / free-text column (J-267 C).
SELECT t_as(t_u('vp_u'));
SET ROLE authenticated;
INSERT INTO t_imp SELECT 'stage ' || l, t_err_sig(format('SELECT rpc_hr_absence_import_stage(%L, %L::jsonb, NULL, %L)', '00000000-0000-0000-0000-0000000a5c01', r, sha))
  FROM (VALUES ('empty', '[]', NULL), ('not array', '{"employee_number":"E-100"}', NULL), ('scalar row', '["E-100"]', NULL),
               ('reason column', '[{"employee_number":"E-100","absence_date":"2026-01-05","absence_kind":"sick","action":"put","reason":"x"}]', NULL),
               ('bad sha', '[{"employee_number":"E-100","absence_date":"2026-01-05","absence_kind":"sick","action":"put"}]', 'abc')) v(l, r, sha);
RESET ROLE;
SELECT t_assert('J-307 C: the stage refuses an empty / non-array / non-object input and any column outside the 5 CSV columns (a reason column) → 400 invalid_import_rows; a malformed SHA-256 → 400 invalid_source_sha256; nothing staged',
  (SELECT bool_and(j->>'code' = '22023' AND j->>'message' = 'invalid_import_rows') AND count(*) = 4 FROM t_imp WHERE label IN ('stage empty', 'stage not array', 'stage scalar row', 'stage reason column'))
  AND (SELECT j->>'message' = 'invalid_source_sha256' FROM t_imp WHERE label = 'stage bad sha')
  AND NOT EXISTS (SELECT 1 FROM hr_absence_import_batch));

-- Stage + dry run of the main file.
SELECT t_as(t_u('vp_u'));
SET ROLE authenticated;
INSERT INTO t_imp SELECT 'stage', rpc_hr_absence_import_stage('00000000-0000-0000-0000-0000000a5c01', t_imp_file(), 'absences_nov.csv', repeat('ab', 32));
-- J-331 B: the stage writes its own audit row, so the "dry run writes nothing" fingerprint is taken after it.
INSERT INTO t_imp SELECT 'fp0', to_jsonb(t_imp_fp());
INSERT INTO t_imp SELECT 'commit before dry run', t_err_sig(format('SELECT rpc_hr_absence_import_commit(%L, %L)', '00000000-0000-0000-0000-0000000a5c01', (SELECT j->>'batch_id' FROM t_imp WHERE label = 'stage')));
INSERT INTO t_imp SELECT 'dry', rpc_hr_absence_import_validate('00000000-0000-0000-0000-0000000a5c01', (SELECT (j->>'batch_id')::uuid FROM t_imp WHERE label = 'stage'));
INSERT INTO t_imp SELECT 'dry again', rpc_hr_absence_import_validate('00000000-0000-0000-0000-0000000a5c01', (SELECT (j->>'batch_id')::uuid FROM t_imp WHERE label = 'stage'));
RESET ROLE;
-- One row entry (row_no p_n) of a stored import report.
CREATE OR REPLACE FUNCTION t_imp_row(p_label text, p_n int) RETURNS jsonb LANGUAGE sql AS $$
  SELECT e FROM t_imp, jsonb_array_elements(j->'rows') e WHERE label = p_label AND (e->>'row_no')::int = p_n $$;
-- 'outcome/code' of one row of a stored import report ('-' = no code).
CREATE OR REPLACE FUNCTION t_imp_code(p_label text, p_n int) RETURNS text LANGUAGE sql AS $$
  SELECT t_imp_row(p_label, p_n)->>'outcome' || '/' || COALESCE(t_imp_row(p_label, p_n)->>'code', '-') $$;
SELECT t_assert('J-301 B: the stage returns the batch (23 rows, staged); a commit before any dry run → 409 import_batch_not_validated',
  (SELECT j->>'status' = 'staged' AND (j->>'rows')::int = 23 FROM t_imp WHERE label = 'stage')
  AND (SELECT j->>'message' = 'import_batch_not_validated' AND j->>'details' = 'http_hint=409;code=import_batch_not_validated' FROM t_imp WHERE label = 'commit before dry run'));
SELECT t_assert('J-301 B: the DRY RUN writes nothing to hr_absence_entry and nothing to the audit (fingerprint + audit count unchanged, twice); it is repeatable (same report)',
  t_imp_fp() = (SELECT j #>> '{}' FROM t_imp WHERE label = 'fp0')
  AND (SELECT j FROM t_imp WHERE label = 'dry') = (SELECT j FROM t_imp WHERE label = 'dry again'));
SELECT t_assert('J-300 B: matched by employee number (rows 5–7), by e-mail when the number is empty — case-insensitive and trimmed (row 3 = imp_a in capitals, row 4 = imp_b); codes are case-insensitive (row 22 PUT / Sick); any date, also far in the future (row 21, J-304 A)',
  t_imp_code('dry', 3) = 'accepted/-' AND t_imp_code('dry', 4) = 'accepted/-' AND t_imp_code('dry', 5) = 'accepted/-'
  AND t_imp_code('dry', 6) = 'accepted/-' AND t_imp_code('dry', 7) = 'accepted/-' AND t_imp_code('dry', 21) = 'accepted/-'
  AND t_imp_code('dry', 22) = 'accepted/-');
SELECT t_assert('J-303 B: an own leaver → ''leaver'' (row 9); another company''s employee by number or e-mail (rows 11, 12), an unknown number (13), a user without an employee profile (14) and an ambiguous e-mail (23) → the SAME opaque ''unmatched''; no key → ''missing_key''; J-297 B: an end date in the future is still active (row 10 accepted)',
  t_imp_code('dry', 9) = 'rejected/leaver' AND t_imp_code('dry', 10) = 'accepted/-'
  AND t_imp_code('dry', 11) = 'rejected/unmatched' AND t_imp_code('dry', 12) = 'rejected/unmatched'
  AND t_imp_code('dry', 13) = 'rejected/unmatched' AND t_imp_code('dry', 14) = 'rejected/unmatched'
  AND t_imp_code('dry', 23) = 'rejected/unmatched' AND t_imp_code('dry', 15) = 'rejected/missing_key');
SELECT t_assert('J-305 C / J-307 C: invalid action (16), impossible date 2026-02-30 (17), non-ISO date (18), invalid kind (19), put without a kind (20) → rejected with their codes; a cancel of a day with no stored row → no_entry (8) — nothing is cancelled implicitly',
  t_imp_code('dry', 16) = 'rejected/invalid_action' AND t_imp_code('dry', 17) = 'rejected/invalid_date'
  AND t_imp_code('dry', 18) = 'rejected/invalid_date' AND t_imp_code('dry', 19) = 'rejected/invalid_kind'
  AND t_imp_code('dry', 20) = 'rejected/invalid_kind' AND t_imp_code('dry', 8) = 'rejected/no_entry');
SELECT t_assert('J-306 C: imp_a on the same day 3 times (rows 1–3, by number and by e-mail): the LAST row (3) wins; row 2 (same values) collapses as a duplicate; row 1 is superseded with code ''conflict'' and the report lists BOTH rows with their file values',
  t_imp_code('dry', 1) = 'superseded/conflict' AND t_imp_code('dry', 2) = 'duplicate/duplicate'
  AND (t_imp_row('dry', 1)->>'winner_row_no')::int = 3 AND (t_imp_row('dry', 2)->>'winner_row_no')::int = 3
  AND (SELECT jsonb_array_length(j->'conflicts') = 1
              AND j->'conflicts'->0->>'code' = 'conflict'
              AND j->'conflicts'->0->'superseded' = jsonb_build_object('row_no', 1, 'employee_number', 'E-100', 'email', NULL, 'absence_date', (CURRENT_DATE - 201)::text, 'absence_kind', 'sick', 'action', 'put')
              AND j->'conflicts'->0->'winner' = jsonb_build_object('row_no', 3, 'employee_number', NULL, 'email', 'IMP_A@AUTHZ.TEST', 'absence_date', (CURRENT_DATE - 201)::text, 'absence_kind', 'other', 'action', 'put')
         FROM t_imp WHERE label = 'dry'));
SELECT t_assert('J-301 B: the report counts (23 rows: 8 accepted, 13 rejected, 1 duplicate, 1 superseded) and carries no user id, name or other person data',
  (SELECT j->'counts' = '{"rows": 23, "accepted": 8, "rejected": 13, "duplicate": 1, "superseded": 1, "exception": 0}'::jsonb
          AND j->>'status' = 'validated' AND NOT (j::text ~* '(user_id|full_name|Fixture|imp_b@|s_imp)') FROM t_imp WHERE label = 'dry'));

-- Another company's vp_hr cannot see, validate or commit the batch.
SELECT t_as(t_u('vp_s'));
SET ROLE authenticated;
INSERT INTO t_imp SELECT 'vp_s ' || l, t_err_sig(format(f, c, (SELECT j->>'batch_id' FROM t_imp WHERE label = 'stage')))
  FROM (VALUES ('validate own co', 'SELECT rpc_hr_absence_import_validate(%L, %L)', '00000000-0000-0000-0000-0000000a5c02'),
               ('commit own co', 'SELECT rpc_hr_absence_import_commit(%L, %L)', '00000000-0000-0000-0000-0000000a5c02'),
               ('validate a5c01', 'SELECT rpc_hr_absence_import_validate(%L, %L)', '00000000-0000-0000-0000-0000000a5c01'),
               ('commit a5c01', 'SELECT rpc_hr_absence_import_commit(%L, %L)', '00000000-0000-0000-0000-0000000a5c01')) v(l, f, c);
INSERT INTO t_imp SELECT 'vp_s unknown', t_err_sig(format('SELECT rpc_hr_absence_import_validate(%L, %L)', '00000000-0000-0000-0000-0000000a5c02', gen_random_uuid()));
-- …and in her own company, a5c01's employees (number E-100 → her own s_imp; imp_a's e-mail) do not leak in.
INSERT INTO t_imp SELECT 'vp_s stage', rpc_hr_absence_import_stage('00000000-0000-0000-0000-0000000a5c02',
  '[{"email":"imp_a@authz.test","absence_date":"2026-01-05","absence_kind":"sick","action":"put"},
    {"employee_number":"E-LV","absence_date":"2026-01-05","absence_kind":"sick","action":"put"},
    {"employee_number":"E-100","absence_date":"2026-01-05","absence_kind":"sick","action":"put"}]'::jsonb);
INSERT INTO t_imp SELECT 'vp_s dry', rpc_hr_absence_import_validate('00000000-0000-0000-0000-0000000a5c02', (SELECT (j->>'batch_id')::uuid FROM t_imp WHERE label = 'vp_s stage'));
RESET ROLE;
SELECT t_assert('J-303 B / J-301 B: another company''s vp_hr — the batch with her company id → 403 access_denied, identical to an unknown batch id; with the batch''s company id → 403 insufficient_privilege; in her own import, a5c01''s employee (e-mail) and a5c01''s LEAVER (E-LV) are just ''unmatched'' (no leaver hint across companies) and E-100 matches her own employee',
  (SELECT count(DISTINCT j - 'ctx') = 1 AND bool_and(j->>'message' = 'access_denied') FROM t_imp WHERE label IN ('vp_s validate own co', 'vp_s commit own co', 'vp_s unknown'))
  AND (SELECT bool_and(j->>'message' = 'insufficient_privilege') FROM t_imp WHERE label IN ('vp_s validate a5c01', 'vp_s commit a5c01'))
  AND t_imp_code('vp_s dry', 1) = 'rejected/unmatched' AND t_imp_code('vp_s dry', 2) = 'rejected/unmatched'
  AND t_imp_code('vp_s dry', 3) = 'accepted/-');

-- Commit.
CREATE TEMP TABLE t_imp_before AS
  SELECT d, (t_imp_entry('imp_a', d)).* FROM unnest(ARRAY[205, 206, 207, 208]) d;
SELECT t_as(t_u('vp_u'));
SET ROLE authenticated;
INSERT INTO t_imp SELECT 'commit', rpc_hr_absence_import_commit('00000000-0000-0000-0000-0000000a5c01', (SELECT (j->>'batch_id')::uuid FROM t_imp WHERE label = 'stage'));
INSERT INTO t_imp SELECT 'commit again', t_err_sig(format('SELECT rpc_hr_absence_import_commit(%L, %L)', '00000000-0000-0000-0000-0000000a5c01', (SELECT j->>'batch_id' FROM t_imp WHERE label = 'stage')));
INSERT INTO t_imp SELECT 'validate after commit', t_err_sig(format('SELECT rpc_hr_absence_import_validate(%L, %L)', '00000000-0000-0000-0000-0000000a5c01', (SELECT j->>'batch_id' FROM t_imp WHERE label = 'stage')));
RESET ROLE;
SELECT t_assert('J-301 B: the commit applies the 8 accepted rows only (7 puts, 1 cancel) and returns the report; status committed',
  (SELECT j->>'status' = 'committed' AND j->'written' = '{"put": 7, "cancel": 1}'::jsonb AND (j->'counts'->>'accepted')::int = 8 FROM t_imp WHERE label = 'commit')
  AND (t_imp_entry('imp_a', 201)).absence_kind = 'other'
  AND (t_imp_entry('imp_b', 202)).absence_kind = 'sick'
  AND (t_imp_entry('imp_fu', 201)).absence_kind = 'sick'
  AND (SELECT absence_kind = 'other' FROM hr_absence_entry WHERE user_id = t_u('imp_a') AND absence_date = CURRENT_DATE + 400)
  AND (t_imp_entry('imp_lv', 201)).entry_id IS NULL AND (t_imp_entry('imp_a', 203)).entry_id IS NULL AND (t_imp_entry('imp_a', 209)).entry_id IS NULL
  AND NOT EXISTS (SELECT 1 FROM hr_absence_entry WHERE user_id IN (t_u('s_imp'), t_u('s_imp2'), t_u('imp_ng'), t_u('imp_d1'), t_u('imp_d2'))));
SELECT t_assert('J-279 A: a re-put keeps the entry id and the coordination status and takes the new kind (205: sick → other, still coordinated); a needs_review day becomes reviewed (208); a cancelled day is re-opened as pending_coordination (206); cancel = status only, the row stays (207)',
  (SELECT e.entry_id = b.entry_id AND e.absence_kind = 'other' AND e.coordination_status = 'coordinated' AND e.cancelled_at IS NULL
     FROM t_imp_before b, t_imp_entry('imp_a', 205) e WHERE b.d = 205)
  AND (SELECT e.entry_id = b.entry_id AND e.absence_kind = 'sick' AND e.kind_review_status = 'reviewed' FROM t_imp_before b, t_imp_entry('imp_a', 208) e WHERE b.d = 208)
  AND (SELECT e.entry_id = b.entry_id AND e.absence_kind = 'sick' AND e.cancelled_at IS NULL AND e.coordination_status = 'pending_coordination'
     FROM t_imp_before b, t_imp_entry('imp_a', 206) e WHERE b.d = 206)
  AND (SELECT e.entry_id = b.entry_id AND e.cancelled_at IS NOT NULL AND e.absence_kind = 'sick' FROM t_imp_before b, t_imp_entry('imp_a', 207) e WHERE b.d = 207));
SELECT t_assert('J-302 A: one WORM audit row per write WITH the kind (put / cancel shape + import_batch_id; the employee is the subject) — 7 put rows, 1 cancel row — plus ONE header row (company, batch, counts, file name + hash; no kind, no person)',
  (SELECT count(*) = 7 AND bool_and(scope ? 'absence_kind' AND scope->>'absence_kind' IN ('sick', 'other') AND subject_user_id IS NOT NULL AND viewer_id = t_u('vp_u'))
     FROM access_audit_log WHERE action = 'hr_absence_put' AND scope->>'import_batch_id' = (SELECT j->>'batch_id' FROM t_imp WHERE label = 'stage'))
  AND (SELECT count(*) = 1 AND bool_and(scope->>'absence_kind' = 'sick' AND subject_user_id = t_u('imp_a'))
     FROM access_audit_log WHERE action = 'hr_absence_cancel' AND scope->>'import_batch_id' = (SELECT j->>'batch_id' FROM t_imp WHERE label = 'stage'))
  AND (SELECT count(*) = 1 AND bool_and(subject_user_id IS NULL AND scope->>'source_filename' = 'absences_nov.csv' AND scope->>'source_sha256' = repeat('ab', 32)
                                         AND (scope->'counts'->>'put')::int = 7 AND (scope->'counts'->>'cancel')::int = 1 AND (scope->'counts'->>'rows')::int = 23
                                         AND NOT (scope::text ~* '(absence_kind|sick|other|user_id)'))
     FROM access_audit_log WHERE action = 'hr_absence_import_commit'));
SELECT t_assert('J-301 B: a second commit of the same batch → 409 import_batch_committed (nothing written twice); a dry run on it → 409 too; the committed batch rows cannot be changed',
  (SELECT j->>'message' = 'import_batch_committed' AND j->>'details' = 'http_hint=409;code=import_batch_committed' FROM t_imp WHERE label = 'commit again')
  AND (SELECT j->>'message' = 'import_batch_committed' FROM t_imp WHERE label = 'validate after commit')
  AND (SELECT count(*) = 1 FROM access_audit_log WHERE action = 'hr_absence_import_commit')
  AND t_err_sig($q$UPDATE hr_absence_import_row SET code = 'x' WHERE row_no = 1 AND batch_id = (SELECT batch_id FROM hr_absence_import_batch WHERE status = 'committed')$q$)->>'message' = 'import_batch_committed');
-- J-284 extended to the import: the kind never reaches a manager, export, CHRO or board object through it.
SELECT t_assert('J-284 / J-308 A: no function outside the HR-absence family (fn_hr_* / rpc_hr_*) reads the import tables; no manager / export / CHRO / report / board function reads them; every import RPC starts with the vp_hr check',
  NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
               WHERE n.nspname = 'public' AND p.prosrc ~* 'hr_absence_import_(row|batch)'
                 AND p.proname !~ '^(fn|rpc)_hr_')
  AND NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
               WHERE n.nspname = 'public' AND p.proname ~* '(export|chro|dossier|report|csv|board|manager|offboard)'
                 AND p.prosrc ~* '(hr_absence_import|fn_hr_import)')
  AND NOT EXISTS (SELECT 1 FROM pg_views v WHERE v.schemaname = 'public' AND v.definition ~* 'hr_absence_import')
  AND (SELECT bool_and(p.prosrc ~ 'fn_assert_vp_hr\(p_company_id\)|fn_hr_import_batch_of\(p_company_id')
         FROM pg_proc p WHERE p.proname IN ('rpc_hr_absence_import_stage', 'rpc_hr_absence_import_validate', 'rpc_hr_absence_import_commit', 'rpc_hr_set_employee_number', 'rpc_hr_employee_numbers')));

-- ============ 17. Karin 25.11 — import J-329 C, J-331 B, J-332 B, J-333 A, J-334 A, J-335 A, J-336 B, J-337 B, J-338 A ============
SELECT FROM t_mk('vp_u2', 'HR', 'vp_hr', 'employee');
-- Stage + dry run as one vp_hr; returns the stage result and the report (helper, client rights).
CREATE OR REPLACE FUNCTION t_imp_run(p_label text, p_rows jsonb) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_stage jsonb;
BEGIN
  v_stage := rpc_hr_absence_import_stage('00000000-0000-0000-0000-0000000a5c01', p_rows);
  INSERT INTO t_imp VALUES (p_label || ' stage', v_stage);
  INSERT INTO t_imp VALUES (p_label, rpc_hr_absence_import_validate('00000000-0000-0000-0000-0000000a5c01', (v_stage->>'batch_id')::uuid));
END $$;
-- The batch id of a labelled stage.
CREATE OR REPLACE FUNCTION t_imp_batch(p_label text) RETURNS uuid LANGUAGE sql AS $$
  SELECT (j->>'batch_id')::uuid FROM t_imp WHERE label = p_label || ' stage' $$;
-- One CSV row object (empty strings are left out).
CREATE OR REPLACE FUNCTION t_imp_csv(p_num text, p_email text, p_days int, p_kind text, p_action text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_strip_nulls(jsonb_build_object('employee_number', p_num, 'email', p_email,
                                              'absence_date', (CURRENT_DATE - p_days)::text, 'absence_kind', p_kind, 'action', p_action)) $$;
GRANT EXECUTE ON FUNCTION t_imp_run(text, jsonb), t_imp_batch(text), t_imp_csv(text, text, int, text, text), t_imp_row(text, int), t_imp_code(text, int) TO authenticated;

-- J-335 A: the row limit starts EMPTY (לא הוגדר) — no limit; a configured limit is enforced (422), reset → empty again.
SELECT t_as(t_u('vp_u'));
SET ROLE authenticated;
INSERT INTO t_imp SELECT 'lim get', to_jsonb(g) FROM rpc_get_agent_settings('00000000-0000-0000-0000-0000000a5c01') g WHERE g.setting_key = 'hr_import_max_rows';
SELECT t_imp_run('lim none', jsonb_build_array(t_imp_csv('E-100', NULL, 300, 'sick', 'put'), t_imp_csv('E-100', NULL, 299, 'sick', 'put'), t_imp_csv('E-100', NULL, 298, 'sick', 'put')));
INSERT INTO t_imp SELECT 'lim bad ' || v, t_err_sig(format('SELECT rpc_put_agent_setting(%L, %L, %s)', '00000000-0000-0000-0000-0000000a5c01', 'hr_import_max_rows', v))
  FROM unnest(ARRAY['0', '1.5']) v;
SELECT FROM rpc_put_agent_setting('00000000-0000-0000-0000-0000000a5c01', 'hr_import_max_rows', 2);
INSERT INTO t_imp SELECT 'lim over', t_err_sig(format('SELECT rpc_hr_absence_import_stage(%L, %L::jsonb)', '00000000-0000-0000-0000-0000000a5c01',
  jsonb_build_array(t_imp_csv('E-100', NULL, 300, 'sick', 'put'), t_imp_csv('E-100', NULL, 299, 'sick', 'put'), t_imp_csv('E-100', NULL, 298, 'sick', 'put'))));
INSERT INTO t_imp SELECT 'lim at', rpc_hr_absence_import_stage('00000000-0000-0000-0000-0000000a5c01',
  jsonb_build_array(t_imp_csv('E-100', NULL, 300, 'sick', 'put'), t_imp_csv('E-100', NULL, 299, 'sick', 'put')));
SELECT FROM rpc_put_agent_setting('00000000-0000-0000-0000-0000000a5c01', 'hr_import_max_rows', NULL);
INSERT INTO t_imp SELECT 'lim reset', to_jsonb(g) FROM rpc_get_agent_settings('00000000-0000-0000-0000-0000000a5c01') g WHERE g.setting_key = 'hr_import_max_rows';
RESET ROLE;
SELECT t_assert('J-335 A: hr_import_max_rows starts empty (not_defined, no value — לא הוגדר) and then no limit is enforced (3 rows staged; the stage reports row_limit ''לא הוגדר''); 0 or 1.5 → 400; with 2 configured: 3 rows → 422 import_too_many_rows (nothing staged), 2 rows pass (row_limit 2); reset → empty again',
  (SELECT j->>'value_status' = 'not_defined' AND j->>'value_numeric' IS NULL FROM t_imp WHERE label = 'lim get')
  AND (SELECT value_status = 'not_defined' AND value_numeric IS NULL FROM agent_settings WHERE company_id IS NULL AND setting_key = 'hr_import_max_rows')
  AND (SELECT (j->>'rows')::int = 3 AND j->>'row_limit' = 'לא הוגדר' FROM t_imp WHERE label = 'lim none stage')
  AND (SELECT bool_and(j->>'message' = 'invalid_setting_value') AND count(*) = 2 FROM t_imp WHERE label LIKE 'lim bad %')
  AND (SELECT j->>'message' = 'import_too_many_rows' AND j->>'details' = 'http_hint=422;code=import_too_many_rows' FROM t_imp WHERE label = 'lim over')
  AND (SELECT (j->>'row_limit')::int = 2 AND (j->>'rows')::int = 2 FROM t_imp WHERE label = 'lim at')
  AND (SELECT j->>'value_status' = 'not_defined' FROM t_imp WHERE label = 'lim reset')
  AND (SELECT count(*) = 1 FROM hr_absence_import_batch b WHERE (SELECT count(*) FROM hr_absence_import_row r WHERE r.batch_id = b.batch_id) = 3
                                                           AND b.batch_id = t_imp_batch('lim none')));

-- J-331 B: every stage is audited — who (viewer) and when (created_at), company, batch, row count; no kind, no cell.
SELECT t_assert('J-331 B: each stage writes ONE audit row hr_absence_import_stage (viewer = the vp_hr, created_at = when; scope = company, batch, rows only — no kind, no file cell); a refused stage (422) writes none',
  (SELECT count(*) = 1 AND bool_and(viewer_id = t_u('vp_u') AND created_at IS NOT NULL AND subject_user_id IS NULL
                                    AND (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(scope) k) = ARRAY['company_id', 'import_batch_id', 'rows']
                                    AND (scope->>'rows')::int = 3)
     FROM access_audit_log WHERE action = 'hr_absence_import_stage' AND scope->>'import_batch_id' = t_imp_batch('lim none')::text)
  AND (SELECT count(*) FROM access_audit_log WHERE action = 'hr_absence_import_stage')
      = (SELECT count(*) FROM hr_absence_import_batch)
  AND NOT EXISTS (SELECT 1 FROM access_audit_log WHERE action = 'hr_absence_import_stage' AND scope::text ~* '(absence_kind|sick|other|E-100|@)'));

-- J-329 C / J-334 A / J-337 B in one file.
SELECT t_as(t_u('vp_u'));
SET ROLE authenticated;
SELECT t_imp_run('ex', jsonb_build_array(
  t_imp_csv('e-100', NULL, 310, 'SICK', 'Put'),                  -- 1 lower-case number, upper-case values → imp_a
  t_imp_csv('E-100', 'IMP_B@authz.test', 311, 'sick', 'put'),     -- 2 number = imp_a, e-mail = imp_b → identity_mismatch
  t_imp_csv('E-100', 'Imp_A@Authz.Test', 312, 'sick', 'put'),     -- 3 both keys = imp_a → accepted
  t_imp_csv('E-100', 'nobody@authz.test', 313, 'sick', 'put'),    -- 4 e-mail names nobody → number wins
  t_imp_csv(NULL, 'imp_b@authz.test', 314, 'sick', 'put'),        -- 5 put …
  t_imp_csv(NULL, 'imp_b@authz.test', 314, NULL, 'cancel'),       -- 6 … and cancel, no stored row → put_cancel_same_day
  t_imp_csv(NULL, 'imp_b@authz.test', 315, NULL, 'cancel'),       -- 7 cancel then …
  t_imp_csv(NULL, 'imp_b@authz.test', 315, 'other', 'put'),       -- 8 … put (other order), no stored row → exception
  t_imp_csv('E-100', NULL, 205, 'sick', 'put'),                   -- 9 put …
  t_imp_csv('E-100', NULL, 205, NULL, 'cancel')));                -- 10 … and cancel of a STORED day → last wins (conflict)
INSERT INTO t_imp SELECT 'num case dup', t_err_sig(format('SELECT rpc_hr_set_employee_number(%L, %L, %L)', '00000000-0000-0000-0000-0000000a5c01', t_u('imp_b'), 'e-100'));
RESET ROLE;
SELECT t_assert('J-334 A: values are case-insensitive — a lower-case employee number matches E-100, SICK / Put are accepted; the setter refuses e-100 for another employee (409, the number is unique case-insensitively)',
  t_imp_code('ex', 1) = 'accepted/-' AND t_imp_code('ex', 3) = 'accepted/-' AND t_imp_code('ex', 4) = 'accepted/-'
  AND (SELECT j->>'message' = 'employee_number_taken' FROM t_imp WHERE label = 'num case dup'));
SELECT t_assert('J-329 C: number and e-mail naming two DIFFERENT employees → outcome ''exception'', code identity_mismatch; both keys naming the same employee, or an e-mail naming nobody, are accepted',
  t_imp_code('ex', 2) = 'exception/identity_mismatch');
SELECT t_assert('J-337 B: a day the file both puts and cancels with no stored row → every row of that day is an exception put_cancel_same_day, in either order (rows 5+6, 7+8); with a stored row the last row wins as before (rows 9–10: conflict)',
  t_imp_code('ex', 5) = 'exception/put_cancel_same_day' AND t_imp_code('ex', 6) = 'exception/put_cancel_same_day'
  AND t_imp_code('ex', 7) = 'exception/put_cancel_same_day' AND t_imp_code('ex', 8) = 'exception/put_cancel_same_day'
  AND t_imp_code('ex', 9) = 'superseded/conflict' AND t_imp_code('ex', 10) = 'accepted/-');
SELECT t_assert('J-329 C / J-337 B ALERT: the report says requires_attention = true, counts 5 exceptions and lists them — one identity_mismatch entry with its row, one entry per put+cancel day with BOTH rows (file values); no user id',
  (SELECT (j->>'requires_attention')::boolean AND (j->'counts'->>'exception')::int = 5
          AND jsonb_array_length(j->'exceptions') = 3
          AND j->'exceptions'->0->>'code' = 'identity_mismatch' AND j->'exceptions'->0->'rows'->0->>'row_no' = '2'
          AND j->'exceptions'->0->'rows'->0->>'email' = 'IMP_B@authz.test'
          AND j->'exceptions'->1->>'code' = 'put_cancel_same_day'
          AND (SELECT array_agg((e->>'row_no')::int ORDER BY (e->>'row_no')::int) FROM jsonb_array_elements(j->'exceptions'->1->'rows') e) = ARRAY[5, 6]
          AND (SELECT array_agg((e->>'row_no')::int ORDER BY (e->>'row_no')::int) FROM jsonb_array_elements(j->'exceptions'->2->'rows') e) = ARRAY[7, 8]
          AND NOT (j::text ~* '(user_id|full_name|Fixture)')
     FROM t_imp WHERE label = 'ex')
  AND (SELECT NOT (j->>'requires_attention')::boolean AND j->'exceptions' = '[]'::jsonb FROM t_imp WHERE label = 'lim none'));
-- J-333 A: another vp_hr of the same company commits the batch vp_u staged; exceptions are never written.
SELECT t_as(t_u('vp_u2'));
SET ROLE authenticated;
INSERT INTO t_imp SELECT 'ex commit', rpc_hr_absence_import_commit('00000000-0000-0000-0000-0000000a5c01', t_imp_batch('ex'));
RESET ROLE;
SELECT t_assert('J-333 A: a second vp_hr of the company (not the uploader) commits the batch — created_by = vp_u, committed_by = vp_u2; J-329 C / J-337 B: the exception rows are not written (days 311, 314, 315), the accepted ones are (310, 312, 313, the 205 cancel)',
  (SELECT created_by = t_u('vp_u') AND committed_by = t_u('vp_u2') AND status = 'committed' FROM hr_absence_import_batch WHERE batch_id = t_imp_batch('ex'))
  AND (SELECT j->'written' = '{"put": 3, "cancel": 1}'::jsonb FROM t_imp WHERE label = 'ex commit')
  AND (t_imp_entry('imp_a', 310)).absence_kind = 'sick' AND (t_imp_entry('imp_a', 312)).entry_id IS NOT NULL AND (t_imp_entry('imp_a', 313)).entry_id IS NOT NULL
  AND (t_imp_entry('imp_a', 311)).entry_id IS NULL AND (t_imp_entry('imp_b', 311)).entry_id IS NULL
  AND (t_imp_entry('imp_b', 314)).entry_id IS NULL AND (t_imp_entry('imp_b', 315)).entry_id IS NULL
  AND (t_imp_entry('imp_a', 205)).cancelled_at IS NOT NULL);

-- J-332 B: a change between dry run and commit stops the commit; a new dry run is required.
SELECT t_as(t_u('vp_u'));
SET ROLE authenticated;
SELECT t_imp_run('chg row', jsonb_build_array(t_imp_csv('E-100', NULL, 320, 'sick', 'put')));
SELECT t_imp_run('chg user', jsonb_build_array(t_imp_csv(NULL, 'imp_b@authz.test', 321, 'other', 'put')));
SELECT t_imp_run('chg none', jsonb_build_array(t_imp_csv('E-FU', NULL, 322, 'other', 'put')));
RESET ROLE;
-- Between the dry run and the commit: a stored row appears on a file day (by hand) and imp_b gets a future end date.
INSERT INTO hr_absence_entry (user_id, company_id, absence_date, absence_kind) VALUES (t_u('imp_a'), '00000000-0000-0000-0000-0000000a5c01', CURRENT_DATE - 320, 'other');
-- (only the import's write actions are counted: a new end date fires the offboarding triggers, which audit themselves)
CREATE TEMP TABLE t_imp_audit0 AS SELECT count(*) AS n FROM access_audit_log WHERE action IN ('hr_absence_put', 'hr_absence_cancel', 'hr_absence_import_commit');
SELECT t_as(t_u('vp_u'));
SET ROLE authenticated;
INSERT INTO t_imp SELECT 'chg row commit', t_err_sig(format('SELECT rpc_hr_absence_import_commit(%L, %L)', '00000000-0000-0000-0000-0000000a5c01', t_imp_batch('chg row')));
RESET ROLE;
UPDATE users SET employment_ended_at = clock_timestamp() + interval '10 days' WHERE user_id = t_u('imp_b');
SELECT t_as(t_u('vp_u'));
SET ROLE authenticated;
INSERT INTO t_imp SELECT 'chg user commit', t_err_sig(format('SELECT rpc_hr_absence_import_commit(%L, %L)', '00000000-0000-0000-0000-0000000a5c01', t_imp_batch('chg user')));
INSERT INTO t_imp SELECT 'chg user commit2', t_err_sig(format('SELECT rpc_hr_absence_import_commit(%L, %L)', '00000000-0000-0000-0000-0000000a5c01', t_imp_batch('chg user')));
RESET ROLE;
SELECT t_assert('J-332 B: a stored row that appeared on a file day, or a change to a named employee (a new end date — even one still in the future), makes the commit stop with 409 import_batch_changed — again on a retry — nothing written, no audit row',
  (SELECT j->>'message' = 'import_batch_changed' AND j->>'details' = 'http_hint=409;code=import_batch_changed' FROM t_imp WHERE label = 'chg row commit')
  AND (SELECT bool_and(j->>'message' = 'import_batch_changed') FROM t_imp WHERE label IN ('chg user commit', 'chg user commit2'))
  AND (SELECT count(*) FROM access_audit_log WHERE action IN ('hr_absence_put', 'hr_absence_cancel', 'hr_absence_import_commit')) = (SELECT n FROM t_imp_audit0)
  AND (t_imp_entry('imp_a', 320)).absence_kind = 'other' AND (t_imp_entry('imp_b', 321)).entry_id IS NULL
  AND (SELECT bool_and(status = 'validated') FROM hr_absence_import_batch WHERE batch_id IN (t_imp_batch('chg row'), t_imp_batch('chg user'))));
SELECT t_as(t_u('vp_u2'));
SET ROLE authenticated;
INSERT INTO t_imp SELECT 'chg row dry2', rpc_hr_absence_import_validate('00000000-0000-0000-0000-0000000a5c01', t_imp_batch('chg row'));
INSERT INTO t_imp SELECT 'chg row commit3', rpc_hr_absence_import_commit('00000000-0000-0000-0000-0000000a5c01', t_imp_batch('chg row'));
INSERT INTO t_imp SELECT 'chg user dry2', rpc_hr_absence_import_validate('00000000-0000-0000-0000-0000000a5c01', t_imp_batch('chg user'));
INSERT INTO t_imp SELECT 'chg user commit3', rpc_hr_absence_import_commit('00000000-0000-0000-0000-0000000a5c01', t_imp_batch('chg user'));
INSERT INTO t_imp SELECT 'chg none commit', rpc_hr_absence_import_commit('00000000-0000-0000-0000-0000000a5c01', t_imp_batch('chg none'));
RESET ROLE;
SELECT t_assert('J-332 B / J-333 A: after a NEW dry run (by the other vp_hr) the commit passes — the stored day takes the file kind (J-279 re-put: other → sick), imp_b (end date in the future = still active) gets her day; a batch whose inputs did not change commits without a new dry run',
  (SELECT j->>'status' = 'committed' FROM t_imp WHERE label = 'chg row commit3') AND (t_imp_entry('imp_a', 320)).absence_kind = 'sick'
  AND (SELECT j->>'status' = 'committed' FROM t_imp WHERE label = 'chg user commit3') AND (t_imp_entry('imp_b', 321)).absence_kind = 'other'
  AND (SELECT j->>'status' = 'committed' FROM t_imp WHERE label = 'chg none commit') AND (t_imp_entry('imp_fu', 322)).absence_kind = 'other');

-- J-336 B: the dedicated employee-number reader.
CREATE TEMP TABLE t_imp_audit1 AS SELECT count(*) AS n FROM access_audit_log;
SELECT t_as(t_u('vp_u'));
SET ROLE authenticated;
INSERT INTO t_imp SELECT 'numbers', jsonb_agg(to_jsonb(r)) FROM rpc_hr_employee_numbers('00000000-0000-0000-0000-0000000a5c01') r;
RESET ROLE;
SELECT t_as(t_u('vp_s'));
SET ROLE authenticated;
INSERT INTO t_imp SELECT 'numbers vp_s', t_err_sig(format('SELECT * FROM rpc_hr_employee_numbers(%L)', '00000000-0000-0000-0000-0000000a5c01'));
RESET ROLE;
SELECT t_as(t_u('mgr_u'));
SET ROLE authenticated;
INSERT INTO t_imp SELECT 'numbers mgr', t_err_sig(format('SELECT * FROM rpc_hr_employee_numbers(%L)', '00000000-0000-0000-0000-0000000a5c01'));
RESET ROLE;
SELECT t_assert('J-336 B: vp_hr of the company reads full name, e-mail and number of the ACTIVE employees (E-100 / E-FU set, imp_b NULL; the leaver E-LV and the no-profile E-NG are not listed; no user id); another company''s vp_hr and a manager → 403; the read is not logged (J-292); the company list still has no number',
  (SELECT (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(j->0) k) = ARRAY['email', 'employee_number', 'full_name']
          AND EXISTS (SELECT 1 FROM jsonb_array_elements(j) e WHERE e->>'email' = 'imp_a@authz.test' AND e->>'employee_number' = 'E-100')
          AND EXISTS (SELECT 1 FROM jsonb_array_elements(j) e WHERE e->>'email' = 'imp_fu@authz.test' AND e->>'employee_number' = 'E-FU')
          AND EXISTS (SELECT 1 FROM jsonb_array_elements(j) e WHERE e->>'email' = 'imp_b@authz.test' AND e->>'employee_number' IS NULL)
          AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(j) e WHERE e->>'employee_number' IN ('E-LV', 'E-NG'))
     FROM t_imp WHERE label = 'numbers')
  AND (SELECT j->>'message' = 'insufficient_privilege' FROM t_imp WHERE label = 'numbers vp_s')
  AND (SELECT j->>'message' = 'insufficient_privilege' FROM t_imp WHERE label = 'numbers mgr')
  AND (SELECT count(*) FROM access_audit_log) = (SELECT n FROM t_imp_audit1)
  AND pg_get_function_result('rpc_hr_absence_list_company(uuid, boolean)'::regprocedure) NOT LIKE '%employee_number%');
-- J-338 A: the header keeps both the file name and the SHA-256 (checked in section 16); the stage refuses a bad hash.
SELECT t_assert('J-338 A: the WORM commit header of the main file keeps file name AND SHA-256; a malformed SHA-256 was refused at stage (400)',
  (SELECT bool_and(scope->>'source_filename' = 'absences_nov.csv' AND scope->>'source_sha256' = repeat('ab', 32))
     FROM access_audit_log WHERE action = 'hr_absence_import_commit' AND scope->>'source_filename' IS NOT NULL)
  AND (SELECT j->>'message' = 'invalid_source_sha256' FROM t_imp WHERE label = 'stage bad sha'));
