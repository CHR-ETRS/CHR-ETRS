-- =============================================================================
-- CHR-ETRS MVP v1.6.19 · tests/test_agents_v1_6_16.sql — agents (agents-bot-instructions-v3) on PostgreSQL 17
-- Version: 1.6.20-mvp (2026-10-31) — supersedes the 1.6.19-mvp, 1.6.18-mvp, 1.6.17-mvp and 1.6.16-mvp files of the same name (filename kept so the Drive
-- id history stays in one place). Run on a FRESH database after the pack:
--   psql -v ON_ERROR_STOP=1 -f ref_country_calendar.sql -f schema.sql -f rpc.sql -f tests/test_agents_v1_6_16.sql
-- Covers: the 18 server tests of v3 §6.3 (tagged "v3-T<n>"), A1 (conversion blocked), A2 (anonymous EverStore
-- budget summary), Karin 30.10 closed values (participation Golden Spoons 10 / 2; 5th signal 1.5× / 2 events /
-- 10 employees), the settings API, two company timezones and the privacy sweep (no person_id / user_id /
-- pseudonym in any agent output). Every check prints "PASS <name>"; any failure aborts.
-- v1.6.17 (Karin 31.10): Cantril monthly → 10; TPS-12 / IHS → 10 (adjustable setting); J-15 time benefits
-- refused after exit (section 4b); A-8 reversed offboarding returns the memo-line debt to the team (section 9b).
-- v1.6.18 (Karin 31.10): A-14 questionnaire amounts per company (section 3b), A-13 time benefits scheduled after
-- exit are cancelled + refunded (section 4c), A-12 reversal returns transfer − attributed remediations (section 9c).
-- v1.6.19 (Karin 31.10): A-3 liability estimate, liability_method locked; reversal output status only; remediation
-- without transfer selection (400 / one 422); aggregate leaver list; computed verification levels; A4 recommendation.
-- The new v1.6.19 board tests are in tests/test_board_v1_6_19.sql.
-- Fixed dates (2026) keep the expectations independent of the run date.
-- =============================================================================
\set QUIET on
SET client_min_messages = warning;

