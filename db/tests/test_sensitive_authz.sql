-- =============================================================================
-- CHR-ETRS MVP v1.6.21 · tests/test_sensitive_authz.sql — sensitive-RPC authorization (Karin 04.11: J-147 – J-150)
-- Run on a FRESH database after the pack:
--   psql -v ON_ERROR_STOP=1 -f ref_country_calendar.sql -f schema.sql -f rpc.sql -f tests/test_sensitive_authz.sql
--   rpc_daily_reset_spoons          → the employee herself (active) or a system process;
--   rpc_upsert_employee_value_asset → an active vp_hr or cfo of the employee's company (J-149: not the employee);
--   rpc_ledger_append               → an active cfo of the ledger's company or a system process (J-147).
-- Anyone else → 403 access_denied (no detail, no digit) and NOTHING changes (fingerprint of every touched table
-- before = after). J-148: a system process = the connection's own role only (fn_is_client_call), never a
-- parameter / header / claim. Anonymous codes unchanged. Same harness as tests/test_assign_authz.sql
-- (pgTAP-style PASS lines; pgTAP itself is not installed). No identifier is printed.
-- =============================================================================
\set QUIET on
SET client_min_messages = warning;

-- ---------- helpers ----------
-- Print one PASS line.
CREATE OR REPLACE FUNCTION t_pass(p_name text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN RAISE WARNING 'PASS %', p_name; END $$;

-- Assert a boolean.
CREATE OR REPLACE FUNCTION t_assert(p_name text, p_ok boolean) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_ok IS NOT TRUE THEN RAISE EXCEPTION 'FAIL %', p_name; END IF;
  PERFORM t_pass(p_name);
END $$;

-- Impersonate a user for auth.uid() (NULL = no user) and clear any forged claim / header.
CREATE OR REPLACE FUNCTION t_as(p_uid uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', COALESCE(p_uid::text, ''), false);
  PERFORM set_config('request.jwt.claim.role', '', false);
  PERFORM set_config('request.jwt.claim.app_role', '', false);
  PERFORM set_config('request.jwt.claims', '', false);
  PERFORM set_config('request.headers', '', false);
END $$;

-- Forge every "I am the system" signal a client could send (claims, header) — none may count (J-148).
CREATE OR REPLACE FUNCTION t_forge_system() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.role', 'service_role', false);
  PERFORM set_config('request.jwt.claim.app_role', 'cfo', false);
  PERFORM set_config('request.jwt.claims', '{"role": "service_role", "app_role": "cfo", "system": true}', false);
  PERFORM set_config('request.headers', '{"x-system": "true", "x-role": "service_role"}', false);
END $$;

-- Deterministic fixture uuid of a key.
CREATE OR REPLACE FUNCTION t_u(p_key text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT md5('sensitive-authz-' || p_key)::uuid
$$;

-- Company uuid of 'A' / 'B'.
CREATE OR REPLACE FUNCTION t_co(p_co text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT md5('sensitive-authz-company-' || p_co)::uuid
$$;

-- Create one fixture user in company p_co reporting to p_mgr.
CREATE OR REPLACE FUNCTION t_mk(p_key text, p_co text, p_app text, p_org_role text, p_mgr text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id) VALUES (t_u(p_key));
  INSERT INTO users (user_id, company_id, reports_to, email, full_name, department, app_role, org_role_code,
                     timezone, hire_date)
  VALUES (t_u(p_key), t_co(p_co), CASE WHEN p_mgr IS NOT NULL THEN t_u(p_mgr) END, p_key || '@sens.test',
          'Fixture ' || p_key, 'Team' || p_co, p_app, p_org_role, 'Asia/Jerusalem', DATE '2025-01-01');
END $$;

-- Fingerprint of every table the three RPCs could touch (superuser read). Equal before / after ⇒ nothing written.
CREATE OR REPLACE FUNCTION t_snapshot() RETURNS text LANGUAGE sql AS $$
  SELECT md5(concat_ws('|',
    (SELECT string_agg(x::text, ',' ORDER BY x::text) FROM spoon_budget x),
    (SELECT string_agg(x::text, ',' ORDER BY x::text) FROM employee_value_asset x),
    (SELECT string_agg(x::text, ',' ORDER BY x::text) FROM manager_ledger x),
    (SELECT string_agg(x::text, ',' ORDER BY x::text) FROM pseudonym_key x),
    (SELECT string_agg(x::text, ',' ORDER BY x::text) FROM early_leave_log x),
    (SELECT string_agg(x::text, ',' ORDER BY x::text) FROM access_audit_log x),
    (SELECT string_agg(x::text, ',' ORDER BY x::text) FROM notification x),
    (SELECT string_agg(x::text, ',' ORDER BY x::text) FROM task x)))
$$;

-- The error of a statement as the client-visible fields; '{"no_error": true}' when it succeeds.
CREATE OR REPLACE FUNCTION t_err_sig(p_sql text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_state text; v_msg text; v_detail text; v_hint text;
BEGIN
  EXECUTE p_sql;
  RETURN '{"no_error": true}'::jsonb;
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT, v_detail = PG_EXCEPTION_DETAIL,
                          v_hint = PG_EXCEPTION_HINT;
  RETURN jsonb_build_object('code', v_state, 'message', v_msg, 'details', v_detail, 'hint', v_hint);
END $$;

CREATE TEMP TABLE t_sig (fn text, label text, sig jsonb, unchanged boolean);
GRANT SELECT, INSERT ON t_sig TO authenticated, anon, service_role;

-- Run p_sql as user p_who (signed in, SET ROLE authenticated; p_forge = add the forged system signals), record the
-- answer and whether every table is unchanged. Superuser-owned, runs the call under the client role.
CREATE OR REPLACE FUNCTION t_try(p_fn text, p_label text, p_who text, p_sql text, p_forge boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_before text := t_snapshot(); v_sig jsonb;
BEGIN
  PERFORM t_as(CASE WHEN p_who IS NOT NULL THEN t_u(p_who) END);
  IF p_forge THEN PERFORM t_forge_system(); END IF;
  SET LOCAL ROLE authenticated;
  v_sig := t_err_sig(p_sql);
  RESET ROLE;
  PERFORM t_as(NULL);
  INSERT INTO t_sig VALUES (p_fn, p_label, v_sig, t_snapshot() = v_before);
END $$;

-- Assert: the recorded attempt was refused with p_code / HTTP 403 (Error Contract) and nothing changed.
CREATE OR REPLACE FUNCTION t_refused(p_fn text, p_label text, p_code text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
  SELECT * INTO r FROM t_sig WHERE fn = p_fn AND label = p_label;
  IF r.sig->>'code' = '42501' AND r.sig->>'message' = p_code AND r.sig->>'hint' = p_code
     AND r.sig->>'details' = format('http_hint=403;code=%s', p_code) AND r.unchanged THEN
    PERFORM t_pass(format('%s: %s → 403 %s, data before = after', p_fn, p_label, p_code));
  ELSE
    RAISE EXCEPTION 'FAIL %: % — got % (unchanged %)', p_fn, p_label, r.sig->>'message', r.unchanged;
  END IF;
END $$;

-- SQL of one call of each RPC (target user / company as fixture keys).
CREATE OR REPLACE FUNCTION t_reset_sql(p_target text) RETURNS text LANGUAGE sql AS $$
  SELECT format('SELECT rpc_daily_reset_spoons(%s)', CASE WHEN p_target IS NULL THEN 'NULL' ELSE quote_literal(t_u(p_target)) || '::uuid' END)
$$;
CREATE OR REPLACE FUNCTION t_eva_sql(p_target uuid, p_tier text DEFAULT NULL) RETURNS text LANGUAGE sql AS $$
  SELECT format('SELECT rpc_upsert_employee_value_asset(%L::uuid, 123456, NULL, NULL, %L)', p_target, p_tier)
$$;
CREATE OR REPLACE FUNCTION t_ledger_sql(p_co text, p_subject text DEFAULT NULL) RETURNS text LANGUAGE sql AS $$
  SELECT format('SELECT rpc_ledger_append(''authz_note'', 1, 2, %s, %s, NULL)',
                CASE WHEN p_subject IS NULL THEN 'NULL' ELSE quote_literal(t_u(p_subject)) || '::uuid' END,
                CASE WHEN p_co IS NULL THEN 'NULL' ELSE quote_literal(t_co(p_co)) || '::uuid' END)
$$;

GRANT EXECUTE ON FUNCTION t_pass(text), t_assert(text, boolean), t_err_sig(text), t_u(text), t_co(text)
  TO authenticated, anon, service_role;

-- ---------- fixtures ----------
-- Company A: employee emp (direct manager mgr), peer emp2, other-team manager mgr_x, vp_hr, cfo, legal_ethics,
-- an ended employee / vp_hr / cfo. Company B: employee, manager, vp_hr, cfo, legal_ethics.
INSERT INTO companies (company_id, company_name, country, week_start_dow, last_workday_dow, timezone)
VALUES (t_co('A'), 'SensCoA', 'IL', 0, 4, 'Asia/Jerusalem'), (t_co('B'), 'SensCoB', 'IL', 0, 4, 'Asia/Jerusalem');
SELECT FROM t_mk('mgr', 'A', 'manager', 'direct_manager');
SELECT FROM t_mk('mgr_x', 'A', 'manager', 'direct_manager');
SELECT FROM t_mk('emp', 'A', 'employee', 'employee', 'mgr');
SELECT FROM t_mk('emp2', 'A', 'employee', 'employee', 'mgr');
SELECT FROM t_mk('emp_ended', 'A', 'employee', 'employee', 'mgr');
SELECT FROM t_mk('vp_hr', 'A', 'vp_hr', 'vp');
SELECT FROM t_mk('cfo', 'A', 'cfo', 'vp');
SELECT FROM t_mk('legal', 'A', 'legal_ethics', 'employee');
SELECT FROM t_mk('vp_hr_ended', 'A', 'vp_hr', 'vp');
SELECT FROM t_mk('cfo_ended', 'A', 'cfo', 'vp');
SELECT FROM t_mk('emp_b', 'B', 'employee', 'employee');
SELECT FROM t_mk('mgr_b', 'B', 'manager', 'direct_manager');
SELECT FROM t_mk('vp_hr_b', 'B', 'vp_hr', 'vp');
SELECT FROM t_mk('cfo_b', 'B', 'cfo', 'vp');
SELECT FROM t_mk('legal_b', 'B', 'legal_ethics', 'employee');
UPDATE users SET employment_ended_at = clock_timestamp() - interval '1 day'
 WHERE user_id IN (t_u('emp_ended'), t_u('vp_hr_ended'), t_u('cfo_ended'));
SELECT FROM fn_ensure_local_spoon_budget(t_u('emp'));
UPDATE spoon_budget SET current_spoon_count = 5 WHERE user_id = t_u('emp');
SELECT FROM fn_ensure_local_spoon_budget(t_u('emp_ended'));
UPDATE spoon_budget SET current_spoon_count = 5 WHERE user_id = t_u('emp_ended');

-- ============ 0. J-148: how a system process is recognized ============
SELECT t_as(t_u('emp2'));
SELECT t_forge_system();
SET ROLE authenticated;
SELECT t_assert('J-148: a signed-in user with forged role / app_role / system claims and an x-system header is still a CLIENT call',
  fn_is_client_call());
RESET ROLE;
SELECT t_as(NULL);
SET ROLE anon;
SELECT t_assert('J-148: an anonymous (anon) call is a CLIENT call, not a system process', fn_is_client_call());
RESET ROLE;
SET ROLE service_role;
SELECT t_assert('J-148: a service_role connection (server key) is NOT a client call', NOT fn_is_client_call());
RESET ROLE;
SELECT t_assert('J-148: a server-side session (no SET ROLE, e.g. cron as the owner) is NOT a client call', NOT fn_is_client_call());

-- ============ 1. rpc_daily_reset_spoons: self (active) or system only ============
SELECT t_try('reset', 'user of another company', 'emp_b', t_reset_sql('emp'));
SELECT t_try('reset', 'regular employee (peer)', 'emp2', t_reset_sql('emp'));
SELECT t_try('reset', 'non-direct manager', 'mgr_x', t_reset_sql('emp'));
SELECT t_try('reset', 'direct manager', 'mgr', t_reset_sql('emp'));
SELECT t_try('reset', 'vp_hr of the same company', 'vp_hr', t_reset_sql('emp'));
SELECT t_try('reset', 'cfo of another company', 'cfo_b', t_reset_sql('emp'));
SELECT t_try('reset', 'ended employee resets herself', 'emp_ended', t_reset_sql('emp_ended'));
SELECT t_try('reset', 'peer with forged system claims and header', 'emp2', t_reset_sql('emp'), true);
SELECT t_refused('reset', label, 'access_denied') FROM t_sig WHERE fn = 'reset' ORDER BY label;
SELECT t_try('reset', 'anonymous client with a target', NULL, t_reset_sql('emp'));
SELECT t_try('reset', 'anonymous client without a target', NULL, t_reset_sql(NULL));
SELECT t_refused('reset', 'anonymous client with a target', 'consent_required');
SELECT t_refused('reset', 'anonymous client without a target', 'consent_required');
SELECT t_assert('reset: fixture — her כפיות are still 5 after all refusals',
  (SELECT current_spoon_count = 5 FROM spoon_budget WHERE user_id = t_u('emp') AND budget_date = fn_user_local_date(t_u('emp'))));
-- allowed
SELECT t_as(t_u('emp'));
SET ROLE authenticated;
SELECT t_assert('reset: the employee herself (no parameter) → 12', (SELECT current_spoon_count = 12 FROM rpc_daily_reset_spoons()));
SELECT t_assert('reset: the employee herself (her own id) → 12',
  (SELECT current_spoon_count = 12 FROM rpc_daily_reset_spoons(t_u('emp'))));
RESET ROLE;
SELECT t_as(NULL);
UPDATE spoon_budget SET current_spoon_count = 5 WHERE user_id = t_u('emp');
SET ROLE service_role;
SELECT t_assert('reset: system process (service_role) → 12', (SELECT current_spoon_count = 12 FROM rpc_daily_reset_spoons(t_u('emp'))));
RESET ROLE;
UPDATE spoon_budget SET current_spoon_count = 5 WHERE user_id = t_u('emp');
SELECT t_assert('reset: system process (server-side session) → 12', (SELECT current_spoon_count = 12 FROM rpc_daily_reset_spoons(t_u('emp'))));
SELECT t_assert('reset: rpc_daily_reset_spoons is granted to service_role',
  has_function_privilege('service_role', 'rpc_daily_reset_spoons(uuid)', 'EXECUTE'));

-- ============ 2. rpc_upsert_employee_value_asset: vp_hr / cfo of the same company only ============
SELECT t_try('eva', 'vp_hr of another company', 'vp_hr_b', t_eva_sql(t_u('emp')));
SELECT t_try('eva', 'cfo of another company', 'cfo_b', t_eva_sql(t_u('emp')));
SELECT t_try('eva', 'the employee herself (J-149)', 'emp', t_eva_sql(t_u('emp')));
SELECT t_try('eva', 'regular employee (peer)', 'emp2', t_eva_sql(t_u('emp')));
SELECT t_try('eva', 'non-direct manager', 'mgr_x', t_eva_sql(t_u('emp')));
SELECT t_try('eva', 'direct manager without vp_hr / cfo role', 'mgr', t_eva_sql(t_u('emp')));
SELECT t_try('eva', 'legal_ethics of the same company', 'legal', t_eva_sql(t_u('emp')));
SELECT t_try('eva', 'vp_hr whose employment ended', 'vp_hr_ended', t_eva_sql(t_u('emp')));
SELECT t_try('eva', 'cfo whose employment ended', 'cfo_ended', t_eva_sql(t_u('emp')));
SELECT t_try('eva', 'vp_hr on an unknown id (no existence hint)', 'vp_hr', t_eva_sql('00000000-0000-0000-0000-00000000dead'));
SELECT t_try('eva', 'employee with forged system / cfo claims', 'emp', t_eva_sql(t_u('emp')), true);
SELECT t_refused('eva', label, 'access_denied') FROM t_sig WHERE fn = 'eva' ORDER BY label;
SELECT t_try('eva', 'anonymous client', NULL, t_eva_sql(t_u('emp')));
SELECT t_refused('eva', 'anonymous client', 'anti_get_blocked');
-- allowed
SELECT t_as(t_u('vp_hr'));
SET ROLE authenticated;
SELECT t_assert('eva: vp_hr of the same company writes salary data', (SELECT annual_salary = 123456 FROM rpc_upsert_employee_value_asset(t_u('emp'), 123456)));
SELECT t_assert('eva: vp_hr of the same company may override the turnover tier (unchanged)',
  (SELECT turnover_tier = 'mid' AND turnover_tier_override FROM rpc_upsert_employee_value_asset(t_u('emp'), NULL, NULL, NULL, 'mid')));
RESET ROLE;
SELECT t_as(t_u('cfo'));
SET ROLE authenticated;
SELECT t_assert('eva: cfo of the same company writes salary data', (SELECT annual_salary = 234567 FROM rpc_upsert_employee_value_asset(t_u('emp2'), 234567)));
RESET ROLE;
SELECT t_try('eva', 'cfo sets a turnover tier (vp_hr only, unchanged rule)', 'cfo', t_eva_sql(t_u('emp2'), 'senior'));
SELECT t_refused('eva', 'cfo sets a turnover tier (vp_hr only, unchanged rule)', 'anti_get_blocked');

-- ============ 3. rpc_ledger_append: cfo of the same company or system only ============
SELECT t_try('ledger', 'manager of another company', 'mgr_b', t_ledger_sql('A'));
SELECT t_try('ledger', 'vp_hr of another company', 'vp_hr_b', t_ledger_sql('A'));
SELECT t_try('ledger', 'legal_ethics of another company', 'legal_b', t_ledger_sql('A'));
SELECT t_try('ledger', 'cfo of another company', 'cfo_b', t_ledger_sql('A'));
SELECT t_try('ledger', 'regular employee', 'emp', t_ledger_sql('A'));
SELECT t_try('ledger', 'non-direct manager', 'mgr_x', t_ledger_sql('A'));
SELECT t_try('ledger', 'direct manager', 'mgr', t_ledger_sql('A', 'emp'));
SELECT t_try('ledger', 'vp_hr of the same company', 'vp_hr', t_ledger_sql('A'));
SELECT t_try('ledger', 'legal_ethics of the same company', 'legal', t_ledger_sql('A'));
SELECT t_try('ledger', 'legal_ethics, own company by default', 'legal', t_ledger_sql(NULL));
SELECT t_try('ledger', 'cfo whose employment ended', 'cfo_ended', t_ledger_sql('A'));
SELECT t_try('ledger', 'cfo of the company with a subject of another company', 'cfo', t_ledger_sql('A', 'emp_b'));
SELECT t_try('ledger', 'employee with forged system / cfo claims', 'emp', t_ledger_sql('A'), true);
SELECT t_refused('ledger', label, 'access_denied') FROM t_sig WHERE fn = 'ledger' ORDER BY label;
SELECT t_try('ledger', 'anonymous client', NULL, t_ledger_sql('A'));
SELECT t_refused('ledger', 'anonymous client', 'anti_get_blocked');
-- allowed
CREATE TEMP TABLE t_ledger_before AS SELECT count(*) AS n FROM manager_ledger WHERE org_id = t_co('A');
SELECT t_as(t_u('cfo'));
SET ROLE authenticated;
SELECT t_assert('ledger: cfo of the same company appends (subject of the same company)',
  (SELECT manager_id = t_u('cfo') AND org_id = t_co('A') FROM rpc_ledger_append('authz_note', 1, 2, t_u('emp'), t_co('A'))));
SELECT t_assert('ledger: cfo of the same company appends to her own company by default',
  (SELECT org_id = t_co('A') FROM rpc_ledger_append('authz_note', 3, 4)));
RESET ROLE;
SELECT t_as(NULL);
-- J-163 (conflict, for Karin): a system process passes the authorization check, but the existing schema rule
-- chk_ledger_manager_or_genesis (every non-GENESIS row names its actor in manager_id) refuses a row without one.
SET ROLE service_role;
SELECT t_assert('ledger: system process (service_role) passes authorization (not access_denied); the existing schema rule then refuses a row without an actor (23514, J-163)',
  (SELECT sig->>'code' = '23514' FROM (SELECT t_err_sig(format('SELECT rpc_ledger_append(%L, 5, 6, NULL, %L::uuid)', 'system_note', t_co('A'))) sig) x));
RESET ROLE;
SELECT t_assert('ledger: system process (server-side session) passes authorization; same schema rule (23514, J-163)',
  (SELECT sig->>'code' = '23514' FROM (SELECT t_err_sig(format('SELECT rpc_ledger_append(%L, 7, 8, NULL, %L::uuid)', 'system_note', t_co('A'))) sig) x));
SELECT t_assert('ledger: a system process must name the company (J-162) → 403 access_denied',
  (SELECT sig->>'message' = 'access_denied' FROM (SELECT t_err_sig('SELECT rpc_ledger_append(''system_note'', 1, 1)') sig) x));
SELECT t_assert('ledger: exactly the 2 allowed cfo rows were added; the chain of company A verifies; company B untouched',
  (SELECT count(*) FROM manager_ledger WHERE org_id = t_co('A')) = (SELECT n FROM t_ledger_before) + 2
  AND fn_ledger_verify_chain(t_co('A'))
  AND (SELECT count(*) = 1 FROM manager_ledger WHERE org_id = t_co('B')));
SELECT t_assert('ledger: rpc_ledger_append is granted to service_role', has_function_privilege('service_role', 'rpc_ledger_append(varchar, numeric, numeric, uuid, uuid, varchar)', 'EXECUTE'));

-- ============ 4. the 403 carries no information ============
SELECT t_assert('every access_denied answer is the same (code, message, details, hint) across the 3 functions',
  (SELECT count(DISTINCT sig) = 1 FROM t_sig WHERE sig->>'message' = 'access_denied'));
SELECT t_assert('no refusal message / hint carries a digit or an id',
  (SELECT bool_and((sig->>'message') || (sig->>'hint') !~ '[0-9]') FROM t_sig WHERE NOT sig ? 'no_error'));
SELECT t_assert('all 37 recorded attempts (10 reset, 13 value asset, 14 ledger) were refused (none succeeded)',
  (SELECT count(*) = 37 AND bool_and(NOT sig ? 'no_error') FROM t_sig));

-- ============ 5. structure ============
SELECT t_assert('helpers are not callable by clients (PUBLIC / anon / authenticated)',
  NOT has_function_privilege('authenticated', 'fn_assert_may_reset_spoons(uuid)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'fn_assert_may_write_value_asset(uuid)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'fn_assert_may_append_ledger(uuid, uuid)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'fn_caller_active_role_in(uuid, text[])', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'fn_user_company(uuid)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'fn_is_system_call()', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'fn_assert_may_append_ledger(uuid, uuid)', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'fn_assert_may_reset_spoons(uuid)', 'EXECUTE'));
SELECT t_assert('the authorization check comes before any business read / write in each function body',
  (SELECT bool_and(a > 0 AND (b = 0 OR a < b))
     FROM (SELECT strpos(d, 'PERFORM fn_assert_may_reset_spoons') a, strpos(d, 'fn_user_local_date') b
             FROM (SELECT pg_get_functiondef('rpc_daily_reset_spoons(uuid)'::regprocedure) d) x
           UNION ALL
           SELECT strpos(d, 'PERFORM fn_assert_may_write_value_asset'), strpos(d, 'FROM users WHERE')
             FROM (SELECT pg_get_functiondef('rpc_upsert_employee_value_asset(uuid, numeric, numeric, numeric, text)'::regprocedure) d) x
           UNION ALL
           SELECT strpos(d, 'PERFORM fn_assert_may_append_ledger'), strpos(d, 'FROM team_aggregate')
             FROM (SELECT pg_get_functiondef('rpc_ledger_append(varchar, numeric, numeric, uuid, uuid, varchar)'::regprocedure) d) x) y));