-- ---------- helpers (same contract as tests/test_v1_5.sql) ----------
-- Print one PASS line.
CREATE OR REPLACE FUNCTION t_pass(p_name text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN RAISE WARNING 'PASS %', p_name; END $$;

-- Expect p_sql to fail with message = p_code or SQLSTATE = p_code.
CREATE OR REPLACE FUNCTION t_expect_err(p_name text, p_sql text, p_code text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RAISE EXCEPTION 'FAIL % — no error (expected %)', p_name, p_code;
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE 'FAIL %' THEN RAISE; END IF;
  IF SQLERRM = p_code OR SQLSTATE = p_code THEN PERFORM t_pass(p_name);
  ELSE RAISE EXCEPTION 'FAIL % — got [%] %, expected %', p_name, SQLSTATE, SQLERRM, p_code; END IF;
END $$;

-- Expect p_code with the Error Contract DETAIL 'http_hint=<p_http>;code=<p_code>'.
CREATE OR REPLACE FUNCTION t_expect_http(p_name text, p_sql text, p_code text, p_http int) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_detail text; v_state text;
BEGIN
  EXECUTE p_sql;
  RAISE EXCEPTION 'FAIL % — no error (expected % %)', p_name, p_http, p_code;
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE 'FAIL %' THEN RAISE; END IF;
  GET STACKED DIAGNOSTICS v_detail = PG_EXCEPTION_DETAIL, v_state = RETURNED_SQLSTATE;
  IF SQLERRM = p_code AND v_detail = format('http_hint=%s;code=%s', p_http, p_code) THEN PERFORM t_pass(p_name);
  ELSE RAISE EXCEPTION 'FAIL % — got [%] % / %, expected % %', p_name, v_state, SQLERRM, v_detail, p_http, p_code; END IF;
END $$;

-- Assert a boolean.
CREATE OR REPLACE FUNCTION t_assert(p_name text, p_ok boolean) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_ok IS NOT TRUE THEN RAISE EXCEPTION 'FAIL %', p_name; END IF;
  PERFORM t_pass(p_name);
END $$;

-- Impersonate a user for auth.uid().
CREATE OR REPLACE FUNCTION t_as(p_uid uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', p_uid::text, false);
$$;

-- Deterministic fixture uuid of a key.
CREATE OR REPLACE FUNCTION t_u(p_key text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT md5('agents-v1616-' || p_key)::uuid
$$;

-- Create one fixture user (auth + users); returns its uuid.
CREATE OR REPLACE FUNCTION t_mk(p_company uuid, p_key text, p_dept text, p_role text DEFAULT 'employee',
                                p_org_role text DEFAULT 'employee', p_mgr text DEFAULT NULL) RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id) VALUES (t_u(p_key));
  INSERT INTO users (user_id, company_id, reports_to, email, full_name, department, app_role, org_role_code, timezone, hire_date)
  VALUES (t_u(p_key), p_company, CASE WHEN p_mgr IS NOT NULL THEN t_u(p_mgr) END, p_key || '@agents.test',
          'Agent Person ' || p_key, p_dept, p_role, p_org_role, 'Asia/Jerusalem', DATE '2025-01-01');
  RETURN t_u(p_key);
END $$;

-- Insert an EverStore purchase directly (fixture history with a chosen instant and price).
CREATE OR REPLACE FUNCTION t_buy(p_key text, p_item varchar, p_at timestamptz, p_price numeric DEFAULT NULL) RETURNS void LANGUAGE sql AS $$
  INSERT INTO shop_purchase (user_id, item_id, category, price_golden_spoons, cosmetic_only, idempotency_key, purchased_at)
  SELECT t_u(p_key), c.item_id, c.category, COALESCE(p_price, c.price_golden_spoons), c.cosmetic_only,
         'fx-' || p_key || '-' || p_item || '-' || extract(epoch FROM p_at)::bigint, p_at
    FROM shop_item_catalog c WHERE c.item_id = p_item
$$;

-- Insert a PCQ-12 submission of a past month directly (fixture history).
CREATE OR REPLACE FUNCTION t_pcq(p_key text, p_day date, p_score numeric) RETURNS void LANGUAGE sql AS $$
  INSERT INTO questionnaire_submission (user_id, questionnaire_code, period_key, local_date, answers, score, reward_golden_spoons)
  VALUES (t_u(p_key), 'PCQ-12', to_char(p_day, 'YYYY-MM'), p_day, '{4,4,4,4,4,4,4,4,4,4,4,4}', p_score, 10)
$$;

-- Every agent output captured during the run (privacy sweep at the end).
CREATE TABLE t_outputs (label text, j jsonb);
GRANT SELECT, INSERT ON t_outputs TO authenticated;

-- True when a jsonb output holds no employee identifier: no id-like key and no user's uuid / pseudonym / name / email.
CREATE OR REPLACE FUNCTION t_ids_free(p_j jsonb) RETURNS boolean LANGUAGE sql SECURITY DEFINER AS $$
  SELECT p_j IS NOT NULL
     AND p_j::text !~* '"(person_id|user_id|employee_id|pseudonym|display_pseudonym|email|full_name|approved_by|buyer)"\s*:'
     AND NOT EXISTS (SELECT 1 FROM users u
                      WHERE strpos(p_j::text, u.user_id::text) > 0
                         OR (u.display_pseudonym IS NOT NULL AND strpos(p_j::text, u.display_pseudonym) > 0)
                         OR strpos(p_j::text, u.full_name) > 0 OR strpos(p_j::text, u.email) > 0)
$$;
GRANT EXECUTE ON FUNCTION t_pass(text), t_expect_err(text, text, text), t_expect_http(text, text, text, int),
                          t_assert(text, boolean), t_as(uuid), t_u(text), t_ids_free(jsonb) TO authenticated;

-- ---------- fixtures ----------
-- Company A (Asia/Jerusalem): Mgmt (vp_hr, cfo, manager, board chair), teams BIG 12 (reports to the manager),
-- NINE 9, SEVEN 7, THREE 3, REST 20 (+ one leaver). Company B (Asia/Jerusalem) and C (Europe/London with the
-- agent setting company_timezone = America/New_York) for the budget, liability and timezone tests.
INSERT INTO companies (company_id, company_name, country, week_start_dow, last_workday_dow, timezone) VALUES
  (t_u('cA'), 'Agents A', 'IL', 0, 4, 'Asia/Jerusalem'),
  (t_u('cB'), 'Agents B', 'IL', 0, 4, 'Asia/Jerusalem'),
  (t_u('cC'), 'Agents C', 'GB', 1, 5, 'Europe/London');

DO $$
DECLARE i int;
BEGIN
  PERFORM t_mk(t_u('cA'), 'hrA', 'Mgmt', 'vp_hr', 'vp');
  PERFORM t_mk(t_u('cA'), 'cfoA', 'Mgmt', 'cfo', 'vp');
  PERFORM t_mk(t_u('cA'), 'mgrA', 'Mgmt', 'manager', 'direct_manager');
  PERFORM t_mk(t_u('cA'), 'chairA', 'Board', 'board_chair', 'board_chair');
  FOR i IN 1..12 LOOP PERFORM t_mk(t_u('cA'), 'big' || i, 'BIG', 'employee', 'employee', 'mgrA'); END LOOP;
  FOR i IN 1..9  LOOP PERFORM t_mk(t_u('cA'), 'nine' || i, 'NINE'); END LOOP;
  FOR i IN 1..7  LOOP PERFORM t_mk(t_u('cA'), 'seven' || i, 'SEVEN'); END LOOP;
  FOR i IN 1..3  LOOP PERFORM t_mk(t_u('cA'), 'three' || i, 'THREE'); END LOOP;
  FOR i IN 1..20 LOOP PERFORM t_mk(t_u('cA'), 'rest' || i, 'REST'); END LOOP;
  PERFORM t_mk(t_u('cA'), 'leaverA', 'REST');
  PERFORM t_mk(t_u('cB'), 'cfoB', 'Mgmt', 'cfo', 'vp');
  PERFORM t_mk(t_u('cB'), 'mgrB', 'Mgmt', 'manager', 'direct_manager');
  FOR i IN 1..3 LOOP PERFORM t_mk(t_u('cB'), 'empB' || i, 'OPS', 'employee', 'employee', 'mgrB'); END LOOP;
  PERFORM t_mk(t_u('cB'), 'leaverB', 'OPS');
  PERFORM t_mk(t_u('cB'), 'depB', 'OPS');
  PERFORM t_mk(t_u('cB'), 'depOld', 'OPS');
  PERFORM t_mk(t_u('cC'), 'cfoC', 'Mgmt', 'cfo', 'vp');
  PERFORM t_mk(t_u('cC'), 'empC1', 'OPS');
END $$;

-- v1.6.17: company D (Asia/Jerusalem) for the questionnaire amounts, J-15 and A-8 — team TEAMD, two leavers.
INSERT INTO companies (company_id, company_name, country, week_start_dow, last_workday_dow, timezone) VALUES
  (t_u('cD'), 'Agents D', 'IL', 0, 4, 'Asia/Jerusalem');
DO $$
DECLARE i int;
BEGIN
  PERFORM t_mk(t_u('cD'), 'hrD', 'Mgmt', 'vp_hr', 'vp');
  FOR i IN 1..3 LOOP PERFORM t_mk(t_u('cD'), 'd' || i, 'TEAMD'); END LOOP;
  PERFORM t_mk(t_u('cD'), 'retD', 'TEAMD');
  PERFORM t_mk(t_u('cD'), 'otherD', 'TEAMD');
  -- v1.6.18 A-13: direct manager mgrD and two employees of TEAMT with time benefits
  PERFORM t_mk(t_u('cD'), 'mgrD', 'Mgmt', 'manager', 'direct_manager');
  PERFORM t_mk(t_u('cD'), 'tb1', 'TEAMT', 'employee', 'employee', 'mgrD');
  PERFORM t_mk(t_u('cD'), 'tb2', 'TEAMT', 'employee', 'employee', 'mgrD');
END $$;

-- v1.6.18: company E (A-12 remediation attribution: TEAME with two leavers, TEAMX with one) and company F
-- (A-14 questionnaire amounts: vp_hr, cfo, employees of two teams and two org roles).
INSERT INTO companies (company_id, company_name, country, week_start_dow, last_workday_dow, timezone) VALUES
  (t_u('cE'), 'Agents E', 'IL', 0, 4, 'Asia/Jerusalem'),
  (t_u('cF'), 'Agents F', 'IL', 0, 4, 'Asia/Jerusalem');
DO $$
BEGIN
  PERFORM t_mk(t_u('cE'), 'hrE', 'Mgmt', 'vp_hr', 'vp');
  PERFORM t_mk(t_u('cE'), 'remE', 'TEAME');
  PERFORM t_mk(t_u('cE'), 'peerE', 'TEAME');
  PERFORM t_mk(t_u('cE'), 'xE', 'TEAMX');
  PERFORM t_mk(t_u('cF'), 'hrF', 'Mgmt', 'vp_hr', 'vp');
  PERFORM t_mk(t_u('cF'), 'cfoF', 'Mgmt', 'cfo', 'vp');
  PERFORM t_mk(t_u('cF'), 'f1', 'TEAMF1');
  PERFORM t_mk(t_u('cF'), 'f2', 'TEAMF2', 'employee', 'project_manager');
END $$;

-- EverStore catalog items of the 8 categories (the pack seeds cosmetics only; the CHRO adds the rest).
INSERT INTO shop_item_catalog (item_id, display_name, name_he, category, provider, tier, price_coins, cosmetic_only) VALUES
  ('charity_trees', 'Plant trees', 'נטיעת עצים', 'donation', 'GreenEarth', 'basic', 5.0, false),
  ('concert_pass', 'Concert pass', 'כרטיס להופעה', 'experience', 'CultureHub', 'premium', 60.0, false),
  ('coffee_card', 'Coffee card', 'כרטיס קפה', 'gift_card', 'CafeNet', 'custom', 7.5, false),
  ('spa_massage', 'Spa massage', 'עיסוי', 'health_wellbeing', 'WellSpa Ltd', 'premium', 45.0, false),
  ('course_book', 'Course book', 'ספר קורס', 'learning', 'AcadPress', 'custom', 15.5, false),
  ('voucher_refresh_day', 'Refresh day', 'יום התרעננות', 'time_benefit', 'Internal HR', 'premium', 35.0, false)
ON CONFLICT (item_id) DO NOTHING;

-- ============ 1. agent_settings (v3 §6.1, Karin 30.10) ============
SELECT t_assert('settings: Karin 30.10 participation values stored as agent_settings (monthly incl. PCQ-12 = 10, weekly / short = 2); v1.6.18 A-14: adjustable (not locked)',
  (SELECT bool_and(NOT is_locked AND value_status = 'set') AND sum(value_numeric) FILTER (WHERE setting_key = 'golden_spoons_per_questionnaire') = 10
          AND sum(value_numeric) FILTER (WHERE setting_key = 'golden_spoons_per_short_questionnaire') = 2
     FROM agent_settings WHERE company_id IS NULL
      AND setting_key IN ('golden_spoons_per_questionnaire', 'golden_spoons_per_short_questionnaire')));
SELECT t_assert('settings: Karin 30.10 5th-signal parameters stored (multiplier 1.5, min events 2, min team size 10, window 3 months)',
  (SELECT string_agg(setting_key || '=' || trim_scale(value_numeric)::text, ',' ORDER BY setting_key) FROM agent_settings
    WHERE company_id IS NULL AND setting_key LIKE 'movement\_%')
  = 'movement_min_events=2,movement_min_team_size=10,movement_rate_multiplier=1.5,movement_window_months=3');
SELECT t_assert('settings: the 15% placeholder movement_rise_pct and the two margin_budget_points keys are gone',
  NOT EXISTS (SELECT 1 FROM agent_settings WHERE setting_key IN ('movement_rise_pct', 'margin_budget_points_pcq', 'margin_budget_points_ihs')));
SELECT t_assert('settings: one range coefficient 12.5 (v3 §4.3)',
  (SELECT value_numeric = 12.5 FROM agent_settings WHERE company_id IS NULL AND setting_key = 'score_range_coefficient'));
SELECT t_assert('settings: open values stay "לא הוגדר" (company_timezone, daily_summary_time, spoon_cost_ils [deprecated v1.6.19], turnover baselines, check-in Golden Spoons)',
  (SELECT count(*) = 7 AND bool_and(value_numeric IS NULL AND value_text IS NULL) FROM agent_settings
    WHERE company_id IS NULL AND value_status = 'not_defined'
      AND setting_key IN ('company_timezone', 'daily_summary_time', 'spoon_cost_ils',
                          'turnover_baseline_junior', 'turnover_baseline_mid', 'turnover_baseline_senior',
                          'golden_spoons_per_checkin')));
SELECT t_assert('v1.6.17 A-5: TPS-12 / IHS participation = agent_settings golden_spoons_per_quarterly_questionnaire 10, set and adjustable (not locked)',
  (SELECT value_numeric = 10 AND value_status = 'set' AND NOT is_locked FROM agent_settings
    WHERE company_id IS NULL AND setting_key = 'golden_spoons_per_quarterly_questionnaire'));
SELECT t_assert('v1.6.17 J-3: Cantril is keyed to the monthly setting (10), TPS-12 / IHS to the quarterly setting',
  (SELECT string_agg(code || '=' || reward_setting_key, ',' ORDER BY code) FROM questionnaire_definition WHERE is_locked)
  = 'Cantril=golden_spoons_per_questionnaire,IHS=golden_spoons_per_quarterly_questionnaire,PCQ-12=golden_spoons_per_questionnaire,TPS-12=golden_spoons_per_quarterly_questionnaire');
SELECT t_assert('settings: agent_settings closed to clients (RLS forced, no grant)',
  NOT has_table_privilege('authenticated', 'agent_settings', 'SELECT')
  AND (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid = 'agent_settings'::regclass));
SELECT t_as(t_u('cfoA'));
SET ROLE authenticated;
INSERT INTO t_outputs SELECT 'settings', jsonb_agg(to_jsonb(s)) FROM rpc_get_agent_settings(t_u('cA')) s;
SELECT t_assert('settings: cfo reads all keys; not-defined keys display "לא הוגדר"',
  (SELECT count(*) >= 29 AND bool_and(display_he = 'לא הוגדר') FILTER (WHERE value_status = 'not_defined')
     FROM rpc_get_agent_settings(t_u('cA'))));
SELECT t_expect_http('v1.6.18 A-14: cfo may not change the monthly questionnaire amount → 403 insufficient_privilege',
  $$SELECT * FROM rpc_put_agent_setting(t_u('cA'), 'golden_spoons_per_questionnaire', 12)$$, 'insufficient_privilege', 403);
SELECT t_expect_http('settings: locked key movement_min_team_size → 403 setting_locked',
  $$SELECT * FROM rpc_put_agent_setting(t_u('cA'), 'movement_min_team_size', 5)$$, 'setting_locked', 403);
SELECT t_expect_http('settings: unknown key → 400', $$SELECT * FROM rpc_put_agent_setting(t_u('cA'), 'nope', 1)$$, 'unknown_setting', 400);
SELECT t_expect_http('settings: bad time → 400', $$SELECT * FROM rpc_put_agent_setting(t_u('cA'), 'daily_summary_time', NULL, '25:00')$$, 'invalid_setting_value', 400);
SELECT t_expect_http('settings: bad timezone → 400', $$SELECT * FROM rpc_put_agent_setting(t_u('cA'), 'company_timezone', NULL, 'Mars/Base')$$, 'invalid_setting_value', 400);
SELECT t_expect_http('v1.6.19 A-3: liability_method is locked to avg_redeemed → 403 setting_locked', $$SELECT * FROM rpc_put_agent_setting(t_u('cA'), 'liability_method', NULL, 'guess')$$, 'setting_locked', 403);
SELECT t_expect_http('v1.6.19 A-3: spoon_cost_ils is deprecated and locked → 403 setting_locked', $$SELECT * FROM rpc_put_agent_setting(t_u('cA'), 'spoon_cost_ils', 2.5)$$, 'setting_locked', 403);
SELECT t_expect_http('v1.6.18 A-14: cfo''s permission on the quarterly amount is removed → 403 insufficient_privilege',
  $$SELECT * FROM rpc_put_agent_setting(t_u('cA'), 'golden_spoons_per_quarterly_questionnaire', 12)$$, 'insufficient_privilege', 403);
SELECT t_expect_http('v1.6.18 A-14: …and on the short amount, including a reset → 403',
  $$SELECT * FROM rpc_put_agent_setting(t_u('cA'), 'golden_spoons_per_short_questionnaire')$$, 'insufficient_privilege', 403);
SELECT t_assert('settings: cfo sets a company override (rise_pct 20) and resets it to the default',
  (SELECT value_numeric = 20 AND scope = 'company' FROM rpc_put_agent_setting(t_u('cA'), 'rise_pct', 20))
  AND (SELECT value_numeric = 15 AND scope = 'default' FROM rpc_put_agent_setting(t_u('cA'), 'rise_pct')));
RESET ROLE;
SELECT t_as(t_u('big1'));
SET ROLE authenticated;
SELECT t_expect_http('settings: employee → 403 insufficient_privilege', $$SELECT * FROM rpc_get_agent_settings(t_u('cA'))$$, 'insufficient_privilege', 403);
RESET ROLE;
SELECT t_as(t_u('cfoB'));
SET ROLE authenticated;
SELECT t_expect_http('settings: cfo of another company → 403', $$SELECT * FROM rpc_get_agent_settings(t_u('cA'))$$, 'insufficient_privilege', 403);
RESET ROLE;

-- ============ 2. A1 · conversion blocked in v1 ============
INSERT INTO avatar_state (user_id, golden_spoons) VALUES (t_u('empB1'), 20), (t_u('empB2'), 30), (t_u('leaverB'), 40),
                                                         (t_u('depB'), 30), (t_u('depOld'), 30);
SELECT t_as(t_u('empB1'));
SET ROLE authenticated;
SELECT t_expect_http('A1: rpc_convert_golden_to_chr → 422 chr_coins_deferred_to_v2', $$SELECT rpc_convert_golden_to_chr(1, 'a1')$$, 'chr_coins_deferred_to_v2', 422);
SELECT t_assert('A1: balance unchanged (20 golden, 0 CHR)', (SELECT golden_spoons = 20 AND chr_coins = 0 FROM avatar_state));
RESET ROLE;
SELECT t_assert('A1: no golden_chr_conversion row', NOT EXISTS (SELECT 1 FROM golden_chr_conversion));
SELECT t_assert('A1: the 422 sentence is the HINT ("CHR Coins shelf is deferred to v2; Golden Spoons conversion is disabled in v1")',
  position('CHR Coins shelf is deferred to v2; Golden Spoons conversion is disabled in v1' IN pg_get_functiondef('rpc_convert_golden_to_chr(numeric, varchar)'::regprocedure)) > 0);

-- ============ 3. v3-T12 · Golden Spoons by participation only ============
SELECT t_as(t_u('empB1'));
SET ROLE authenticated;
SELECT t_assert('v3-T12: PCQ-12 lowest answers → 10 Golden Spoons', (SELECT reward_golden_spoons = 10 FROM rpc_submit_questionnaire('PCQ-12', '{1,1,1,1,1,1,1,1,1,1,1,1}')));
SELECT t_assert('v3-T12 / v1.6.17 J-3: Cantril (monthly) answer 0 → 10 Golden Spoons', (SELECT reward_golden_spoons = 10 FROM rpc_submit_questionnaire('Cantril', '{0}')));
RESET ROLE;
SELECT t_as(t_u('empB2'));
SET ROLE authenticated;
SELECT t_assert('v3-T12: PCQ-12 highest answers → the same 10', (SELECT reward_golden_spoons = 10 FROM rpc_submit_questionnaire('PCQ-12', '{6,6,6,6,6,6,6,6,6,6,6,6}')));
SELECT t_assert('v3-T12 / v1.6.17 J-3: Cantril answer 10 → the same 10', (SELECT reward_golden_spoons = 10 FROM rpc_submit_questionnaire('Cantril', '{10}')));
RESET ROLE;
SELECT t_assert('v3-T12: different answers, different scores, same reward (2 PCQ-12 + 2 Cantril submissions)',
  (SELECT count(DISTINCT pcq12_score) = 2 AND count(DISTINCT reward_golden_spoons) = 1
     FROM questionnaire_submission WHERE questionnaire_code = 'PCQ-12' AND user_id IN (t_u('empB1'), t_u('empB2')))
  AND (SELECT count(DISTINCT answers) = 2 AND count(DISTINCT reward_golden_spoons) = 1
     FROM questionnaire_submission WHERE questionnaire_code = 'Cantril' AND user_id IN (t_u('empB1'), t_u('empB2'))));
SELECT t_assert('v3-T12: no RPC computes Golden Spoons from a score (fn_reward_score_div10 gone; fn_questionnaire_reward reads agent_settings, never a score)',
  to_regprocedure('fn_reward_score_div10(numeric)') IS NULL
  AND pg_get_functiondef('fn_questionnaire_reward(questionnaire_definition, uuid)'::regprocedure) !~* 'score'
  AND pg_get_functiondef('fn_questionnaire_reward(questionnaire_definition, uuid)'::regprocedure) ~ 'fn_agent_setting_num'
  AND NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                   WHERE n.nspname = 'public' AND p.prosrc ~* 'reward[a-z_]*\s*:?=\s*[a-z_.]*score'));
SELECT t_as(t_u('d1'));
SET ROLE authenticated;
SELECT t_assert('v1.6.17 A-5: TPS-12 lowest answers → 10 Golden Spoons (participation, reward_status set)',
  (SELECT reward_golden_spoons = 10 AND reward_status = 'set' FROM rpc_submit_questionnaire('TPS-12', '{1,1,1,1,1,1,1,1,1,1,1,1}')));
SELECT t_assert('v1.6.17 A-5: IHS lowest answers → 10 Golden Spoons', (SELECT reward_golden_spoons = 10 FROM rpc_submit_questionnaire('IHS', '{1,1,1,1,1,1,1,1,1}')));
RESET ROLE;
SELECT t_as(t_u('d2'));
SET ROLE authenticated;
SELECT t_assert('v1.6.17 A-5: TPS-12 highest answers → the same 10', (SELECT reward_golden_spoons = 10 FROM rpc_submit_questionnaire('TPS-12', '{5,5,5,5,5,5,5,5,5,5,5,5}')));
SELECT t_assert('v1.6.17 A-5: IHS highest answers → the same 10', (SELECT reward_golden_spoons = 10 FROM rpc_submit_questionnaire('IHS', '{5,5,5,5,5,5,5,5,5}')));
SELECT t_assert('v1.6.17 A-5: …credited to the wallet (0 + 10 + 10 = 20)', (SELECT golden_spoons = 20 FROM avatar_state));
RESET ROLE;
-- The amount is read from the setting at submit time, never a constant: a company override changes it.
INSERT INTO agent_settings (company_id, setting_key, value_kind, value_numeric, value_status, source_note)
VALUES (t_u('cD'), 'golden_spoons_per_quarterly_questionnaire', 'numeric', 7, 'set', 'test override');
SELECT t_as(t_u('d3'));
SET ROLE authenticated;
SELECT t_assert('v1.6.17 A-5: a company override of the quarterly setting (7) is what TPS-12 pays — no code constant',
  (SELECT reward_golden_spoons = 7 FROM rpc_submit_questionnaire('TPS-12', '{3,3,3,3,3,3,3,3,3,3,3,3}')));
RESET ROLE;
DELETE FROM agent_settings WHERE company_id = t_u('cD') AND setting_key = 'golden_spoons_per_quarterly_questionnaire';
SELECT t_assert('v1.6.17: same-answers check — TPS-12 / IHS pay the same amount for different scores (d1 vs d2)',
  (SELECT count(DISTINCT score) = 2 AND count(DISTINCT reward_golden_spoons) = 1 FROM questionnaire_submission
    WHERE questionnaire_code = 'TPS-12' AND user_id IN (t_u('d1'), t_u('d2'))));
SELECT t_assert('v3-T12: questionnaire_definition rewards are participation-only (no per-questionnaire amount)',
  NOT EXISTS (SELECT 1 FROM questionnaire_definition WHERE reward_type <> 'participation' OR reward_amount IS NOT NULL));

-- ============ 3b. v1.6.18 A-14 (Karin 31.10) · questionnaire Golden Spoons adjustable per company ============
-- A weekly (short) questionnaire so all three settings can be seen (vp_hr defines it; the amount comes from settings).
SELECT t_as(t_u('hrF'));
SET ROLE authenticated;
SELECT code FROM rpc_upsert_questionnaire_definition('WEEK-F', 'Weekly pulse F', 'דופק שבועי F', 'weekly', NULL, 3, 1, 5);
RESET ROLE;
-- 4. Employees see the current value before filling out (computed field golden_spoons_reward on /questionnaire_definition).
SELECT t_as(t_u('f1'));
SET ROLE authenticated;
SELECT t_assert('A-14 (4): an employee sees the current amount before filling out — defaults PCQ-12 10, Cantril 10, weekly 2, TPS-12 10, IHS 10',
  (SELECT string_agg(q.code || '=' || trim_scale(golden_spoons_reward(q))::text, ',' ORDER BY q.code) FROM questionnaire_definition q
    WHERE q.code IN ('PCQ-12', 'Cantril', 'WEEK-F', 'TPS-12', 'IHS'))
  = 'Cantril=10,IHS=10,PCQ-12=10,TPS-12=10,WEEK-F=2');
SELECT t_assert('A-14: f1 fills PCQ-12 before any change → 10 (snapshot: key golden_spoons_per_questionnaire, effective_from NULL = pack default)',
  (SELECT reward_golden_spoons = 10 AND reward_setting_key = 'golden_spoons_per_questionnaire' AND reward_effective_from IS NULL
     FROM rpc_submit_questionnaire('PCQ-12', '{2,2,2,2,2,2,2,2,2,2,2,2}')));
SELECT t_assert('A-14: f1 fills the weekly questionnaire before any change → 2', (SELECT reward_golden_spoons = 2 FROM rpc_submit_questionnaire('WEEK-F', '{3,3,3}')));
RESET ROLE;
-- 3. Only vp_hr can change it.
SELECT t_as(t_u('cfoF'));
SET ROLE authenticated;
SELECT t_assert('A-14 (3): cfo still reads the settings', (SELECT count(*) >= 29 FROM rpc_get_agent_settings(t_u('cF'))));
SELECT t_expect_http('A-14 (3): cfo → 403 on the monthly amount', $$SELECT * FROM rpc_put_agent_setting(t_u('cF'), 'golden_spoons_per_questionnaire', 12)$$, 'insufficient_privilege', 403);
SELECT t_expect_http('A-14 (3): cfo → 403 on the short amount', $$SELECT * FROM rpc_put_agent_setting(t_u('cF'), 'golden_spoons_per_short_questionnaire', 3)$$, 'insufficient_privilege', 403);
SELECT t_expect_http('A-14 (3): cfo → 403 on the quarterly amount', $$SELECT * FROM rpc_put_agent_setting(t_u('cF'), 'golden_spoons_per_quarterly_questionnaire', 15)$$, 'insufficient_privilege', 403);
RESET ROLE;
SELECT t_as(t_u('f1'));
SET ROLE authenticated;
SELECT t_expect_http('A-14 (3): an employee → 403', $$SELECT * FROM rpc_put_agent_setting(t_u('cF'), 'golden_spoons_per_questionnaire', 12)$$, 'insufficient_privilege', 403);
RESET ROLE;
SELECT t_as(t_u('hrA'));
SET ROLE authenticated;
SELECT t_expect_http('A-14 (3): the vp_hr of ANOTHER company → 403', $$SELECT * FROM rpc_put_agent_setting(t_u('cF'), 'golden_spoons_per_questionnaire', 12)$$, 'insufficient_privilege', 403);
RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', false) AS no_caller;
SELECT t_expect_http('A-14 (3): a service call without a vp_hr behind it → 403 (vp_hr only)', $$SELECT * FROM rpc_put_agent_setting(t_u('cF'), 'golden_spoons_per_questionnaire', 12)$$, 'insufficient_privilege', 403);
-- 2. Range 1–20 per questionnaire (422 outside).
SELECT t_as(t_u('hrF'));
SET ROLE authenticated;
SELECT t_expect_http('A-14 (2): 21 → 422 questionnaire_reward_out_of_range', $$SELECT * FROM rpc_put_agent_setting(t_u('cF'), 'golden_spoons_per_questionnaire', 21)$$, 'questionnaire_reward_out_of_range', 422);
SELECT t_expect_http('A-14 (2): 0 → 422', $$SELECT * FROM rpc_put_agent_setting(t_u('cF'), 'golden_spoons_per_short_questionnaire', 0)$$, 'questionnaire_reward_out_of_range', 422);
SELECT t_expect_http('A-14 (2): 0.9 → 422', $$SELECT * FROM rpc_put_agent_setting(t_u('cF'), 'golden_spoons_per_quarterly_questionnaire', 0.9)$$, 'questionnaire_reward_out_of_range', 422);
SELECT t_expect_http('A-14 (2): −5 → 422', $$SELECT * FROM rpc_put_agent_setting(t_u('cF'), 'golden_spoons_per_quarterly_questionnaire', -5)$$, 'questionnaire_reward_out_of_range', 422);
SELECT t_expect_http('A-14 (2): 20.5 → 422', $$SELECT * FROM rpc_put_agent_setting(t_u('cF'), 'golden_spoons_per_questionnaire', 20.5)$$, 'questionnaire_reward_out_of_range', 422);
SELECT t_expect_http('A-14: more than one decimal (2.55) → 400 invalid_setting_value', $$SELECT * FROM rpc_put_agent_setting(t_u('cF'), 'golden_spoons_per_short_questionnaire', 2.55)$$, 'invalid_setting_value', 400);
RESET ROLE;
SELECT t_assert('A-14 (2): the refused values left no override and no history row',
  NOT EXISTS (SELECT 1 FROM agent_settings WHERE company_id = t_u('cF'))
  AND NOT EXISTS (SELECT 1 FROM questionnaire_reward_history WHERE company_id = t_u('cF')));
SELECT t_as(t_u('hrF'));
SET ROLE authenticated;
SELECT t_assert('A-14 (2): the boundaries are accepted — 1 and 20', (SELECT value_numeric = 1 AND scope = 'company' FROM rpc_put_agent_setting(t_u('cF'), 'golden_spoons_per_short_questionnaire', 1)));
SELECT t_assert('A-14 (2): …20', (SELECT value_numeric = 20 FROM rpc_put_agent_setting(t_u('cF'), 'golden_spoons_per_quarterly_questionnaire', 20)));
SELECT t_assert('A-14 (3): vp_hr sets monthly 12', (SELECT value_numeric = 12 AND scope = 'company' FROM rpc_put_agent_setting(t_u('cF'), 'golden_spoons_per_questionnaire', 12)));
SELECT t_assert('A-14 (3): vp_hr sets short 3', (SELECT value_numeric = 3 FROM rpc_put_agent_setting(t_u('cF'), 'golden_spoons_per_short_questionnaire', 3)));
SELECT t_assert('A-14 (3): vp_hr sets quarterly 15', (SELECT value_numeric = 15 FROM rpc_put_agent_setting(t_u('cF'), 'golden_spoons_per_quarterly_questionnaire', 15)));
RESET ROLE;
-- 3. WORM audit + history, effective from now, non-retroactive.
SELECT t_assert('A-14 (3): every change is in the WORM history with value before / after and effective_from (5 rows: short 2→1→3, quarterly 10→20→15, monthly 10→12)',
  (SELECT string_agg(setting_key || ':' || trim_scale(value_before)::text || '>' || trim_scale(value_after)::text, ',' ORDER BY effective_from)
     FROM questionnaire_reward_history WHERE company_id = t_u('cF'))
  = 'golden_spoons_per_short_questionnaire:2>1,golden_spoons_per_quarterly_questionnaire:10>20,golden_spoons_per_questionnaire:10>12,golden_spoons_per_short_questionnaire:1>3,golden_spoons_per_quarterly_questionnaire:20>15');
SELECT t_assert('A-14 (3): …and every change is in access_audit_log (WORM) by the vp_hr, with before / after / effective_from',
  (SELECT count(*) = 5 AND bool_and(viewer_id = t_u('hrF') AND scope ? 'value_before' AND scope ? 'value_after' AND scope ? 'effective_from')
     FROM access_audit_log WHERE action = 'questionnaire_reward_setting_put' AND company_id = t_u('cF')));
SELECT t_expect_err('A-14 (3): the history is WORM (UPDATE refused)', $$UPDATE questionnaire_reward_history SET value_after = 5$$, 'ledger_immutable');
SELECT t_expect_err('A-14 (3): the history is WORM (DELETE refused)', $$DELETE FROM questionnaire_reward_history$$, 'ledger_immutable');
SELECT t_assert('A-14 (3): nothing retroactive — f1''s PCQ-12 (10) and weekly (2) submissions and her wallet are unchanged',
  (SELECT string_agg(questionnaire_code || '=' || trim_scale(reward_golden_spoons)::text, ',' ORDER BY questionnaire_code)
     FROM questionnaire_submission WHERE user_id = t_u('f1')) = 'PCQ-12=10,WEEK-F=2'
  AND (SELECT golden_spoons = 12 FROM avatar_state WHERE user_id = t_u('f1')));
SELECT t_as(t_u('f2'));
SET ROLE authenticated;
SELECT t_assert('A-14 (4): f2 sees the new amounts before filling out — PCQ-12 12, Cantril 12, weekly 3, TPS-12 15, IHS 15',
  (SELECT string_agg(q.code || '=' || trim_scale(golden_spoons_reward(q))::text, ',' ORDER BY q.code) FROM questionnaire_definition q
    WHERE q.code IN ('PCQ-12', 'Cantril', 'WEEK-F', 'TPS-12', 'IHS'))
  = 'Cantril=12,IHS=15,PCQ-12=12,TPS-12=15,WEEK-F=3');
SELECT t_assert('A-14: from now on — f2 (other team, other org role) PCQ-12 → 12',
  (SELECT reward_golden_spoons = 12 AND reward_setting_key = 'golden_spoons_per_questionnaire'
     FROM rpc_submit_questionnaire('PCQ-12', '{6,6,6,6,6,6,6,6,6,6,6,6}')));
SELECT t_assert('A-14: f2 Cantril → 12', (SELECT reward_golden_spoons = 12 FROM rpc_submit_questionnaire('Cantril', '{9}')));
SELECT t_assert('A-14: f2 weekly → 3', (SELECT reward_golden_spoons = 3 FROM rpc_submit_questionnaire('WEEK-F', '{5,5,5}')));
SELECT t_assert('A-14: f2 TPS-12 → 15', (SELECT reward_golden_spoons = 15 FROM rpc_submit_questionnaire('TPS-12', '{5,5,5,5,5,5,5,5,5,5,5,5}')));
SELECT t_assert('A-14: f2 IHS → 15', (SELECT reward_golden_spoons = 15 FROM rpc_submit_questionnaire('IHS', '{5,5,5,5,5,5,5,5,5}')));
RESET ROLE;
SELECT t_as(t_u('f1'));
SET ROLE authenticated;
SELECT t_assert('A-14 (1): f1 (other team, other role, lowest answers) gets the very same amounts — Cantril 12',
  (SELECT reward_golden_spoons = 12 FROM rpc_submit_questionnaire('Cantril', '{0}')));
SELECT t_assert('A-14 (1): f1 TPS-12 → 15', (SELECT reward_golden_spoons = 15 FROM rpc_submit_questionnaire('TPS-12', '{1,1,1,1,1,1,1,1,1,1,1,1}')));
SELECT t_assert('A-14 (1): f1 IHS → 15', (SELECT reward_golden_spoons = 15 FROM rpc_submit_questionnaire('IHS', '{1,1,1,1,1,1,1,1,1}')));
RESET ROLE;
SELECT t_assert('A-14 (3): provable — f2''s PCQ-12 snapshot effective_from = the monthly change in the history, and it is later than f1''s 10-spoon submission',
  (SELECT s.reward_effective_from = (SELECT max(h.effective_from) FROM questionnaire_reward_history h
                                      WHERE h.company_id = t_u('cF') AND h.setting_key = 'golden_spoons_per_questionnaire')
          AND s.reward_effective_from > (SELECT o.submitted_at FROM questionnaire_submission o WHERE o.user_id = t_u('f1') AND o.questionnaire_code = 'PCQ-12')
          AND s.submitted_at >= s.reward_effective_from
     FROM questionnaire_submission s WHERE s.user_id = t_u('f2') AND s.questionnaire_code = 'PCQ-12'));
SELECT t_assert('A-14 (1): one value per company — after the change every F submission of a setting pays the same amount whatever the answers, team or org role',
  (SELECT bool_and(n = 1) FROM (SELECT count(DISTINCT s.reward_golden_spoons) n FROM questionnaire_submission s JOIN users u USING (user_id)
                                 WHERE u.company_id = t_u('cF') AND s.reward_effective_from IS NOT NULL
                                 GROUP BY s.reward_setting_key) x)
  AND (SELECT count(DISTINCT u.department) = 2 AND count(DISTINCT u.org_role_code) = 2 FROM questionnaire_submission s JOIN users u USING (user_id)
        WHERE u.company_id = t_u('cF') AND s.reward_effective_from IS NOT NULL));
SELECT t_assert('A-14 (1): the amount depends only on the definition and the company — fn_questionnaire_reward(definition, company) and the settings key is (company, setting) only',
  pg_get_function_identity_arguments('fn_questionnaire_reward(questionnaire_definition, uuid)'::regprocedure) = 'p_def questionnaire_definition, p_company uuid'
  AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'agent_settings' AND column_name ~* '(team|department|role|user|answer)'));
SELECT t_assert('A-14: other companies keep the defaults (company D PCQ-12 = 10)', fn_questionnaire_reward((SELECT q FROM questionnaire_definition q WHERE code = 'PCQ-12'), t_u('cD')) = 10);
SELECT t_as(t_u('hrF'));
SET ROLE authenticated;
SELECT t_assert('A-14 (3): vp_hr resets the monthly amount to the default (10) — logged as scope default',
  (SELECT value_numeric = 10 AND scope = 'default' FROM rpc_put_agent_setting(t_u('cF'), 'golden_spoons_per_questionnaire')));
RESET ROLE;
SELECT t_assert('A-14 (3): …the reset is a history row (12 → 10, default) and earlier submissions still hold 12',
  (SELECT value_before = 12 AND value_after = 10 AND scope_after = 'default' FROM questionnaire_reward_history
    WHERE company_id = t_u('cF') ORDER BY effective_from DESC LIMIT 1)
  AND (SELECT reward_golden_spoons = 12 FROM questionnaire_submission WHERE user_id = t_u('f2') AND questionnaire_code = 'PCQ-12'));
SELECT t_assert('A-14 privacy: questionnaire_reward_history has no person column and is closed (RLS forced, no client grant)',
  NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'questionnaire_reward_history' AND column_name ~* '(person|user|employee|pseudonym|changed_by)')
  AND NOT has_table_privilege('authenticated', 'questionnaire_reward_history', 'SELECT')
  AND (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid = 'questionnaire_reward_history'::regclass));
SELECT t_as(t_u('hrF'));
SET ROLE authenticated;
INSERT INTO t_outputs SELECT 'a14_settings', jsonb_agg(to_jsonb(s)) FROM rpc_get_agent_settings(t_u('cF')) s;
RESET ROLE;

-- ============ 4. v3-T6 / v3-T7 · open Golden Spoons liability, 30-day exit redemption ============
SELECT t_as(t_u('cfoB'));
SET ROLE authenticated;
INSERT INTO t_outputs SELECT 'liability_not_defined', rpc_get_open_golden_spoons_liability(t_u('cB'));
SELECT t_assert('v3-T6 + v1.6.19 A-3: cfo sees open Golden Spoons; fewer than 10 purchases → no ILS estimate, "אין עדיין מספיק מימושים לאומדן"',
  (SELECT (j->>'open_golden_spoons')::numeric = 40 + 50 + 40 + 30 + 30 AND j->'ils_estimate' = 'null'::jsonb
          AND j->>'ils_status' = 'insufficient' AND j->>'display_he' = 'אין עדיין מספיק מימושים לאומדן'
          AND j->>'liability_method' = 'avg_redeemed'
     FROM (SELECT rpc_get_open_golden_spoons_liability(t_u('cB')) j) x));
RESET ROLE;
SELECT t_as(t_u('empB1'));
SET ROLE authenticated;
SELECT t_expect_http('v3-T6: employee → 403 on the ILS liability', $$SELECT rpc_get_open_golden_spoons_liability(t_u('cB'))$$, 'insufficient_privilege', 403);
RESET ROLE;
SELECT t_as(t_u('mgrB'));
SET ROLE authenticated;
SELECT t_expect_http('v3-T6: manager → 403 on the ILS liability', $$SELECT rpc_get_open_golden_spoons_liability(t_u('cB'))$$, 'insufficient_privilege', 403);
RESET ROLE;
SELECT t_as(t_u('chairA'));
SET ROLE authenticated;
SELECT t_expect_http('v3-T6: board chair → 403 on the ILS liability', $$SELECT rpc_get_open_golden_spoons_liability(t_u('cA'))$$, 'insufficient_privilege', 403);
RESET ROLE;
SELECT t_assert('v3-T6: no conversion rate in any employee-readable column (no ILS / spoon cost / liability column granted to authenticated; item ILS costs in a closed table)',
  NOT EXISTS (SELECT 1 FROM information_schema.column_privileges
               WHERE grantee = 'authenticated' AND privilege_type = 'SELECT'
                 AND column_name ~* '(ils|spoon_cost|internal_cost|liability_method|exchange)')
  AND NOT has_table_privilege('authenticated', 'everstore_item_cost', 'SELECT')
  AND NOT has_table_privilege('authenticated', 'golden_spoons_ledger', 'SELECT'));

-- leaverB ended 2026-09-01 10:00 (Jerusalem) → last redemption day 2026-10-01; day 31 = 2026-10-02.
UPDATE users SET employment_ended_at = '2026-09-01 10:00+03' WHERE user_id = t_u('leaverB');
SELECT t_assert('v3-T7: redemption deadline = end of employment + 30 days (2026-10-01)', fn_exit_redemption_deadline(t_u('leaverB')) = DATE '2026-10-01');
SELECT t_assert('v3-T7: day 30 (2026-10-01 23:30 local) still inside the window; nothing expires',
  fn_in_exit_redemption_window(t_u('leaverB'), '2026-10-01 23:30+03')
  AND rpc_expire_departed_golden_spoons('2026-10-01 23:30+03') = 0);
SELECT t_assert('v3-T7: …balance kept on day 30 (40)', (SELECT golden_spoons = 40 FROM avatar_state WHERE user_id = t_u('leaverB')));
SELECT t_assert('v3-T7: day 31 (2026-10-02 00:30 local) → 1 balance reset', rpc_expire_departed_golden_spoons('2026-10-02 00:30+03') = 1);
SELECT t_assert('v3-T7: balance 0 and a WORM ledger row expired_after_exit (40, deadline 2026-10-01)',
  (SELECT golden_spoons = 0 FROM avatar_state WHERE user_id = t_u('leaverB'))
  AND (SELECT count(*) = 1 AND sum(amount) = 40 AND min(exit_deadline) = DATE '2026-10-01'
         FROM golden_spoons_ledger WHERE user_id = t_u('leaverB') AND event_type = 'expired_after_exit'));
SELECT t_assert('v3-T7: re-run expires nothing (idempotent)', rpc_expire_departed_golden_spoons('2026-10-03 09:00+03') = 0);
SELECT t_expect_err('v3-T7: golden_spoons_ledger is WORM', $$UPDATE golden_spoons_ledger SET amount = 1$$, 'ledger_immutable');
SELECT t_as(t_u('cfoB'));
SET ROLE authenticated;
SELECT t_assert('v3-T7: the expired balance left the open liability (190 − 40 = 150)',
  (SELECT (rpc_get_open_golden_spoons_liability(t_u('cB'))->>'open_golden_spoons')::numeric = 150));
SELECT t_expect_err('v3-T7: the expiry job is service-only (no EXECUTE for clients → 42501)', $$SELECT rpc_expire_departed_golden_spoons()$$, '42501');
RESET ROLE;
-- 30-day window for purchases (decision 4): depB left 5 days ago, depOld 40 days ago.
UPDATE users SET employment_ended_at = clock_timestamp() - interval '5 days' WHERE user_id = t_u('depB');
UPDATE users SET employment_ended_at = clock_timestamp() - interval '40 days' WHERE user_id = t_u('depOld');
SELECT t_as(t_u('depB'));
SET ROLE authenticated;
SELECT t_assert('exit window: ex-employee inside 30 days may still redeem (30 → 20)',
  (SELECT golden_spoons = 20 FROM rpc_everstore_purchase('theme_basement_office', 'dep-1')));
SELECT t_expect_http('exit window: …but not a time benefit after exit (judgment)', $$SELECT rpc_everstore_purchase('voucher_refresh_day', 'dep-2')$$, 'anti_get_blocked', 403);
RESET ROLE;
SELECT t_as(t_u('depOld'));
SET ROLE authenticated;
SELECT t_expect_http('exit window: after 30 days → 403', $$SELECT rpc_everstore_purchase('theme_basement_office', 'old-1')$$, 'anti_get_blocked', 403);
RESET ROLE;

-- ============ 4b. v1.6.17 J-15 (confirmed by Karin 31.10) · no time benefits after employment ends ============
SELECT t_as(t_u('depB'));
SET ROLE authenticated;
SELECT t_expect_http('J-15: inside the 30-day window a time benefit with a chosen day is still refused → 403',
  $$SELECT rpc_everstore_purchase('voucher_refresh_day', 'dep-3', CURRENT_DATE + 3)$$, 'anti_get_blocked', 403);
SELECT t_expect_http('J-15: the go-home (early leave) RPC is refused after exit → 403', $$SELECT rpc_log_go_home()$$, 'anti_get_blocked', 403);
RESET ROLE;
SELECT t_assert('J-15: …the refused time benefit cost nothing and left no trace (balance 20, one purchase = the product, no absence row)',
  (SELECT golden_spoons = 20 FROM avatar_state WHERE user_id = t_u('depB'))
  AND (SELECT count(*) = 1 AND min(category) = 'cosmetic' FROM shop_purchase WHERE user_id = t_u('depB'))
  AND NOT EXISTS (SELECT 1 FROM approved_absence_entry WHERE user_id = t_u('depB')));
SELECT t_expect_http('J-15: DB guard — no early leave row for an ex-employee on any path (fn_log_early_leave)',
  $$SELECT fn_log_early_leave(t_u('depB'))$$, 'anti_get_blocked', 403);
SELECT t_expect_http('J-15: DB guard — no approved absence / day off row for an ex-employee (direct insert)',
  $$INSERT INTO approved_absence_entry (user_id, company_id, requested_date, entry_type, entry_text, schedule_status)
    VALUES (t_u('depB'), t_u('cB'), CURRENT_DATE + 1, 'approved_absence', 'זמן התרעננות / היעדרות מאושרת', 'pending_coordination')$$,
  'anti_get_blocked', 403);
SELECT t_assert('J-15: no early_leave_log / approved_absence_entry row exists for any ex-employee',
  NOT EXISTS (SELECT 1 FROM early_leave_log l JOIN users u ON u.user_id = l.user_id WHERE u.employment_ended_at IS NOT NULL)
  AND NOT EXISTS (SELECT 1 FROM approved_absence_entry a JOIN users u ON u.user_id = a.user_id WHERE u.employment_ended_at IS NOT NULL));
SELECT t_assert('J-15: guard triggers installed on both time-benefit tables',
  (SELECT count(*) = 2 FROM pg_trigger WHERE tgname IN ('trg_early_leave_after_exit', 'trg_approved_absence_after_exit') AND NOT tgisinternal));
-- Control: an ACTIVE employee still gets the time benefit (bought with Golden Spoons) and an early leave.
INSERT INTO avatar_state (user_id, golden_spoons) VALUES (t_u('d3'), 40) ON CONFLICT (user_id) DO UPDATE SET golden_spoons = 40;
SELECT t_as(t_u('d3'));
SET ROLE authenticated;
SELECT t_assert('J-15 control: an active employee redeems the time benefit (40 → 5) → standard approved absence row',
  (SELECT golden_spoons = 5 FROM rpc_everstore_purchase('voucher_refresh_day', 'd3-1', CURRENT_DATE + 2)));
RESET ROLE;
SELECT t_assert('J-15 control: …the approved absence exists for the active employee, and an early leave can be logged',
  EXISTS (SELECT 1 FROM approved_absence_entry WHERE user_id = t_u('d3'))
  AND (SELECT log_id IS NOT NULL FROM fn_log_early_leave(t_u('d3'))));

-- ============ 4c. v1.6.18 A-13 (Karin 31.10) · time benefit scheduled after the end of employment is cancelled ============
-- tb1 buys four refresh days (35 each) while employed: yesterday, today (= her end day), today + 3 and today + 10.
INSERT INTO avatar_state (user_id, golden_spoons) VALUES (t_u('tb1'), 150), (t_u('tb2'), 40);
CREATE TEMP TABLE t_a13 AS SELECT fn_user_local_date(t_u('tb1')) AS today;
GRANT SELECT ON t_a13 TO authenticated;
SELECT t_as(t_u('tb1'));
SET ROLE authenticated;
SELECT golden_spoons FROM rpc_everstore_purchase('voucher_refresh_day', 'tb1-before', (SELECT today - 1 FROM t_a13));
SELECT golden_spoons FROM rpc_everstore_purchase('voucher_refresh_day', 'tb1-endday', (SELECT today FROM t_a13));
SELECT golden_spoons FROM rpc_everstore_purchase('voucher_refresh_day', 'tb1-after3', (SELECT today + 3 FROM t_a13));
SELECT t_assert('A-13: four time benefits bought while employed (150 − 4 × 35 = 10)',
  (SELECT golden_spoons = 10 FROM rpc_everstore_purchase('voucher_refresh_day', 'tb1-after10', (SELECT today + 10 FROM t_a13))));
RESET ROLE;
SELECT t_assert('A-13: each absence has its CLOSED purchase link (price 35); approved_absence_entry itself has no purchase / item / Golden Spoons column (נעילת הפרגוד)',
  (SELECT count(*) = 4 AND bool_and(l.price_golden_spoons = 35) FROM approved_absence_entry a JOIN time_benefit_absence_link l USING (absence_id)
    WHERE a.user_id = t_u('tb1'))
  AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'approved_absence_entry'
                   AND column_name ~* '(purchase|item|spoon|price|everstore|shop|voucher)'));
-- The end of employment is recorded now (employee-local end day = today).
UPDATE users SET employment_ended_at = clock_timestamp() WHERE user_id = t_u('tb1');
SELECT t_assert('A-13: the two benefits scheduled AFTER the end day are cancelled (cancel_reason employment_ended)',
  (SELECT string_agg((requested_date - (SELECT today FROM t_a13))::text || ':' || schedule_status || ':' || COALESCE(cancel_reason, '-'), ',' ORDER BY requested_date)
     FROM approved_absence_entry WHERE user_id = t_u('tb1'))
  = '-1:pending_coordination:-,0:pending_coordination:-,3:cancelled:employment_ended,10:cancelled:employment_ended');
SELECT t_assert('A-13: a benefit scheduled before the end date (and on the end day itself) is unaffected — no refund for it',
  (SELECT count(*) = 2 FROM approved_absence_entry a WHERE a.user_id = t_u('tb1') AND a.requested_date <= (SELECT today FROM t_a13)
      AND a.schedule_status = 'pending_coordination' AND a.cancelled_at IS NULL
      AND NOT EXISTS (SELECT 1 FROM time_benefit_refund r WHERE r.absence_id = a.absence_id)));
SELECT t_assert('A-13: the Golden Spoons of the cancelled benefits are refunded (10 + 2 × 35 = 80), one WORM refund row each',
  (SELECT golden_spoons = 80 FROM avatar_state WHERE user_id = t_u('tb1'))
  AND (SELECT count(*) = 2 AND sum(r.amount) = 70 FROM time_benefit_refund r JOIN approved_absence_entry a USING (absence_id) WHERE a.user_id = t_u('tb1')));
SELECT t_expect_err('A-13: time_benefit_refund is WORM', $$UPDATE time_benefit_refund SET amount = 1$$, 'ledger_immutable');
-- Idempotent: the operation again, and the end date touched again, change nothing.
INSERT INTO t_outputs SELECT 'a13_second_call', fn_cancel_time_benefits_after_exit(t_u('tb1'));
UPDATE users SET employment_ended_at = employment_ended_at + interval '1 second' WHERE user_id = t_u('tb1');
SELECT t_assert('A-13 idempotent: a second run cancels and refunds nothing (status nothing_to_cancel; balance 80; 2 cancelled; 2 refunds)',
  (SELECT j->>'status' = 'nothing_to_cancel' AND (j->>'refunded_golden_spoons')::numeric = 0 FROM t_outputs WHERE label = 'a13_second_call')
  AND (SELECT golden_spoons = 80 FROM avatar_state WHERE user_id = t_u('tb1'))
  AND (SELECT count(*) = 2 FROM approved_absence_entry WHERE user_id = t_u('tb1') AND schedule_status = 'cancelled')
  AND (SELECT count(*) = 2 FROM time_benefit_refund r JOIN approved_absence_entry a USING (absence_id) WHERE a.user_id = t_u('tb1')));
SELECT t_expect_err('A-13 idempotent: one refund per absence at most (primary key)',
  $$INSERT INTO time_benefit_refund (absence_id, amount, refund_reason) SELECT absence_id, 35, 'employment_ended' FROM time_benefit_refund LIMIT 1$$, '23505');
-- In the 30-day window: products only (J-15).
SELECT t_as(t_u('tb1'));
SET ROLE authenticated;
SELECT t_expect_http('A-13 / J-15: with the refund in the 30-day window a time benefit is still refused → 403',
  $$SELECT rpc_everstore_purchase('voucher_refresh_day', 'tb1-window-tb', (SELECT today + 1 FROM t_a13))$$, 'anti_get_blocked', 403);
SELECT t_assert('A-13 / J-15: …while an EverStore product can be bought with the refunded Golden Spoons (80 − 5 = 75)',
  (SELECT golden_spoons = 75 FROM rpc_everstore_purchase('charity_trees', 'tb1-window-product')));
SELECT t_expect_http('A-13: after the end nothing can be moved earlier by the employee (cancelled entry) → 403',
  $$SELECT * FROM rpc_request_absence_reschedule((SELECT absence_id FROM approved_absence_entry WHERE requested_date = (SELECT today + 3 FROM t_a13)), (SELECT today FROM t_a13))$$,
  'anti_get_blocked', 403);
SELECT t_expect_http('A-13: after the end even a still-valid entry cannot be moved → 403',
  $$SELECT * FROM rpc_request_absence_reschedule((SELECT absence_id FROM approved_absence_entry WHERE requested_date = (SELECT today FROM t_a13)), (SELECT today FROM t_a13))$$,
  'anti_get_blocked', 403);
RESET ROLE;
SELECT t_assert('A-13: nothing was moved earlier automatically — the cancelled entries keep their own dates (today + 3, today + 10)',
  (SELECT array_agg(requested_date - (SELECT today FROM t_a13) ORDER BY requested_date) = '{3,10}'
     FROM approved_absence_entry WHERE user_id = t_u('tb1') AND schedule_status = 'cancelled'));
-- The direct manager: sees the cancellation as a plain HR status (no EverStore trace) and cannot reschedule it.
-- (Manager-view rows carry the pseudonym by design, so they are kept out of the agent-output sweep table.)
CREATE TEMP TABLE t_a13_mgr (j jsonb);
GRANT SELECT, INSERT ON t_a13_mgr TO authenticated;
SELECT t_as(t_u('mgrD'));
SET ROLE authenticated;
INSERT INTO t_a13_mgr SELECT jsonb_agg(to_jsonb(v)) FROM approved_absence_manager_v v;
SELECT t_expect_http('A-13: the manager cannot coordinate a cancelled entry → 403',
  $$SELECT * FROM rpc_coordinate_approved_absence((SELECT absence_id FROM approved_absence_manager_v WHERE schedule_status = 'cancelled' LIMIT 1), NULL)$$,
  'anti_get_blocked', 403);
SELECT t_expect_http('A-13: …nor move an ex-employee''s remaining entry → 403',
  $$SELECT * FROM rpc_coordinate_approved_absence((SELECT absence_id FROM approved_absence_manager_v WHERE schedule_status <> 'cancelled' LIMIT 1), NULL)$$,
  'anti_get_blocked', 403);
RESET ROLE;
SELECT t_assert('A-13 Curtain: the manager view shows the 4 entries (2 cancelled) with the locked HR text only — no purchase, item, price or Golden Spoons field',
  (SELECT jsonb_array_length(j) = 4
          AND (SELECT count(*) = 2 FROM jsonb_array_elements(j) e WHERE e->>'schedule_status' = 'cancelled')
          AND (SELECT bool_and(e->>'entry_text' = 'זמן התרעננות / היעדרות מאושרת') FROM jsonb_array_elements(j) e)
          AND j::text !~* '(purchase|item_id|spoon|price|everstore|voucher|refund)'
     FROM t_a13_mgr));
-- A regular move-earlier request before the end (tb2): allowed; after the end: refused.
SELECT t_as(t_u('tb2'));
SET ROLE authenticated;
SELECT t_assert('A-13: tb2 (employed) buys a refresh day for today + 10 (40 → 5)',
  (SELECT golden_spoons = 5 FROM rpc_everstore_purchase('voucher_refresh_day', 'tb2-1', (SELECT today + 10 FROM t_a13))));
INSERT INTO t_outputs SELECT 'a13_reschedule', to_jsonb(r) FROM rpc_request_absence_reschedule(
  (SELECT absence_id FROM approved_absence_entry WHERE requested_date = (SELECT today + 10 FROM t_a13)), (SELECT today + 2 FROM t_a13)) r;
SELECT t_expect_http('A-13: a move to a past day → 400 invalid_requested_date',
  $$SELECT * FROM rpc_request_absence_reschedule((SELECT absence_id FROM approved_absence_entry LIMIT 1), (SELECT today - 1 FROM t_a13))$$,
  'invalid_requested_date', 400);
RESET ROLE;
SELECT t_assert('A-13: the regular move-earlier request before the end is accepted (today + 10 → today + 2, back to pending_coordination) and returns no person field',
  (SELECT (j->>'requested_date')::date = (SELECT today + 2 FROM t_a13) AND j->>'schedule_status' = 'pending_coordination'
          AND NOT j ? 'user_id' AND t_ids_free(j) FROM t_outputs WHERE label = 'a13_reschedule'));
-- tb2 leaves today: the (moved) benefit at today + 2 is after her end day → cancelled and refunded.
UPDATE users SET employment_ended_at = clock_timestamp() WHERE user_id = t_u('tb2');
SELECT t_assert('A-13: tb2''s benefit (today + 2) is cancelled at exit and refunded (5 + 35 = 40)',
  (SELECT schedule_status = 'cancelled' FROM approved_absence_entry WHERE user_id = t_u('tb2'))
  AND (SELECT golden_spoons = 40 FROM avatar_state WHERE user_id = t_u('tb2')));
SELECT t_as(t_u('tb2'));
SET ROLE authenticated;
SELECT t_expect_http('A-13: after the end the move-earlier request is refused → 403',
  $$SELECT * FROM rpc_request_absence_reschedule((SELECT absence_id FROM approved_absence_entry LIMIT 1), (SELECT today FROM t_a13))$$,
  'anti_get_blocked', 403);
RESET ROLE;
CREATE TEMP TABLE t_a13_ids AS
  SELECT absence_id FROM approved_absence_entry WHERE user_id = t_u('tb1') AND schedule_status <> 'cancelled' LIMIT 1;
GRANT SELECT ON t_a13_ids TO authenticated;
SELECT t_as(t_u('d3'));
SET ROLE authenticated;
SELECT t_expect_http('A-13: an employee cannot move someone else''s absence → 403', $$SELECT * FROM rpc_request_absence_reschedule((SELECT absence_id FROM t_a13_ids), (SELECT today + 1 FROM t_a13))$$, 'anti_get_blocked', 403);
RESET ROLE;
SELECT t_assert('A-13 Curtain: the purchase link and the refund record are CLOSED (RLS forced, no client grant)',
  (SELECT bool_and(c.relrowsecurity AND c.relforcerowsecurity AND NOT has_table_privilege('authenticated', c.oid, 'SELECT')
                   AND NOT has_table_privilege('anon', c.oid, 'SELECT'))
     FROM pg_class c WHERE c.relname IN ('time_benefit_absence_link', 'time_benefit_refund')));
INSERT INTO t_outputs SELECT 'a13_cancel_output', fn_cancel_time_benefits_after_exit(t_u('tb2'));
SELECT t_assert('A-13 privacy: the cancellation output and the employee reschedule output hold no person_id / user_id / pseudonym; the link / refund tables hold no user column',
  (SELECT bool_and(t_ids_free(j)) FROM t_outputs WHERE label LIKE 'a13_%')
  AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name IN ('time_benefit_absence_link', 'time_benefit_refund')
                   AND column_name ~* '(person|user|employee|pseudonym)'));

-- ============ 5. A2 / v3-T8 · anonymous aggregate EverStore budget summary ============
DO $$
DECLARE i int;
BEGIN
  -- W1 2026-09-10: cosmetic 6 buyers (5 theme + 1 badge), learning 6, gift card 2, donation 2 → "אחר" = 4 buyers
  FOR i IN 1..5 LOOP PERFORM t_buy('rest' || i, 'theme_basement_office', '2026-09-10 12:00+03'); END LOOP;
  PERFORM t_buy('rest6', 'badge_passive_pilgrim', '2026-09-10 12:00+03');
  FOR i IN 1..6 LOOP PERFORM t_buy('rest' || i, 'course_book', '2026-09-10 13:00+03'); END LOOP;
  PERFORM t_buy('rest7', 'coffee_card', '2026-09-10 12:00+03'); PERFORM t_buy('rest8', 'coffee_card', '2026-09-10 12:00+03');
  PERFORM t_buy('rest9', 'charity_trees', '2026-09-10 12:00+03'); PERFORM t_buy('rest10', 'charity_trees', '2026-09-10 12:00+03');
  -- W2 2026-09-20: gift card 2, donation 1, time benefit 1 → no category passes, small ones total 4 buyers
  PERFORM t_buy('rest1', 'coffee_card', '2026-09-20 12:00+03'); PERFORM t_buy('rest2', 'coffee_card', '2026-09-20 12:00+03');
  PERFORM t_buy('rest3', 'charity_trees', '2026-09-20 12:00+03');
  PERFORM t_buy('rest4', 'voucher_refresh_day', '2026-09-20 12:00+03');
  -- W3 2026-09-25: learning 5, gift card 3 + experience 3 (= "אחר" 6 buyers), time benefit 5
  FOR i IN 1..5 LOOP PERFORM t_buy('rest' || i, 'course_book', '2026-09-25 12:00+03'); END LOOP;
  FOR i IN 6..8 LOOP PERFORM t_buy('rest' || i, 'coffee_card', '2026-09-25 12:00+03'); END LOOP;
  FOR i IN 9..11 LOOP PERFORM t_buy('rest' || i, 'concert_pass', '2026-09-25 12:00+03'); END LOOP;
  FOR i IN 12..16 LOOP PERFORM t_buy('rest' || i, 'voucher_refresh_day', '2026-09-25 12:00+03'); END LOOP;
END $$;
SELECT t_as(t_u('cfoA'));
SET ROLE authenticated;
INSERT INTO t_outputs SELECT 'summary_w1', jsonb_agg(to_jsonb(s)) FROM rpc_everstore_budget_summary('2026-09-10', '2026-09-10') s;
INSERT INTO t_outputs SELECT 'summary_w2', jsonb_agg(to_jsonb(s)) FROM rpc_everstore_budget_summary('2026-09-20', '2026-09-20') s;
INSERT INTO t_outputs SELECT 'summary_w3', jsonb_agg(to_jsonb(s)) FROM rpc_everstore_budget_summary('2026-09-25', '2026-09-25') s;
SELECT t_assert('A2: company total (16 purchases, 178.0 Golden Spoons) and time_benefit total (0) always present',
  (SELECT purchase_count = 16 AND total_golden_spoons = 178.0 FROM rpc_everstore_budget_summary('2026-09-10', '2026-09-10') WHERE row_type = 'company_total')
  AND (SELECT purchase_count = 0 AND total_golden_spoons = 0 FROM rpc_everstore_budget_summary('2026-09-10', '2026-09-10') WHERE row_type = 'time_benefit_total'));
SELECT t_assert('v3-T8: "אחר" with 4 buyers (gift card 2 + donation 2) merges into the smallest passing category (cosmetic, 6 buyers) and is marked',
  (SELECT purchase_count = 4 AND total_golden_spoons = 25.0 AND category = 'cosmetic' AND name_he = 'אחר' AND includes_small_categories
          AND note_he = 'כולל קטגוריות קטנות'
     FROM rpc_everstore_budget_summary('2026-09-10', '2026-09-10') WHERE row_type = 'merged_small_categories'));
SELECT t_assert('A2: item rows grouped by category / item_id / name_he / tier / cosmetic_only / provider (theme 5 buyers, course_book 6 buyers)',
  (SELECT string_agg(category || ':' || item_id || ':' || tier || ':' || cosmetic_only || ':' || COALESCE(provider, '-') || ':' || purchase_count || ':' || total_golden_spoons, ',' ORDER BY item_id)
     FROM rpc_everstore_budget_summary('2026-09-10', '2026-09-10') WHERE row_type = 'item')
  = 'learning:course_book:custom:false:AcadPress:6:93.0,cosmetic:theme_basement_office:basic:true:-:5:50.0');
SELECT t_assert('A2: an item with < 5 buyers is collapsed inside its category ("פריטים נוספים", no item id)',
  (SELECT item_id IS NULL AND name_he = 'פריטים נוספים' AND purchase_count = 1 AND total_golden_spoons = 10.0
     FROM rpc_everstore_budget_summary('2026-09-10', '2026-09-10') WHERE row_type = 'item_small_merged'));
SELECT t_assert('v3-T8: still < 5 buyers after merging (no passing category) → only the company total (time benefit 1 buyer hidden)',
  (SELECT array_agg(row_type ORDER BY row_type) = '{company_total,time_benefit_total}'
          AND bool_and(purchase_count IS NULL) FILTER (WHERE row_type = 'time_benefit_total')
          AND max(note_he) FILTER (WHERE row_type = 'time_benefit_total') = 'אין מספיק קונים להצגה'
          AND max(purchase_count) FILTER (WHERE row_type = 'company_total') = 4
     FROM rpc_everstore_budget_summary('2026-09-20', '2026-09-20')));
SELECT t_assert('A2: small categories with ≥ 5 buyers together form their own "אחר" row (gift card 3 + experience 3 = 6 buyers)',
  (SELECT purchase_count = 6 AND total_golden_spoons = 202.5 AND category = 'אחר' AND NOT includes_small_categories
     FROM rpc_everstore_budget_summary('2026-09-25', '2026-09-25') WHERE row_type = 'other'));
SELECT t_assert('A2: time_benefit total shown with ≥ 5 buyers (5 × 35 = 175.0)',
  (SELECT purchase_count = 5 AND total_golden_spoons = 175.0 FROM rpc_everstore_budget_summary('2026-09-25', '2026-09-25') WHERE row_type = 'time_benefit_total'));
SELECT t_assert('A2: the view everstore_budget_summary_v (current month) answers vp_hr / cfo', EXISTS (SELECT 1 FROM everstore_budget_summary_v WHERE row_type = 'company_total'));
SELECT t_expect_http('A2: from > to → 400', $$SELECT * FROM rpc_everstore_budget_summary('2026-09-20', '2026-09-10')$$, 'invalid_date_range', 400);
RESET ROLE;
SELECT t_as(t_u('hrA'));
SET ROLE authenticated;
SELECT t_assert('A2: vp_hr gets the same summary', (SELECT purchase_count = 16 FROM rpc_everstore_budget_summary('2026-09-10', '2026-09-10') WHERE row_type = 'company_total'));
RESET ROLE;
SELECT t_as(t_u('mgrA'));
SET ROLE authenticated;
SELECT t_expect_http('A2: manager → 403 insufficient_privilege (RPC)', $$SELECT * FROM rpc_everstore_budget_summary()$$, 'insufficient_privilege', 403);
SELECT t_expect_http('A2: manager → 403 insufficient_privilege (view)', $$SELECT * FROM everstore_budget_summary_v$$, 'insufficient_privilege', 403);
RESET ROLE;
SELECT t_as(t_u('rest1'));
SET ROLE authenticated;
SELECT t_expect_http('A2: employee → 403 (view)', $$SELECT * FROM everstore_budget_summary_v$$, 'insufficient_privilege', 403);
SELECT t_expect_http('A2: employee → 403 (function)', $$SELECT * FROM fn_everstore_budget_summary()$$, 'insufficient_privilege', 403);
RESET ROLE;
SELECT t_as(t_u('chairA'));
SET ROLE authenticated;
SELECT t_expect_http('A2: board chair → 403', $$SELECT * FROM rpc_everstore_budget_summary()$$, 'insufficient_privilege', 403);
RESET ROLE;
SELECT t_assert('A2: output columns carry no user_id / pseudonym / person_id / team / department / timestamp',
  (SELECT string_agg(column_name, ',' ORDER BY ordinal_position) FROM information_schema.columns
    WHERE table_name = 'everstore_budget_summary_v')
  = 'row_type,category,item_id,name_he,tier,cosmetic_only,provider,purchase_count,total_golden_spoons,includes_small_categories,note_he'
  AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'everstore_budget_summary_v'
                   AND (data_type LIKE 'timestamp%' OR data_type = 'date' OR column_name ~* '(user|pseudonym|person|team|department|_at$)')));
SELECT t_assert('A2: purchase_count bigint, total_golden_spoons numeric(12,1)',
  (SELECT bool_and(CASE column_name WHEN 'purchase_count' THEN data_type = 'bigint'
                                    ELSE data_type = 'numeric' AND numeric_precision = 12 AND numeric_scale = 1 END)
     FROM information_schema.columns WHERE table_name = 'everstore_budget_summary_v'
      AND column_name IN ('purchase_count', 'total_golden_spoons')));
SELECT t_assert('A2: fn_everstore_budget_summary is SECURITY DEFINER with the 2 optional date arguments',
  (SELECT prosecdef AND pronargs = 2 AND pronargdefaults = 2 FROM pg_proc WHERE oid = 'fn_everstore_budget_summary(date, date)'::regprocedure));

-- ============ 6. v3-T9 / v3-T10 · one daily summary per crossing day, company timezone ============
SELECT t_as(t_u('cfoB'));
SET ROLE authenticated;
SELECT t_assert('v3-T9: daily_summary_time not defined → no summary, status not_defined ("לא הוגדר")',
  (SELECT j->>'status' = 'not_defined' AND j->>'display_he' = 'לא הוגדר' FROM (SELECT rpc_run_daily_budget_summary(t_u('cB'), '2026-08-06 09:30+03') j) x));
SELECT setting_key FROM rpc_put_agent_setting(t_u('cB'), 'daily_summary_time', NULL, '09:00');
SELECT t_assert('v3-T9: no budget for the month → no_budget ("לא הוגדר")',
  (SELECT rpc_run_daily_budget_summary(t_u('cB'), '2026-07-06 09:30+03')->>'status' = 'no_budget'));
SELECT budget_month FROM rpc_everstore_budget_set(t_u('cB'), '2026-08-01', 100);
SELECT budget_month FROM rpc_everstore_budget_set(t_u('cB'), '2026-09-01', 100);
RESET ROLE;
SELECT t_buy('empB3', 'concert_pass', '2026-08-05 10:00+03', 50);
SELECT t_as(t_u('cfoB'));
SET ROLE authenticated;
SELECT t_assert('v3-T10: before the company-local summary time (08:30 Jerusalem) → not_yet',
  (SELECT rpc_run_daily_budget_summary(t_u('cB'), '2026-08-05 08:30+03')->>'status' = 'not_yet'));
SELECT t_assert('v3-T9: day without a threshold crossing (50%) → no summary row',
  (SELECT rpc_run_daily_budget_summary(t_u('cB'), '2026-08-06 09:30+03')->>'status' = 'no_crossing'));
RESET ROLE;
SELECT t_assert('v3-T9: …and nothing stored', NOT EXISTS (SELECT 1 FROM agent_daily_summaries WHERE company_id = t_u('cB')));
SELECT t_buy('empB3', 'spa_massage', '2026-08-06 12:00+03', 45);
SELECT t_as(t_u('cfoB'));
SET ROLE authenticated;
INSERT INTO t_outputs SELECT 'daily_created', rpc_run_daily_budget_summary(t_u('cB'), '2026-08-07 09:30+03');
SELECT t_assert('v3-T9: a second run that day → exists (no second summary)',
  (SELECT rpc_run_daily_budget_summary(t_u('cB'), '2026-08-07 18:00+03')->>'status' = 'exists'));
SELECT t_assert('v3-T9: next day, thresholds already reported this month → no_crossing',
  (SELECT rpc_run_daily_budget_summary(t_u('cB'), '2026-08-08 09:30+03')->>'status' = 'no_crossing'));
INSERT INTO t_outputs SELECT 'daily_get', rpc_get_daily_budget_summary(t_u('cB'), '2026-08-07');
SELECT t_assert('v3-T9: GET daily-summary for that date → sent; another date → none',
  (SELECT rpc_get_daily_budget_summary(t_u('cB'), '2026-08-07')->>'status' = 'sent')
  AND (SELECT rpc_get_daily_budget_summary(t_u('cB'), '2026-08-08')->>'status' = 'none'));
RESET ROLE;
SELECT t_assert('v3-T9: a day crossing two thresholds (75 % and 90 %, at 95 %) → ONE summary listing both; linear forecast 95 ÷ 7 days × 31 = 420.71 %',
  (SELECT count(*) = 1 AND min(thresholds_crossed) = '{75,90}' AND min(utilization_pct) = 95 AND min(forecast_pct) = 420.71
     FROM agent_daily_summaries WHERE company_id = t_u('cB')));
SELECT t_as(t_u('empB1'));
SET ROLE authenticated;
SELECT t_expect_http('v3-T9: employee → 403 on the daily summary', $$SELECT rpc_get_daily_budget_summary(t_u('cB'), '2026-08-07')$$, 'insufficient_privilege', 403);
RESET ROLE;
-- Two timezones: B = Asia/Jerusalem (companies.timezone); C = Europe/London overridden by company_timezone America/New_York.
SELECT t_as(t_u('cfoC'));
SET ROLE authenticated;
SELECT setting_key FROM rpc_put_agent_setting(t_u('cC'), 'company_timezone', NULL, 'America/New_York');
SELECT setting_key FROM rpc_put_agent_setting(t_u('cC'), 'daily_summary_time', NULL, '09:00');
SELECT budget_month FROM rpc_everstore_budget_set(t_u('cC'), '2026-08-01', 100);
RESET ROLE;
SELECT t_assert('v3-T10: one instant (2026-08-31 22:30 UTC) is September in Jerusalem and August in New York (agent setting beats companies.timezone)',
  fn_agent_month_start(t_u('cB'), '2026-08-31 22:30+00') = DATE '2026-09-01'
  AND fn_agent_month_start(t_u('cC'), '2026-08-31 22:30+00') = DATE '2026-08-01'
  AND fn_agent_company_tz(t_u('cC')) = 'America/New_York');
SELECT t_buy('empB2', 'concert_pass', '2026-08-31 22:30+00', 80);
SELECT t_buy('empC1', 'concert_pass', '2026-08-31 22:30+00', 80);
SELECT t_as(t_u('cfoB'));
SET ROLE authenticated;
SELECT t_assert('v3-T10: Jerusalem — the purchase counts in the September budget (80 %, threshold 75 crossed, budget_month 2026-09)',
  (SELECT j->>'status' = 'created' AND j->>'budget_month' = '2026-09-01' AND j->'thresholds_crossed' = '[75]'::jsonb
     FROM (SELECT rpc_run_daily_budget_summary(t_u('cB'), '2026-09-01 06:30+00') j) x));
SELECT t_assert('v3-T10: Jerusalem 09:30 local (06:30 UTC) is past the 09:00 summary time',
  (SELECT rpc_run_daily_budget_summary(t_u('cB'), '2026-09-02 06:30+00')->>'status' = 'no_crossing'));
RESET ROLE;
SELECT t_as(t_u('cfoC'));
SET ROLE authenticated;
SELECT t_assert('v3-T10: New York — the same purchase counts in the August budget (budget_month 2026-08)',
  (SELECT j->>'status' = 'created' AND j->>'budget_month' = '2026-08-01' AND j->>'local_date' = '2026-08-31'
     FROM (SELECT rpc_run_daily_budget_summary(t_u('cC'), '2026-08-31 23:30+00') j) x));
SELECT t_assert('v3-T10: the same instant 06:30 UTC is 02:30 in New York → not_yet',
  (SELECT rpc_run_daily_budget_summary(t_u('cC'), '2026-09-02 06:30+00')->>'status' = 'not_yet'));
RESET ROLE;
SELECT t_assert('v3-T10: B August budget unaffected by the 31.08 UTC purchase (still 95 spent in August)',
  (SELECT spent = 95 FROM fn_everstore_budget_state(t_u('cB'), '2026-08-31 20:00+00')));

-- ============ 7. v3-T17 · score range gate ============
SELECT t_as(t_u('cfoA'));
SET ROLE authenticated;
SELECT t_assert('v3-T17: margin_of_error(70, r = 0.5) = 12.5 × 0.5 = 6.25 (range 63.75–76.25)',
  (SELECT margin = 6.25 AND range_low = 63.75 AND range_high = 76.25 FROM rpc_margin_of_error(70, 0.5)));
SELECT t_assert('v3-T17: overlapping ranges (70 vs 65 at r = 0.5) → can_compare false + "אין הבדל שאפשר לקבוע"',
  (SELECT NOT comparable AND display_he = 'אין הבדל שאפשר לקבוע' AND required_gap = 12.5 FROM rpc_can_compare(70, 0.5, 65, 0.5)));
SELECT t_assert('v3-T17: separate ranges (80 vs 60 at r = 1) → comparable, no text',
  (SELECT comparable AND display_he IS NULL FROM rpc_can_compare(80, 1, 60, 1)));
SELECT t_expect_http('v3-T17: r outside 0–1 → 400', $$SELECT * FROM rpc_margin_of_error(70, 1.5)$$, 'invalid_response_rate', 400);
INSERT INTO t_outputs SELECT 'margin', jsonb_agg(to_jsonb(m)) FROM rpc_margin_of_error(70, 0.5) m;
INSERT INTO t_outputs SELECT 'can_compare', jsonb_agg(to_jsonb(c)) FROM rpc_can_compare(70, 0.5, 65, 0.5) c;
INSERT INTO t_outputs SELECT 'summary_view', jsonb_agg(to_jsonb(v)) FROM everstore_budget_summary_v v;
SELECT setting_key FROM rpc_put_agent_setting(t_u('cA'), 'score_range_coefficient', 10);
SELECT t_assert('v3-T17: the coefficient is read from agent_settings (company override 10 → margin 5)',
  (SELECT margin = 5 FROM rpc_margin_of_error(70, 0.5)));
SELECT setting_key FROM rpc_put_agent_setting(t_u('cA'), 'score_range_coefficient');
RESET ROLE;

-- ============ 8. Agent 2 · burnout forecast (v3-T1, T2, T3, T4, T11; Karin 5th signal) ============
DO $$
DECLARE i int; m date;
BEGIN
  -- PCQ-12 history: BIG 12 reporters Jun–Sep at 70, October at 60; SEVEN 7, NINE 9, THREE 3 in October at 70
  FOREACH m IN ARRAY ARRAY[DATE '2026-06-05', '2026-07-05', '2026-08-05', '2026-09-05'] LOOP
    FOR i IN 1..12 LOOP PERFORM t_pcq('big' || i, m, 70); END LOOP;
  END LOOP;
  FOR i IN 1..12 LOOP PERFORM t_pcq('big' || i, DATE '2026-10-05', 60); END LOOP;
  FOR i IN 1..7 LOOP PERFORM t_pcq('seven' || i, DATE '2026-10-05', 70); END LOOP;
  FOR i IN 1..9 LOOP PERFORM t_pcq('nine' || i, DATE '2026-10-05', 70); PERFORM t_pcq('nine' || i, DATE '2026-04-05', 70); END LOOP;
  FOR i IN 1..3 LOOP PERFORM t_pcq('three' || i, DATE '2026-10-05', 70); END LOOP;
END $$;
SELECT t_as(t_u('hrA'));
SET ROLE authenticated;
-- Team movements (aggregate counts only): BIG 1 event in Aug, Sep, Oct; BIG 1 in Jan; NINE 3 in Feb, Mar, Apr
SELECT rpc_put_team_movements(t_u('cA'), 'BIG', '2026-08-01', 1, 0);
SELECT rpc_put_team_movements(t_u('cA'), 'BIG', '2026-09-01', 0, 1);
SELECT rpc_put_team_movements(t_u('cA'), 'BIG', '2026-10-01', 1, 0);
SELECT rpc_put_team_movements(t_u('cA'), 'BIG', '2026-01-01', 1, 0);
SELECT rpc_put_team_movements(t_u('cA'), 'NINE', '2026-02-01', 2, 1);
SELECT rpc_put_team_movements(t_u('cA'), 'NINE', '2026-03-01', 2, 1);
SELECT rpc_put_team_movements(t_u('cA'), 'NINE', '2026-04-01', 2, 1);
SELECT t_expect_http('movements: negative count → 400', $$SELECT rpc_put_team_movements(t_u('cA'), 'BIG', '2026-10-01', -1, 0)$$, 'invalid_amount', 400);
INSERT INTO t_outputs SELECT 'trend_big_oct', rpc_get_burnout_trend(t_u('cA'), 'BIG', '2026-10-01');
INSERT INTO t_outputs SELECT 'trend_big_sep', rpc_get_burnout_trend(t_u('cA'), 'BIG', '2026-09-01');
INSERT INTO t_outputs SELECT 'trend_seven', rpc_get_burnout_trend(t_u('cA'), 'SEVEN', '2026-10-01');
INSERT INTO t_outputs SELECT 'trend_nine_oct', rpc_get_burnout_trend(t_u('cA'), 'NINE', '2026-10-01');
INSERT INTO t_outputs SELECT 'trend_nine_apr', rpc_get_burnout_trend(t_u('cA'), 'NINE', '2026-04-01');
INSERT INTO t_outputs SELECT 'trend_three', rpc_get_burnout_trend(t_u('cA'), 'THREE', '2026-10-01');
RESET ROLE;
SELECT t_assert('5th signal (Karin): BIG October — 3 events ÷ 12 = 0.25 ≥ 1.5 × org 3 ÷ 56, ≥ 2 events, team 12 → alert',
  (SELECT (j->>'alert')::boolean AND (j->>'team_rate')::numeric = 0.25 AND (j->>'organization_rate')::numeric = round(3::numeric / 56, 4)
     FROM (SELECT fn_movement_period(t_u('cA'), 'BIG', '2026-10-01') j) x));
SELECT t_assert('5th signal (Karin): no alert below 2 events — BIG January: 1 event (rate 1/12 ≥ 1.5 × org) → alert false, enough_events false',
  (SELECT NOT (j->>'alert')::boolean AND NOT (j->>'enough_events')::boolean
          AND (j->>'team_rate')::numeric >= 1.5 * (j->>'organization_rate')::numeric
     FROM (SELECT fn_movement_period(t_u('cA'), 'BIG', '2026-01-01') j) x));
SELECT t_assert('5th signal (Karin): no alert for a team below 10 employees — NINE April: 9 events ÷ 9 (rate and events pass) → alert false',
  (SELECT NOT (j->>'alert')::boolean AND NOT (j->>'team_size_ok')::boolean AND (j->>'enough_events')::boolean
          AND (j->>'team_rate')::numeric >= 1.5 * (j->>'organization_rate')::numeric
     FROM (SELECT fn_movement_period(t_u('cA'), 'NINE', '2026-04-01') j) x));
SELECT t_assert('5th signal (Karin): rate below 1.5 × org → no alert (company-wide group = the org itself)',
  (SELECT NOT (fn_movement_period(t_u('cA'), NULL, '2026-10-01')->>'alert')::boolean));
SELECT t_assert('5th signal (Karin): both conditions in 2 consecutive periods (Sep + Oct) → BIG October "סיכון עולה"',
  (SELECT j->'signals'->'team_movements'->'shown' = 'true'::jsonb
          AND j->'signals'->'team_movements'->'crossed_last_periods' = '[true, true]'::jsonb
          AND (j->>'rising_risk')::boolean AND j->>'rising_risk_label_he' = 'סיכון עולה'
     FROM t_outputs WHERE label = 'trend_big_oct'));
SELECT t_assert('v3-T3: one crossing period only (Aug has 1 event, Sep crosses) → BIG September NOT rising',
  (SELECT j->'signals'->'team_movements'->'crossed_last_periods' = '[false, true]'::jsonb AND NOT (j->>'rising_risk')::boolean
          AND j->'rising_risk_label_he' = 'null'::jsonb
     FROM t_outputs WHERE label = 'trend_big_sep'));
SELECT t_assert('v1.6.19 A4: rising risk → the only recommendation "לבדוק את תנאי העבודה בצוות" (טיוטה)',
  (SELECT j->>'recommendation_he' = 'לבדוק את תנאי העבודה בצוות' AND j->>'recommendation_text_status' = 'טיוטה'
     FROM t_outputs WHERE label = 'trend_big_oct'));
SELECT t_assert('v1.6.19 A4: not rising → no recommendation',
  (SELECT j->'recommendation_he' = 'null'::jsonb FROM t_outputs WHERE label = 'trend_big_sep'));
SELECT t_assert('5th signal (Karin): no display below 10 employees — NINE (9 employees) gets no movement figures',
  (SELECT bool_and(j->'signals'->'team_movements'->'shown' = 'false'::jsonb
                   AND NOT (j->'signals'->'team_movements' ? 'team_rate')
                   AND j->'signals'->'team_movements'->>'display_he' LIKE 'לא מוצג: מדד רגיש%10%')
     FROM t_outputs WHERE label IN ('trend_nine_oct', 'trend_nine_apr')));
SELECT t_assert('v3-T3: fn_burnout_signal — rise in the last period only (10,10,10,10,20) → not rising',
  (SELECT NOT (j->>'rising')::boolean AND j->'crossed_last_periods' = '[false, true]'::jsonb
     FROM (SELECT fn_burnout_signal(t_u('cA'), 'rise', ARRAY[10,10,10,10,20]::numeric[], 3, 2, 15) j) x));
SELECT t_assert('v3-T3: fn_burnout_signal — rise in 2 consecutive periods of the 3-month MA (10,10,10,20,30) → rising',
  (SELECT (j->>'rising')::boolean FROM (SELECT fn_burnout_signal(t_u('cA'), 'rise', ARRAY[10,10,10,20,30]::numeric[], 3, 2, 15) j) x));
SELECT t_assert('v3-T4: PCQ-12 drop ≥ 10 % in both periods but the first (12 %, 12 points) is inside the two ranges (r = 0.5 → 12.5) → not rising',
  (SELECT NOT (j->>'rising')::boolean
     FROM (SELECT fn_burnout_signal(t_u('cA'), 'drop', ARRAY[100,100,100,64,40]::numeric[], 3, 2, 10,
                                    ARRAY[5,5,5,5,5], ARRAY[10,10,10,10,10]) j) x));
SELECT t_assert('v3-T4: same drop with full reporting (r = 1, range 0) → rising (the range is the only difference)',
  (SELECT (j->>'rising')::boolean
     FROM (SELECT fn_burnout_signal(t_u('cA'), 'drop', ARRAY[100,100,100,64,40]::numeric[], 3, 2, 10,
                                    ARRAY[10,10,10,10,10], ARRAY[10,10,10,10,10]) j) x));
SELECT t_assert('v3-T11: team with 7 מדווחים בפועל → partial, "מגמה חלקית" and the §4.4 texts',
  (SELECT j->>'coverage' = 'partial' AND j->>'card_label_he' = 'מגמה חלקית'
          AND j->>'how_calculated_he' = 'המגמה חלקית. היא מבוססת רק על PCQ-12 והיעדרויות, כי יש בקבוצה פחות מ-10 מדווחים בפועל.'
          AND j->>'how_calculated_short_he' = 'המגמה חלקית: מבוססת רק על PCQ-12 והיעדרויות.'
          AND j->'signals'->'deprivation_tax'->>'display_he' = 'אין מספיק מדווחים בפועל להצגה'
          AND j->'signals'->'happiness_debt'->>'display_he' = 'אין מספיק מדווחים בפועל להצגה'
          AND j->'signals' ? 'pcq12' AND j->'signals' ? 'absences'
          AND (j->>'reporters_count')::int = 7
     FROM t_outputs WHERE label = 'trend_seven'));
SELECT t_assert('v3 §4.4: fewer than 5 מדווחים בפועל → none, the whole card says "אין מספיק מדווחים בפועל להצגה" (no signals)',
  (SELECT j->>'coverage' = 'none' AND j->>'display_he' = 'אין מספיק מדווחים בפועל להצגה' AND NOT (j ? 'signals') AND NOT (j ? 'reporters_count')
     FROM t_outputs WHERE label = 'trend_three'));
SELECT t_assert('get_burnout_trend: full coverage (12) returns response_rate, margin, comparable (v3 §6.4 fields)',
  (SELECT j->>'coverage' = 'full' AND (j->>'response_rate')::numeric = 1 AND (j->>'margin')::numeric = 0 AND j ? 'comparable'
     FROM t_outputs WHERE label = 'trend_big_oct'));
SELECT t_assert('v3-T2 + r3: absences only as one aggregate team figure (aggregate_only), only from 5 מדווחים בפועל; no input yet → "חסר: team_absence_input", skipped',
  (SELECT (j->'signals'->'absences'->>'aggregate_only')::boolean
          AND j->'signals'->'absences'->>'display_he' = 'חסר: team_absence_input'
          AND NOT (j->'signals'->'absences'->>'used_in_risk')::boolean AND NOT (j->'signals'->'absences') ? 'days'
     FROM t_outputs WHERE label = 'trend_seven')
  AND (SELECT NOT (j::text LIKE '%absences%') FROM t_outputs WHERE label = 'trend_three')
  AND (SELECT bool_and(NOT (j::text LIKE '%approved_absences%')) FROM t_outputs WHERE label LIKE 'trend_%'));
SELECT t_assert('r3 (J-80 = A): a missing absence input does not stop the agent — partial SEVEN still has its PCQ-12 signal, and BIG October is still "סיכון עולה" from the 5th signal',
  (SELECT j->>'coverage' = 'partial' AND j->'signals'->'pcq12' ? 'moving_average' FROM t_outputs WHERE label = 'trend_seven')
  AND (SELECT (j->>'rising_risk')::boolean AND j->'signals'->'absences'->>'display_he' = 'חסר: team_absence_input'
         FROM t_outputs WHERE label = 'trend_big_oct'));
SELECT t_assert('v3-T1: Agent 2 never reads the 12-spoons data (no spoon_budget / spoon columns in its functions)',
  NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname IN ('rpc_get_burnout_trend', 'fn_team_month_members', 'fn_team_month_pcq',
                                                      'fn_team_month_absences', 'fn_team_month_tax_debt', 'fn_burnout_signal',
                                                      'fn_team_absence_days', 'fn_team_absence_signal',
                                                      'fn_movement_events', 'fn_movement_period', 'fn_ma', 'fn_pooled_rate',
                                                      'fn_may_read_team_agent')
                 AND prosrc ~* '(spoon_budget|current_spoon_count|team_spoon_avg|spoons_company_avg|spoon_reporter)'));
DO $$
DECLARE i int;
BEGIN
  FOR i IN 1..12 LOOP
    INSERT INTO spoon_budget (user_id, budget_date, current_spoon_count, reported_at)
    VALUES (t_u('big' || i), DATE '2026-10-12', 2, '2026-10-12 09:00+03') ON CONFLICT DO NOTHING;
  END LOOP;
END $$;
SELECT t_as(t_u('hrA'));
SET ROLE authenticated;
SELECT t_assert('v3-T1: …and its output is identical after 12 low spoon reports in the team',
  (SELECT rpc_get_burnout_trend(t_u('cA'), 'BIG', '2026-10-01') = j FROM t_outputs WHERE label = 'trend_big_oct'));
RESET ROLE;
SELECT t_as(t_u('mgrA'));
SET ROLE authenticated;
SELECT t_assert('burnout access: the manager of BIG reads BIG', (SELECT rpc_get_burnout_trend(t_u('cA'), 'BIG', '2026-10-01')->>'coverage' = 'full'));
SELECT t_expect_http('burnout access: …but not a team outside the subtree (SEVEN) → 403', $$SELECT rpc_get_burnout_trend(t_u('cA'), 'SEVEN', '2026-10-01')$$, 'insufficient_privilege', 403);
RESET ROLE;
SELECT t_as(t_u('big1'));
SET ROLE authenticated;
SELECT t_expect_http('burnout access: employee → 403', $$SELECT rpc_get_burnout_trend(t_u('cA'), 'BIG', '2026-10-01')$$, 'insufficient_privilege', 403);
SELECT t_expect_http('movements input: employee → 403', $$SELECT rpc_put_team_movements(t_u('cA'), 'BIG', '2026-10-01', 9, 9)$$, 'insufficient_privilege', 403);
RESET ROLE;
SELECT t_assert('team_movements: group counts only (no person / user / name column), RLS forced, closed to clients',
  NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'team_movements' AND column_name ~* '(person|user|name|pseudonym)')
  AND NOT has_table_privilege('authenticated', 'team_movements', 'SELECT'));

-- ============ 8b. v1.6.19-r3 (Karin 31.10, J-80 = A) · burnout absences = team input (sick + unplanned + unapproved early leave) ============
-- System rows that must NOT count: approved absence / refresh entries (incl. a time benefit) and pre-approved early leave.
INSERT INTO approved_absence_entry (user_id, company_id, requested_date, schedule_status)
SELECT t_u('big' || i), t_u('cA'), DATE '2026-10-12', 'coordinated' FROM generate_series(1, 4) i;
INSERT INTO early_leave_log (user_id, local_date) SELECT t_u('big' || i), DATE '2026-10-13' FROM generate_series(5, 7) i;
SELECT t_as(t_u('hrA'));
SET ROLE authenticated;
INSERT INTO t_outputs SELECT 'trend_big_sys_only', rpc_get_burnout_trend(t_u('cA'), 'BIG', '2026-10-01');
RESET ROLE;
SELECT t_assert('r3: approved absences / time benefits (4) and pre-approved early leave (3) exist for BIG in October but are NOT counted → still "חסר"',
  fn_team_month_absences(t_u('cA'), 'BIG', '2026-10-01') = 7
  AND (SELECT j->'signals'->'absences'->>'display_he' = 'חסר: team_absence_input' FROM t_outputs WHERE label = 'trend_big_sys_only'));
-- vp_hr enters TOTAL days per team month: Jun–Aug 10, Sep 20, Oct 30 (sick 20 + unplanned 6 + unapproved early leave 4).
SELECT t_as(t_u('hrA'));
SET ROLE authenticated;
INSERT INTO t_outputs SELECT 'team_abs_put', rpc_put_team_absences(t_u('cA'), 'BIG', '2026-10-01', 20, 6, 4);
SELECT jsonb_typeof(rpc_put_team_absences(t_u('cA'), 'BIG', m, 8, 2, 0)) AS earlier
  FROM unnest(ARRAY[DATE '2026-06-01', '2026-07-01', '2026-08-01']) m;
SELECT jsonb_typeof(rpc_put_team_absences(t_u('cA'), 'BIG', '2026-09-15', 12, 4, 4)) AS sep;
SELECT t_expect_http('r3: negative days → 400 invalid_amount', $$SELECT rpc_put_team_absences(t_u('cA'), 'BIG', '2026-10-01', -1, 0, 0)$$, 'invalid_amount', 400);
SELECT t_expect_http('r3: two decimals → 400 invalid_amount', $$SELECT rpc_put_team_absences(t_u('cA'), 'BIG', '2026-10-01', 1.25, 0, 0)$$, 'invalid_amount', 400);
SELECT t_expect_http('r3: more days than team size × days of the month (12 × 31 = 372) → 400 invalid_amount', $$SELECT rpc_put_team_absences(t_u('cA'), 'BIG', '2026-10-01', 300, 70, 3)$$, 'invalid_amount', 400);
SELECT t_expect_http('r3: a team with no active employee → 400 invalid_team', $$SELECT rpc_put_team_absences(t_u('cA'), 'NOPE', '2026-10-01', 1, 0, 0)$$, 'invalid_team', 400);
SELECT t_expect_http('r3: a missing value is not 0 → 400 invalid_amount', $$SELECT rpc_put_team_absences(t_u('cA'), 'BIG', '2026-10-01', 1, NULL, 0)$$, 'invalid_amount', 400);
INSERT INTO t_outputs SELECT 'trend_big_abs', rpc_get_burnout_trend(t_u('cA'), 'BIG', '2026-10-01');
INSERT INTO t_outputs SELECT 'trend_seven_abs', rpc_get_burnout_trend(t_u('cA'), 'SEVEN', '2026-10-01');
RESET ROLE;
SELECT t_assert('r3: BIG October absences = 30 days = sick 20 + unplanned 6 + unapproved early leave 4 (the 7 system rows not added)',
  (SELECT (j->'signals'->'absences'->>'days')::numeric = 30 AND (j->'signals'->'absences'->>'used_in_risk')::boolean
          AND (j->'signals'->'absences'->>'aggregate_only')::boolean
          AND j->'signals'->'absences'->>'definition_he' = fn_absence_definition_he()
          AND NOT (j->'signals'->'absences') ? 'text_status' AND (j->'signals'->'absences')::text !~ 'טיוטה'   -- J-88 approved
     FROM t_outputs WHERE label = 'trend_big_abs')
  AND fn_team_absence_days(t_u('cA'), 'BIG', '2026-10-01') = 30 AND fn_team_absence_days(t_u('cA'), 'BIG', '2026-09-01') = 20);
SELECT t_assert('r3: the absence term uses the existing rise test — 10, 10, 10, 20, 30 → crosses in 2 consecutive periods → rising',
  (SELECT (j->'signals'->'absences'->>'rising')::boolean AND j->'signals'->'absences'->'crossed_last_periods' = '[true, true]'::jsonb
     FROM t_outputs WHERE label = 'trend_big_abs'));
SELECT t_assert('r3: the other signals are unchanged by the absence input (PCQ-12, מס קיפוח, Happiness Debt, 5th signal identical to the run without it)',
  (SELECT a.j->'signals'->'pcq12' = b.j->'signals'->'pcq12' AND a.j->'signals'->'deprivation_tax' = b.j->'signals'->'deprivation_tax'
          AND a.j->'signals'->'happiness_debt' = b.j->'signals'->'happiness_debt'
          AND a.j->'signals'->'team_movements' = b.j->'signals'->'team_movements'
     FROM t_outputs a, t_outputs b WHERE a.label = 'trend_big_abs' AND b.label = 'trend_big_oct'));
SELECT t_assert('r3: a team without its month input (SEVEN) keeps "חסר" while BIG has data — per team, per month',
  (SELECT j->'signals'->'absences'->>'display_he' = 'חסר: team_absence_input' FROM t_outputs WHERE label = 'trend_seven_abs'));
SELECT t_assert('r3: the input is audited (team + month only, no person) and its output is team + month + status',
  (SELECT count(*) = 5 AND bool_and(t_ids_free(a.scope) AND a.subject_user_id IS NULL AND a.viewer_id = t_u('hrA')
                                    AND a.scope ? 'team' AND NOT a.scope ? 'sickness_days')
     FROM access_audit_log a WHERE a.action = 'team_absences_put')
  AND (SELECT j = jsonb_build_object('team', 'BIG', 'period_month', DATE '2026-10-01', 'status', 'saved') FROM t_outputs WHERE label = 'team_abs_put'));
SELECT t_as(t_u('cfoA'));
SET ROLE authenticated;
SELECT t_expect_http('r3: cfo → 403 on the team absences input (vp_hr only)', $$SELECT rpc_put_team_absences(t_u('cA'), 'BIG', '2026-10-01', 1, 0, 0)$$, 'insufficient_privilege', 403);
RESET ROLE;
SELECT t_as(t_u('mgrA'));
SET ROLE authenticated;
SELECT t_expect_http('r3: manager → 403 on the team absences input', $$SELECT rpc_put_team_absences(t_u('cA'), 'BIG', '2026-10-01', 1, 0, 0)$$, 'insufficient_privilege', 403);
RESET ROLE;
SELECT t_as(t_u('big1'));
SET ROLE authenticated;
SELECT t_expect_http('r3: employee → 403 on the team absences input', $$SELECT rpc_put_team_absences(t_u('cA'), 'BIG', '2026-10-01', 1, 0, 0)$$, 'insufficient_privilege', 403);
RESET ROLE;
SELECT t_expect_http('r3: service call (no caller) → 403 on the team absences input', $$SELECT rpc_put_team_absences(t_u('cA'), 'BIG', '2026-10-01', 1, 0, 0)$$, 'insufficient_privilege', 403);
SELECT t_assert('r3: team_absence_input is closed (RLS forced, no client grant) and has no person / user / employee / name column',
  NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'team_absence_input' AND column_name ~* '(person|user|employee|pseudonym|name|email)')
  AND NOT has_table_privilege('authenticated', 'team_absence_input', 'SELECT')
  AND (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid = 'team_absence_input'::regclass));
SELECT t_assert('r3 catalog: NO table and NO function accepts absence / sick days next to a person (no person_id / user_id / employee id / name / e-mail column or argument beside absence-day count fields)',
  NOT EXISTS (SELECT 1 FROM information_schema.columns d JOIN information_schema.columns p
                ON p.table_schema = d.table_schema AND p.table_name = d.table_name
               WHERE d.table_schema = 'public' AND d.column_name ~* '(sick|unplanned|absence_days|absent_days|early_leave_days)'
                 AND d.data_type IN ('numeric', 'integer', 'smallint', 'bigint', 'real', 'double precision')
                 AND p.column_name ~* '(person|user|employee|pseudonym|name|email)')
  AND NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid = f.pronamespace
                   WHERE n.nspname = 'public' AND f.proargnames IS NOT NULL
                     AND EXISTS (SELECT 1 FROM unnest(f.proargnames) a WHERE a ~* '(sick|unplanned|absence_days|absent_days|early_leave_days)')
                     AND EXISTS (SELECT 1 FROM unnest(f.proargnames) a WHERE a ~* '(person|user|employee|pseudonym|name|email)'))
  AND (SELECT count(DISTINCT table_name) >= 2 FROM information_schema.columns WHERE table_schema = 'public' AND column_name ~* 'sick')
  AND EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_put_team_absences'));
SELECT t_expect_err('r3: the per-employee early-leave flag sick_day_deducted stays locked false (an early leave is never a sick day)',
  $$INSERT INTO early_leave_log (user_id, local_date, sick_day_deducted) VALUES (t_u('big1'), DATE '2026-10-20', true)$$, '23514');
SELECT t_assert('r3: the system absence tables carry no sick-day field (approved_absence_entry / early_leave_log are never sick days)',
  NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name IN ('approved_absence_entry', 'early_leave_log')
               AND column_name ~* '(sick_days|unplanned|absence_days)'));
SELECT t_assert('r3: the burnout agent no longer reads the old system absence count',
  (SELECT prosrc !~ 'fn_team_month_absences' AND prosrc ~ 'fn_team_absence_days' FROM pg_proc WHERE proname = 'rpc_get_burnout_trend'));
SELECT t_assert('r3: B_t is unchanged (0.41·S + 0.37·O + 0.22·D, no absence term): B_t(5, 10, 1) = 0.78, B_t(1, 10, 1) = 0.37',
  fn_b_t(5, 10, 1) = 0.78 AND fn_b_t(1, 10, 1) = 0.37 AND fn_b_t(3, 5, 3) = 0.5);

-- ============ 9. v3-T13 · Happiness Debt on exit → memo line "יצא עם העוזבים" ============
INSERT INTO employee_value_asset (user_id, company_id, annual_salary) VALUES (t_u('leaverA'), t_u('cA'), 100000);
UPDATE employee_value_asset SET happiness_debt_liability = 50000 WHERE user_id = t_u('leaverA');
UPDATE users SET employment_ended_at = '2026-10-10 12:00+03' WHERE user_id = t_u('leaverA');
SELECT t_assert('v3-T13: leaving writes a leaver_transfer event (50,000, team REST, 2026-10) — no person column',
  (SELECT count(*) = 1 AND sum(amount) = 50000 AND min(group_id) = 'REST' AND min(period_month) = DATE '2026-10-01'
     FROM happiness_debt_events WHERE company_id = t_u('cA') AND event_type = 'leaver_transfer')
  AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'happiness_debt_events' AND column_name ~* '(person|user|employee)'));
SELECT t_assert('v3-T13: …and an exported_on_exit ledger row (not part of the 4-line split)',
  (SELECT count(*) = 1 AND sum(amount) = 50000 FROM happiness_debt_ledger WHERE company_id = t_u('cA') AND exported_on_exit));
SELECT t_assert('v3-T13: the debt is NOT deleted (employee_value_asset still 50,000)',
  (SELECT happiness_debt_liability = 50000 FROM employee_value_asset WHERE user_id = t_u('leaverA')));
SELECT t_assert('v3-T13: memo line through October = 50,000', fn_leaver_memo(t_u('cA'), '2026-10-01') = 50000);
SELECT t_as(t_u('cfoA'));
SET ROLE authenticated;
SELECT t_assert('remediation: a documented fix (what, when, who approved, amount) reduces the memo line (50,000 − 20,000)',
  rpc_record_remediation(t_u('cA'), 'REST', '2026-10-20', 'הקטנת עומס משמרות', 20000) = fn_remediation_response());
SELECT t_expect_http('remediation: missing description → 400', $$SELECT rpc_record_remediation(t_u('cA'), 'REST', '2026-10-20', ' ', 1)$$, 'invalid_remediation', 400);
RESET ROLE;
SELECT t_assert('remediation: memo line = 30,000; remediation_records keeps who approved (cfo)',
  fn_leaver_memo(t_u('cA'), '2026-10-01') = 30000
  AND (SELECT approved_by = t_u('cfoA') FROM remediation_records WHERE company_id = t_u('cA')));
SELECT t_expect_err('happiness_debt_events is WORM', $$DELETE FROM happiness_debt_events$$, 'ledger_immutable');
SELECT t_expect_err('remediation_records is WORM', $$UPDATE remediation_records SET reduction_amount = 1$$, 'ledger_immutable');
SELECT t_assert('v1.6.18 A-12: the team-level remediation was attributed to the team''s open transfer (leaverA''s, 20,000; open balance 30,000)',
  (SELECT count(*) = 1 AND sum(a.amount) = 20000 AND bool_and(fn_transfer_open_balance(a.transfer_event_id) = 30000)
     FROM happiness_debt_remediation_allocation a JOIN happiness_debt_leaver_link l ON l.event_id = a.transfer_event_id
    WHERE l.user_id = t_u('leaverA')));

-- ============ 9b. v1.6.17 A-8 · reversed offboarding returns the memo-line debt to the team ============
-- retD (8,000) and otherD (5,000) leave TEAMD 3 days before the run (inside the 30-day reversal window).
INSERT INTO employee_value_asset (user_id, company_id, annual_salary) VALUES (t_u('retD'), t_u('cD'), 100000), (t_u('otherD'), t_u('cD'), 90000);
UPDATE employee_value_asset SET happiness_debt_liability = 8000 WHERE user_id = t_u('retD');
UPDATE employee_value_asset SET happiness_debt_liability = 5000 WHERE user_id = t_u('otherD');
UPDATE users SET employment_ended_at = clock_timestamp() - interval '3 days' WHERE user_id IN (t_u('retD'), t_u('otherD'));
CREATE TEMP TABLE t_a8 AS SELECT fn_agent_month_start(t_u('cD'), clock_timestamp()) AS rev_month, DATE '2100-01-01' AS far;
SELECT t_assert('A-8: two leaver_transfer events for TEAMD (8,000 + 5,000) → memo line "יצא עם העוזבים" 13,000',
  (SELECT count(*) = 2 AND sum(amount) = 13000 AND bool_and(group_id = 'TEAMD') FROM happiness_debt_events
    WHERE company_id = t_u('cD') AND event_type = 'leaver_transfer')
  AND fn_leaver_memo(t_u('cD'), (SELECT far FROM t_a8)) = 13000);
SELECT t_assert('A-8: each transfer has one internal link row (closed table: RLS forced, no client grant)',
  (SELECT count(*) = 2 FROM happiness_debt_leaver_link l JOIN happiness_debt_events e USING (event_id) WHERE e.company_id = t_u('cD'))
  AND NOT has_table_privilege('authenticated', 'happiness_debt_leaver_link', 'SELECT')
  AND NOT has_table_privilege('anon', 'happiness_debt_leaver_link', 'SELECT')
  AND (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid = 'happiness_debt_leaver_link'::regclass));
SELECT t_as(t_u('hrD'));
SET ROLE authenticated;
SELECT t_assert('A-8: the CHRO reverses retD''s offboarding (marked by mistake) inside the 30 days',
  (SELECT employment_ended_at IS NULL FROM rpc_revert_offboarding(t_u('retD'))));
RESET ROLE;
SELECT t_assert('A-8: a documented leaver_reversal event is recorded — TEAMD, 8,000, this company month, linked to retD''s original leaver_transfer',
  (SELECT count(*) = 1 AND sum(r.amount) = 8000 AND min(r.group_id) = 'TEAMD' AND min(r.period_month) = (SELECT rev_month FROM t_a8)
          AND bool_and(t.event_type = 'leaver_transfer' AND t.amount = r.amount
                       AND EXISTS (SELECT 1 FROM happiness_debt_leaver_link l WHERE l.event_id = t.event_id AND l.user_id = t_u('retD')))
     FROM happiness_debt_events r JOIN happiness_debt_events t ON t.event_id = r.reverses_event_id
    WHERE r.company_id = t_u('cD') AND r.event_type = 'leaver_reversal'));
SELECT t_assert('A-8: the memo line decreases by the returned debt (13,000 → 5,000 = otherD only)',
  fn_leaver_memo(t_u('cD'), (SELECT far FROM t_a8)) = 5000);
SELECT t_assert('A-8: the debt is back in the team — retD is an active TEAMD member again with the 8,000 Happiness Debt unchanged, and TEAMD''s net memo share is 5,000',
  (SELECT employment_ended_at IS NULL AND department = 'TEAMD' FROM users WHERE user_id = t_u('retD'))
  AND (SELECT happiness_debt_liability = 8000 FROM employee_value_asset WHERE user_id = t_u('retD'))
  AND (SELECT sum(CASE WHEN event_type = 'leaver_transfer' THEN amount ELSE -amount END) = 5000
         FROM happiness_debt_events WHERE company_id = t_u('cD') AND group_id = 'TEAMD'));
SELECT t_assert('A-8: history kept — both original transfers and the exported_on_exit ledger rows are still there (WORM)',
  (SELECT count(*) = 2 FROM happiness_debt_events WHERE company_id = t_u('cD') AND event_type = 'leaver_transfer')
  AND (SELECT count(*) = 2 FROM happiness_debt_ledger WHERE company_id = t_u('cD') AND exported_on_exit));
-- Idempotency
INSERT INTO t_outputs SELECT 'a8_second_call', fn_reverse_leaver_transfer(t_u('retD'));
SELECT t_assert('A-8 idempotent: calling the reversal again changes nothing (status nothing_to_reverse, still 1 reversal, memo 5,000)',
  (SELECT j->>'status' = 'nothing_to_reverse' FROM t_outputs WHERE label = 'a8_second_call')
  AND (SELECT count(*) = 1 FROM happiness_debt_events WHERE company_id = t_u('cD') AND event_type = 'leaver_reversal')
  AND fn_leaver_memo(t_u('cD'), (SELECT far FROM t_a8)) = 5000);
SELECT t_as(t_u('hrD'));
SET ROLE authenticated;
SELECT t_expect_http('A-8 idempotent: a second rpc_revert_offboarding is refused (already active) → 403', $$SELECT rpc_revert_offboarding(t_u('retD'))$$, 'anti_get_blocked', 403);
RESET ROLE;
SELECT t_expect_err('A-8 idempotent: a second reversal of the same transfer is impossible (unique index)',
  $$INSERT INTO happiness_debt_events (company_id, group_id, period_month, event_type, amount, reverses_event_id)
    SELECT company_id, group_id, period_month, 'leaver_reversal', amount, reverses_event_id FROM happiness_debt_events
     WHERE company_id = t_u('cD') AND event_type = 'leaver_reversal'$$, '23505');
SELECT t_expect_err('A-8: a reversal must point at a transfer (reverses_event_id required)',
  $$INSERT INTO happiness_debt_events (company_id, group_id, period_month, event_type, amount)
    VALUES (t_u('cD'), 'TEAMD', (SELECT rev_month FROM t_a8), 'leaver_reversal', 1)$$, '23514');
INSERT INTO t_outputs SELECT 'a8_still_offboarded', fn_reverse_leaver_transfer(t_u('otherD'));
SELECT t_assert('A-8: an employee who is still offboarded is not reversed (status still_offboarded, memo 5,000)',
  (SELECT j->>'status' = 'still_offboarded' FROM t_outputs WHERE label = 'a8_still_offboarded')
  AND fn_leaver_memo(t_u('cD'), (SELECT far FROM t_a8)) = 5000);
-- Leave again → a NEW transfer; return again through the HR system (direct call) → only the new transfer is reversed.
UPDATE users SET employment_ended_at = clock_timestamp() - interval '1 day' WHERE user_id = t_u('retD');
SELECT t_assert('A-8: leaving again writes a new transfer (memo 13,000)', fn_leaver_memo(t_u('cD'), (SELECT far FROM t_a8)) = 13000);
ALTER TABLE users DISABLE TRIGGER trg_users_leaver_debt_reversal;   -- test only: call the reversal directly to capture its output
UPDATE users SET employment_ended_at = NULL WHERE user_id = t_u('retD');
ALTER TABLE users ENABLE TRIGGER trg_users_leaver_debt_reversal;
INSERT INTO t_outputs SELECT 'a8_reversed', fn_reverse_leaver_transfer(t_u('retD'));
SELECT t_assert('A-8 + v1.6.19: the reversal output is status only (status reversed, label "יצא עם העוזבים") — no amount, team, id or memo value',
  (SELECT j = jsonb_build_object('status', 'reversed', 'label_he', 'יצא עם העוזבים') AND t_ids_free(j)
     FROM t_outputs WHERE label = 'a8_reversed'));
SELECT t_assert('A-8: each of retD''s two transfers is reversed exactly once (2 reversals, 2 distinct targets)',
  (SELECT count(*) = 2 AND count(DISTINCT reverses_event_id) = 2 FROM happiness_debt_events
    WHERE company_id = t_u('cD') AND event_type = 'leaver_reversal'));
SELECT t_assert('A-8 privacy: happiness_debt_events has no person / user / employee / pseudonym column; no A-8 output holds an identifier',
  NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'happiness_debt_events' AND column_name ~* '(person|user|employee|pseudonym)')
  AND (SELECT bool_and(t_ids_free(j)) FROM t_outputs WHERE label LIKE 'a8_%')
  AND (SELECT bool_and(t_ids_free(to_jsonb(e))) FROM happiness_debt_events e WHERE e.company_id = t_u('cD')));
SELECT (fn_crypto_shred_pseudonym_key(t_u('otherD'))).shredded_at IS NOT NULL AS otherd_shredded;
SELECT t_assert('A-8 privacy: crypto-shredding an employee removes the internal leaver link (no reversal possible after that)',
  NOT EXISTS (SELECT 1 FROM happiness_debt_leaver_link WHERE user_id = t_u('otherD'))
  AND fn_leaver_memo(t_u('cD'), (SELECT far FROM t_a8)) = 5000);

-- ============ 9c. A-12 / G-3 (Karin 31.10, v1.6.19-r2) · FIFO remediation, leftover unattributed, reversal per transfer ============
-- Company E: remE (100) and peerE (50) leave TEAME, xE (40) leaves TEAMX, in that order, 2 days before the run.
INSERT INTO employee_value_asset (user_id, company_id, annual_salary) VALUES (t_u('remE'), t_u('cE'), 100000), (t_u('peerE'), t_u('cE'), 100000), (t_u('xE'), t_u('cE'), 100000);
UPDATE employee_value_asset SET happiness_debt_liability = 100 WHERE user_id = t_u('remE');
UPDATE employee_value_asset SET happiness_debt_liability = 50 WHERE user_id = t_u('peerE');
UPDATE employee_value_asset SET happiness_debt_liability = 40 WHERE user_id = t_u('xE');
UPDATE users SET employment_ended_at = clock_timestamp() - interval '2 days' WHERE user_id = t_u('remE');
UPDATE users SET employment_ended_at = clock_timestamp() - interval '2 days' WHERE user_id = t_u('peerE');
UPDATE users SET employment_ended_at = clock_timestamp() - interval '2 days' WHERE user_id = t_u('xE');
CREATE TEMP TABLE t_a12 AS
  SELECT DATE '2100-01-01' AS far, fn_agent_local_ts(t_u('cE'), clock_timestamp())::date AS today,
         (SELECT l.event_id FROM happiness_debt_leaver_link l WHERE l.user_id = t_u('remE')) AS t_rem,
         (SELECT l.event_id FROM happiness_debt_leaver_link l WHERE l.user_id = t_u('peerE')) AS t_peer,
         (SELECT l.event_id FROM happiness_debt_leaver_link l WHERE l.user_id = t_u('xE')) AS t_x;
GRANT SELECT ON t_a12 TO authenticated;
-- Call rpc_record_remediation and roll it back; returns everything the caller could observe (SQLSTATE, message,
-- detail, body) so that responses can be compared byte for byte.
CREATE OR REPLACE FUNCTION t_rem_probe(p_team varchar, p_on date, p_amount numeric) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_detail text;
BEGIN
  RAISE EXCEPTION 'probe' USING DETAIL = rpc_record_remediation(t_u('cE'), p_team, p_on, 'ניסיון', p_amount)::text;
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v_detail = PG_EXCEPTION_DETAIL;
  RETURN SQLSTATE || '|' || SQLERRM || '|' || COALESCE(v_detail, '');
END $$;
GRANT EXECUTE ON FUNCTION t_rem_probe(varchar, date, numeric) TO authenticated;
-- An allocation of a transfer (sum over every remediation of it).
CREATE OR REPLACE FUNCTION t_alloc(p_transfer uuid) RETURNS numeric LANGUAGE sql AS $$
  SELECT COALESCE(sum(a.amount), 0) FROM happiness_debt_remediation_allocation a WHERE a.transfer_event_id = p_transfer
$$;
-- Unattributed remediation amount of company E (remediation events with no allocation row).
CREATE OR REPLACE FUNCTION t_unattributed_e() RETURNS numeric LANGUAGE sql AS $$
  SELECT COALESCE(sum(e.amount), 0) FROM happiness_debt_events e
   WHERE e.company_id = t_u('cE') AND e.event_type = 'remediation'
     AND NOT EXISTS (SELECT 1 FROM happiness_debt_remediation_allocation a WHERE a.remediation_event_id = e.event_id)
$$;
SELECT t_assert('A-12: three transfers (100 + 50 + 40) → memo line "יצא עם העוזבים" 190',
  fn_leaver_memo(t_u('cE'), (SELECT far FROM t_a12)) = 190);
SELECT t_as(t_u('hrE'));
SET ROLE authenticated;
INSERT INTO t_outputs SELECT 'g3_probe_' || k, to_jsonb(t_rem_probe(team, (SELECT today FROM t_a12), amt))
  FROM (VALUES ('lt', 'TEAME', 30), ('eq', 'TEAME', 100), ('gt', 'TEAME', 120), ('gt_all', 'TEAME', 500),
               ('no_transfer', 'NOPE', 5)) v(k, team, amt);
INSERT INTO t_outputs SELECT 'g3_probe_before_months', to_jsonb(t_rem_probe('TEAME', DATE '2026-01-15', 5));
RESET ROLE;
SELECT t_assert('G-3: the response (status, message, body) is identical for amount < balance, = balance, > balance, > all balances, a team with no transfer and a date before every transfer — never 422',
  (SELECT count(DISTINCT j) = 1 AND count(*) = 6 FROM t_outputs WHERE label LIKE 'g3_probe_%')
  AND (SELECT j #>> '{}' = 'P0001|probe|' || fn_remediation_response()::text FROM t_outputs WHERE label = 'g3_probe_gt_all'));
SELECT t_assert('G-3: the response is status only — no amount, balance or count',
  fn_remediation_response() = jsonb_build_object('status', 'recorded', 'label_he', 'יצא עם העוזבים')
  AND t_ids_free(fn_remediation_response()));
SELECT t_assert('G-3: the probes were rolled back (no remediation row, memo still 190)',
  NOT EXISTS (SELECT 1 FROM remediation_records WHERE company_id = t_u('cE')) AND fn_leaver_memo(t_u('cE'), (SELECT far FROM t_a12)) = 190);
SELECT t_as(t_u('hrE'));
SET ROLE authenticated;
SELECT t_assert('A-12: a documented remediation of 30 for TEAME (vp_hr) → the status response',
  rpc_record_remediation(t_u('cE'), 'TEAME', (SELECT today FROM t_a12), 'צמצום שעות נוספות בצוות', 30) = fn_remediation_response());
INSERT INTO t_outputs SELECT 'a12_transfers', jsonb_agg(to_jsonb(x)) FROM rpc_list_leaver_transfers(t_u('cE')) x;
SELECT t_expect_http('v1.6.19: a transfer can no longer be named (the list shows no transfer) → 400 transfer_selection_not_allowed',
  $$SELECT rpc_record_remediation(t_u('cE'), 'TEAME', (SELECT today FROM t_a12), 'ניסיון', 60, (SELECT t_peer FROM t_a12))$$, 'transfer_selection_not_allowed', 400);
SELECT t_expect_http('v1.6.19: …also a transfer of another team → 400 transfer_selection_not_allowed',
  $$SELECT rpc_record_remediation(t_u('cE'), 'TEAME', (SELECT today FROM t_a12), 'ניסיון', 5, (SELECT t_x FROM t_a12))$$, 'transfer_selection_not_allowed', 400);
RESET ROLE;
SELECT t_assert('A-12: 30 (< the oldest balance) → one allocation, to the team''s oldest transfer (remE''s)',
  (SELECT count(*) = 1 AND bool_and(a.transfer_event_id = (SELECT t_rem FROM t_a12) AND a.amount = 30)
     FROM happiness_debt_remediation_allocation a JOIN happiness_debt_events e ON e.event_id = a.remediation_event_id WHERE e.company_id = t_u('cE')));
SELECT t_assert('A-12: per-transfer balances: remE 70, peerE 50, xE 40; memo 160',
  fn_transfer_open_balance((SELECT t_rem FROM t_a12)) = 70 AND fn_transfer_open_balance((SELECT t_peer FROM t_a12)) = 50
  AND fn_transfer_open_balance((SELECT t_x FROM t_a12)) = 40 AND fn_leaver_memo(t_u('cE'), (SELECT far FROM t_a12)) = 160);
SELECT t_assert('v1.6.19: rpc_list_leaver_transfers is aggregate — 3 leavers (< 10) → one company_total row, no batch, no transfer / team amounts',
  (SELECT jsonb_array_length(j) = 1 AND t_ids_free(j) AND j->0->>'row_kind' = 'company_total'
          AND j->0->'transferred' = 'null'::jsonb AND j->0->'open_balance' = 'null'::jsonb
          AND j->0->>'note_he' = 'עדיין לא הצטברו מספיק עוזבים להצגה'
     FROM t_outputs WHERE label = 'a12_transfers'));
-- FIFO across two transfers: 90 > remE's 70 → remE 70 (oldest) + peerE 20, in ONE remediation.
SELECT t_as(t_u('hrE'));
SET ROLE authenticated;
SELECT t_assert('G-3: a remediation of 90 above the oldest balance (70) is accepted with the same response',
  rpc_record_remediation(t_u('cE'), 'TEAME', (SELECT today FROM t_a12), 'שינוי סידור משמרות', 90) = fn_remediation_response());
RESET ROLE;
SELECT t_assert('G-3 FIFO: the 90 is split oldest first — remE 70 + peerE 20 (2 allocation rows of one remediation event); TEAMX untouched',
  (SELECT count(*) = 2 AND count(DISTINCT a.remediation_event_id) = 1 AND sum(a.amount) = 90
          AND sum(a.amount) FILTER (WHERE a.transfer_event_id = (SELECT t_rem FROM t_a12)) = 70
          AND sum(a.amount) FILTER (WHERE a.transfer_event_id = (SELECT t_peer FROM t_a12)) = 20
     FROM happiness_debt_remediation_allocation a
    WHERE a.remediation_event_id = (SELECT e.event_id FROM happiness_debt_events e JOIN remediation_records r ON r.remediation_id = e.remediation_id
                                     WHERE e.company_id = t_u('cE') AND r.reduction_amount = 90))
  AND t_alloc((SELECT t_x FROM t_a12)) = 0 AND t_unattributed_e() = 0);
SELECT t_assert('G-3 FIFO: balances remE 0, peerE 30, xE 40; memo 70',
  fn_transfer_open_balance((SELECT t_rem FROM t_a12)) = 0 AND fn_transfer_open_balance((SELECT t_peer FROM t_a12)) = 30
  AND fn_transfer_open_balance((SELECT t_x FROM t_a12)) = 40 AND fn_leaver_memo(t_u('cE'), (SELECT far FROM t_a12)) = 70);
-- Reversal with split allocations: remE = 100 − 30 − 70 = 0; peerE = 50 − 20 = 30.
SELECT t_as(t_u('hrE'));
SET ROLE authenticated;
SELECT t_assert('A-12: the CHRO reverses remE''s offboarding', (SELECT employment_ended_at IS NULL FROM rpc_revert_offboarding(t_u('remE'))));
RESET ROLE;
SELECT t_assert('A-12 split: remE''s transfer was covered by 2 remediations (30 + 70) → its reversal is 0, recorded, linked to remE''s transfer; memo still 70',
  (SELECT count(*) = 1 AND sum(amount) = 0 AND min(group_id) = 'TEAME' AND bool_and(reverses_event_id = (SELECT t_rem FROM t_a12))
     FROM happiness_debt_events WHERE company_id = t_u('cE') AND event_type = 'leaver_reversal')
  AND t_alloc((SELECT t_rem FROM t_a12)) = 100 AND fn_leaver_memo(t_u('cE'), (SELECT far FROM t_a12)) = 70);
ALTER TABLE users DISABLE TRIGGER trg_users_leaver_debt_reversal;   -- test only: call the reversal directly to capture its output
UPDATE users SET employment_ended_at = NULL WHERE user_id = t_u('peerE');
ALTER TABLE users ENABLE TRIGGER trg_users_leaver_debt_reversal;
INSERT INTO t_outputs SELECT 'a12_reversal_split', fn_reverse_leaver_transfer(t_u('peerE'));
SELECT t_assert('A-12 split: peerE''s reversal = 50 − its own allocation 20 = 30 (not 50, not 50 − 90); output status only',
  (SELECT j = jsonb_build_object('status', 'reversed', 'label_he', 'יצא עם העוזבים') FROM t_outputs WHERE label = 'a12_reversal_split')
  AND (SELECT amount = 30 FROM happiness_debt_events WHERE reverses_event_id = (SELECT t_peer FROM t_a12)));
SELECT t_assert('A-12 split: every TEAME transfer is at 0 — 100 = 100 remediated + 0 returned, 50 = 20 remediated + 30 returned; memo 40 (xE)',
  fn_transfer_open_balance((SELECT t_rem FROM t_a12)) = 0 AND fn_transfer_open_balance((SELECT t_peer FROM t_a12)) = 0
  AND (SELECT fn_transfer_remediated(t_peer) + (SELECT amount FROM happiness_debt_events WHERE reverses_event_id = t_peer) FROM t_a12) = 50
  AND fn_leaver_memo(t_u('cE'), (SELECT far FROM t_a12)) = 40);
INSERT INTO t_outputs SELECT 'a12_second_call', fn_reverse_leaver_transfer(t_u('remE'));
SELECT t_assert('A-12 idempotent: reversing remE again changes nothing (nothing_to_reverse, memo 40)',
  (SELECT j->>'status' = 'nothing_to_reverse' FROM t_outputs WHERE label = 'a12_second_call')
  AND fn_leaver_memo(t_u('cE'), (SELECT far FROM t_a12)) = 40);
-- Leftover: TEAMX 50 > xE's 40 → xE 40 + an unattributed 10; TEAME (no open transfer) 25 → all unattributed.
SELECT t_as(t_u('hrE'));
SET ROLE authenticated;
SELECT t_assert('G-3 leftover: TEAMX 50 (> all its balances) and TEAME 25 (no open transfer) → the same status response',
  rpc_record_remediation(t_u('cE'), 'TEAMX', (SELECT today FROM t_a12), 'הוספת תקן', 50) = fn_remediation_response()
  AND rpc_record_remediation(t_u('cE'), 'TEAME', (SELECT today FROM t_a12), 'הקלה בעומס', 25) = fn_remediation_response());
RESET ROLE;
SELECT t_assert('G-3 leftover: xE gets 40 (balance 0); the 10 leftover and the 25 are team remediations with NO transfer (unattributed 35); TEAME transfers unchanged',
  t_alloc((SELECT t_x FROM t_a12)) = 40 AND fn_transfer_open_balance((SELECT t_x FROM t_a12)) = 0
  AND t_unattributed_e() = 35 AND t_alloc((SELECT t_peer FROM t_a12)) = 20 AND t_alloc((SELECT t_rem FROM t_a12)) = 100
  AND (SELECT count(*) = 2 AND sum(e.amount) = 50 FROM happiness_debt_events e JOIN remediation_records r ON r.remediation_id = e.remediation_id
        WHERE e.company_id = t_u('cE') AND r.reduction_amount = 50)
  AND fn_leaver_memo(t_u('cE'), (SELECT far FROM t_a12)) = 0);
SELECT t_assert('G-3 leftover: the unattributed rows keep their team (TEAMX 10, TEAME 25) and remediation_records keeps the full amounts',
  (SELECT sum(e.amount) FILTER (WHERE e.group_id = 'TEAMX') = 10 AND sum(e.amount) FILTER (WHERE e.group_id = 'TEAME') = 25
     FROM happiness_debt_events e WHERE e.company_id = t_u('cE') AND e.event_type = 'remediation'
      AND NOT EXISTS (SELECT 1 FROM happiness_debt_remediation_allocation a WHERE a.remediation_event_id = e.event_id))
  AND (SELECT sum(reduction_amount) = 195 FROM remediation_records WHERE company_id = t_u('cE')));
SELECT t_assert('A-12: a reversal of 0 is the only zero amount in the events',
  (SELECT count(*) = 1 AND bool_and(event_type = 'leaver_reversal') FROM happiness_debt_events WHERE company_id = t_u('cE') AND amount = 0));
SELECT t_expect_err('A-12: a 0 transfer / remediation event is refused by the CHECK',
  $$INSERT INTO happiness_debt_events (company_id, group_id, period_month, event_type, amount) VALUES (t_u('cE'), 'TEAMX', DATE '2026-10-01', 'leaver_transfer', 0)$$, '23514');
SELECT t_expect_err('A-12: the attribution is WORM', $$UPDATE happiness_debt_remediation_allocation SET amount = 1$$, 'ledger_immutable');
SELECT t_assert('A-12 privacy: the attribution table has no person column and is closed (RLS forced, no client grant)',
  NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'happiness_debt_remediation_allocation' AND column_name ~* '(person|user|employee|pseudonym)')
  AND NOT has_table_privilege('authenticated', 'happiness_debt_remediation_allocation', 'SELECT')
  AND (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid = 'happiness_debt_remediation_allocation'::regclass));
SELECT t_as(t_u('big1'));
SET ROLE authenticated;
SELECT t_expect_http('A-12: an employee cannot list the transfers → 403', $$SELECT * FROM rpc_list_leaver_transfers(t_u('cE'))$$, 'insufficient_privilege', 403);
RESET ROLE;

-- ============ 10. Agent 3 · board report (v3-T14, T15, T16, T18) ============
INSERT INTO shadow_balance_aggregate (org_id, department, contributor_count, deprived_count, deprivation_tax_amount,
                                      happiness_debt_sum, shadow_balance_sum, calculated_at) VALUES
  (t_u('cA'), 'BIG', 12, 3, 12000, 100000, 112000, '2026-09-15 12:00+03'),
  (t_u('cA'), 'BIG', 12, 3, 14400, 120000, 134400, '2026-10-15 12:00+03');
SELECT t_as(t_u('cfoA'));
SET ROLE authenticated;
SELECT t_expect_http('v3-T18: no reconciliation table → the report is not published (422 reconciliation_missing)',
  $$SELECT rpc_build_board_report(t_u('cA'), '2026-10-01')$$, 'reconciliation_missing', 422);
SELECT period_month FROM rpc_put_board_reconciliation(t_u('cA'), '2026-10-01', 1100000, 480000, false);
SELECT t_expect_http('v3-T18: GAAP entered but no 4-line split → still 422 reconciliation_missing',
  $$SELECT rpc_build_board_report(t_u('cA'), '2026-10-01')$$, 'reconciliation_missing', 422);
SELECT jsonb_array_length(rpc_put_happiness_debt_split(t_u('cA'), '2026-10-01', 50000, 30000, 20000, 10000)) AS split_lines;
SELECT t_expect_http('v3-T14: 4 lines (110,000) ≠ happiness_debt_balance (120,000) → 422 reconciliation_unbalanced',
  $$SELECT rpc_build_board_report(t_u('cA'), '2026-10-01')$$, 'reconciliation_unbalanced', 422);
SELECT jsonb_array_length(rpc_put_happiness_debt_split(t_u('cA'), '2026-10-01', 50000, 30000, 25000, 15000)) AS split_lines;
SELECT t_expect_http('v3-T18: no prior-period figures (September) → 422 reconciliation_prior_period_missing',
  $$SELECT rpc_build_board_report(t_u('cA'), '2026-10-01')$$, 'reconciliation_prior_period_missing', 422);
SELECT period_month FROM rpc_put_board_reconciliation(t_u('cA'), '2026-09-01', 1000000, 500000, true);
SELECT jsonb_array_length(rpc_put_happiness_debt_split(t_u('cA'), '2026-09-01', 40000, 30000, 20000, 10000)) AS split_lines;
SELECT t_expect_http('v1.6.19 A1: a manual tier is refused — the level is computed → 422 verification_level_is_computed',
  $$SELECT rpc_put_metric_assurance(t_u('cA'), 'chr_real_ebitda', 2, 'בדיקה פנימית של טבלת ההתאמה')$$, 'verification_level_is_computed', 422);
SELECT (rpc_put_metric_verification_evidence(t_u('cA'), 'chr_real_ebitda', '2026-10-01', NULL, true, true, true, true, false, 'none', NULL, false, false))->>'tier' AS chr_tier;
SELECT t_assert('BCR: 13 yes without independent approval (C6–C7 not counted) → "התחייבות אמינה"',
  (SELECT (j->>'yes_count')::int = 13 AND j->>'result_he' = 'התחייבות אמינה'
     FROM (SELECT rpc_put_bcr_check(t_u('cA'), '2026-09-01', jsonb_build_object('B1',true,'B2',true,'B3',true,'B4',true,'C1',true,'C2',true,'C3',true,'C4',true,'C5',true,'C6',true,'C7',true,'R1',true,'R2',true,'R3',true,'R4',true)) j) x));
SELECT t_assert('BCR: 8 yes + C6–C7 yes WITHOUT approval = 8 → "לא הוגדר" (v3 gives no middle label)',
  (SELECT (j->>'yes_count')::int = 8 AND j->>'result_he' = 'לא הוגדר'
     FROM (SELECT rpc_put_bcr_check(t_u('cA'), '2026-10-01', jsonb_build_object('B1',true,'B2',true,'B3',true,'B4',true,'C1',true,'C2',true,'C3',true,'C4',true,'C5',false,'C6',true,'C7',true,'R1',false,'R2',false,'R3',false,'R4',false)) j) x));
SELECT t_assert('BCR: the same with independent approval = 10 → "התחייבות אמינה"',
  (SELECT (j->>'yes_count')::int = 10 AND j->>'result_he' = 'התחייבות אמינה'
     FROM (SELECT rpc_put_bcr_check(t_u('cA'), '2026-10-01', jsonb_build_object('B1',true,'B2',true,'B3',true,'B4',true,'C1',true,'C2',true,'C3',true,'C4',true,'C5',false,'C6',true,'C7',true,'R1',false,'R2',false,'R3',false,'R4',false), true) j) x));
SELECT t_assert('BCR: 5 yes → "הוצאה לתצוגה"',
  (SELECT j->>'result_he' = 'הוצאה לתצוגה'
     FROM (SELECT rpc_put_bcr_check(t_u('cA'), '2026-08-01', jsonb_build_object('B1',true,'B2',true,'B3',true,'B4',true,'C1',true,'C2',false,'C3',false,'C4',false,'C5',false,'C6',false,'C7',false,'R1',false,'R2',false,'R3',false,'R4',false)) j) x));
SELECT t_expect_http('BCR: 14 answers → 400', $$SELECT rpc_put_bcr_check(t_u('cA'), '2026-08-01', '{"B1":true}')$$, 'invalid_bcr_answers', 400);
INSERT INTO t_outputs SELECT 'board_oct_12', rpc_build_board_report(t_u('cA'), '2026-10-01');
INSERT INTO t_outputs SELECT 'board_oct_10', rpc_build_board_report(t_u('cA'), '2026-10-01', 0.10);
SELECT t_expect_http('v3-T16: a display rate other than 12 % / 10 % → 400', $$SELECT rpc_build_board_report(t_u('cA'), '2026-10-01', 0.11)$$, 'invalid_sensitivity_rate', 400);
RESET ROLE;
SELECT t_assert('v3-T14: the 4 Shadow Balance lines add up to happiness_debt_balance (120,000)',
  (SELECT (SELECT sum((l->>'amount')::numeric) FROM jsonb_array_elements(j->'shadow_balance') l) = (j->>'happiness_debt_balance')::numeric
          AND jsonb_array_length(j->'shadow_balance') = 4 AND (j->>'happiness_debt_balance')::numeric = 120000
     FROM t_outputs WHERE label = 'board_oct_12'));
SELECT t_assert('v3-T15: reconciliation balances — GAAP 1,100,000 − debt 120,000 − מס קיפוח 14,400 = CHR Real EBITDA 965,600 (prior 888,000)',
  (SELECT (j->'chr_real_ebitda'->>'value')::numeric = 965600
          AND (SELECT (r->>'current')::numeric FROM jsonb_array_elements(j->'reconciliation') r WHERE r->>'line' = 'gaap_ebitda')
              - (SELECT sum((r->>'current')::numeric) FROM jsonb_array_elements(j->'reconciliation') r
                  WHERE r->>'line' NOT IN ('gaap_ebitda', 'chr_real_ebitda'))
              = (SELECT (r->>'current')::numeric FROM jsonb_array_elements(j->'reconciliation') r WHERE r->>'line' = 'chr_real_ebitda')
          AND (SELECT (r->>'prior')::numeric FROM jsonb_array_elements(j->'reconciliation') r WHERE r->>'line' = 'chr_real_ebitda') = 888000
          AND jsonb_array_length(j->'reconciliation') = 7
          AND j->'chr_real_ebitda'->>'definition_he' = 'מדד ניהולי חלופי, לא רווח חשבונאי'
     FROM t_outputs WHERE label = 'board_oct_12'));
SELECT t_assert('v3-T16: the 10 % switch changes only the display (14,400 → 12,000); stored rate / amount and CHR Real EBITDA unchanged',
  (SELECT (a.j->'deprivation_tax'->>'display_amount')::numeric = 14400 AND (b.j->'deprivation_tax'->>'display_amount')::numeric = 12000
          AND a.j->'deprivation_tax'->'stored_amount' = b.j->'deprivation_tax'->'stored_amount'
          AND a.j->'deprivation_tax'->'stored_rate' = b.j->'deprivation_tax'->'stored_rate'
          AND a.j->'chr_real_ebitda' = b.j->'chr_real_ebitda' AND a.j->'reconciliation' = b.j->'reconciliation'
     FROM t_outputs a, t_outputs b WHERE a.label = 'board_oct_12' AND b.label = 'board_oct_10')
  AND (SELECT deprivation_tax_amount = 14400 FROM shadow_balance_aggregate WHERE org_id = t_u('cA') AND calculated_at = '2026-10-15 12:00+03')
  AND (SELECT value_numeric = 0.12 FROM agent_settings WHERE company_id IS NULL AND setting_key = 'deprivation_tax_rate'));
SELECT t_assert('board report + v1.6.19 J-43: one leaver (< 10) → memo line "יצא עם העוזבים" not yet published (amount null, waiting text)',
  (SELECT j->'exported_on_exit'->'amount' = 'null'::jsonb AND j->'exported_on_exit'->>'label_he' = 'יצא עם העוזבים'
          AND j->'exported_on_exit'->>'display_he' = 'עדיין לא הצטברו מספיק עוזבים לעדכון ראשון'
     FROM t_outputs WHERE label = 'board_oct_12'));
SELECT t_assert('board report + v1.6.19: computed level per metric (chr_real_ebitda 2 — reporting-rate control; others 0) and the BCR score',
  (SELECT (j->'verification_levels'->'chr_real_ebitda'->>'tier')::int = 2
          AND j->'verification_levels'->'chr_real_ebitda'->>'label_he' LIKE 'רמה 2 —%'
          AND (j->'verification_levels'->'happiness_debt_balance'->>'tier')::int = 0
          AND NOT j ? 'assurance_tier'
          AND (j->'bcr_score'->>'yes_count')::int = 10
     FROM t_outputs WHERE label = 'board_oct_12'));
SELECT t_assert('board report: turnover above baseline "לא הוגדר" while baselines are not set; misleading-margins flag on (payroll ↓ with a leaver, PCQ-12 ↓)',
  (SELECT j->'turnover_above_baseline'->>'display_he' = 'לא הוגדר' AND j->'turnover_above_baseline'->'cost_above_baseline' = 'null'::jsonb
          AND (j->>'misleading_margins_flag')::boolean
     FROM t_outputs WHERE label = 'board_oct_12'));
SELECT t_as(t_u('cfoA'));
SET ROLE authenticated;
INSERT INTO t_outputs SELECT 'board_sep', rpc_build_board_report(t_u('cA'), '2026-09-01');
RESET ROLE;
SELECT t_assert('board report: first period (September) publishes with "אין תקופה קודמת"',
  (SELECT j->>'prior_period_note_he' = 'אין תקופה קודמת (דוח ראשון)' FROM t_outputs WHERE label = 'board_sep'));
SELECT t_as(t_u('chairA'));
SET ROLE authenticated;
INSERT INTO t_outputs SELECT 'board_get_chair', rpc_get_board_report(t_u('cA'), '2026-10-01');
SELECT t_assert('board report: the board chair reads the published report', (SELECT j ? 'reconciliation' FROM t_outputs WHERE label = 'board_get_chair'));
SELECT t_expect_http('board report: a month never published → 422', $$SELECT rpc_get_board_report(t_u('cA'), '2026-05-01')$$, 'board_report_not_published', 422);
SELECT t_expect_http('board report: the chair cannot build it (cfo / vp_hr only) → 403', $$SELECT rpc_build_board_report(t_u('cA'), '2026-10-01')$$, 'insufficient_privilege', 403);
RESET ROLE;
SELECT t_as(t_u('big1'));
SET ROLE authenticated;
SELECT t_expect_http('board report: employee → 403', $$SELECT rpc_get_board_report(t_u('cA'), '2026-10-01')$$, 'insufficient_privilege', 403);
RESET ROLE;
SELECT t_expect_err('board_report is WORM', $$UPDATE board_report SET report = '{}'$$, 'ledger_immutable');

-- ============ 11. v3-T5 · privacy sweep: no person_id or other employee identifier in any agent output ============
SELECT t_assert('v3-T5: ' || count(*) || ' captured agent outputs (settings, liability, EverStore summaries, daily summaries, burnout trends incl. the 5th signal, board reports) hold no person_id / user_id / pseudonym / name / email',
  count(*) >= 20 AND bool_and(t_ids_free(j)))
  FROM t_outputs;
SELECT t_assert('v3-T5: the sweep itself catches an identifier (self-check)',
  NOT t_ids_free(jsonb_build_object('person_id', 1)) AND NOT t_ids_free(jsonb_build_object('x', t_u('big1')::text)));
SELECT t_assert('v3-T5: no agent table has a person / user / employee column except remediation_records.approved_by and the per-user ledger',
  NOT EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name IN ('agent_settings', 'everstore_budget', 'agent_daily_summaries', 'happiness_debt_events',
                                    'happiness_debt_ledger', 'team_movements', 'metric_assurance', 'bcr_checks', 'epwi_inputs',
                                    'board_reconciliation', 'board_report', 'everstore_budget_summary_v')
                 AND column_name ~* '(person|user|employee|pseudonym)'));
SELECT t_assert('v3-T5: every agent table has RLS forced and no client grant',
  (SELECT bool_and(c.relrowsecurity AND c.relforcerowsecurity
                   AND NOT has_table_privilege('authenticated', c.oid, 'SELECT') AND NOT has_table_privilege('anon', c.oid, 'SELECT'))
     FROM pg_class c WHERE c.relname IN ('agent_settings', 'everstore_budget', 'everstore_item_cost', 'agent_daily_summaries',
                                         'golden_spoons_ledger', 'remediation_records', 'happiness_debt_events', 'happiness_debt_ledger',
                                         'team_movements', 'metric_assurance', 'bcr_checks', 'epwi_inputs', 'board_reconciliation', 'board_report',
                                         'happiness_debt_leaver_link', 'happiness_debt_remediation_allocation',
                                         'time_benefit_absence_link', 'time_benefit_refund', 'questionnaire_reward_history')));

-- ============ 12. classify_deprived — two consecutive weeks (v3 §6.2) ============
SELECT t_assert('classify_deprived: fn_is_employee_deprived requires this week AND the previous week (week_start − 7)',
  pg_get_functiondef('fn_is_employee_deprived(uuid, date)'::regprocedure) ~ '- 7');
