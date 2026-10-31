-- =============================================================================
-- CHR-ETRS MVP v1.6.17 · tests/test_v1_5.sql (filename kept per Drive rule) — scratch PostgreSQL 17 validation
-- Version: 1.6.17-mvp (2026-10-31) — supersedes the 1.6.16-mvp (2026-10-30), 1.6.13-mvp (2026-10-25), 1.6.12-mvp, 1.6.11-mvp, 1.6.10-mvp, 1.6.9-mvp, 1.6.8-mvp and 1.6.7-mvp versions of this file
-- v1.6.21 (2026-10-31, Karin J-115 = A / J-112 = A): the no-department share of the company Shadow Balance total
--   (differencing guard N ≥ 10, same total in CHR Real EBITDA) and company-level Cuckoo for employees without a department.
-- v1.6.20-r2 (2026-10-31, Karin J-102 = A): + a real 'General' team never grows by default-department employees
--   (small team stays suppressed at N≥5 and N≥10; tax / Happiness Debt exclude them).
-- v1.6.10: UZ keeps Asia/Tashkent (Samarkand excluded); a pinned zone (UA → Kyiv) is never needs_review;
--   fn_start_date_untrusted / fn_tz_edge follow chr.mig_source_tz (UTC when unset).
-- v1.6.9: users.start_date is a generated read-only alias (O-50) → fixtures write hire_date instead.
-- Run on a FRESH database after ref_country_calendar.sql + schema.sql + rpc.sql:
--   psql -v ON_ERROR_STOP=1 -f ref_country_calendar.sql -f schema.sql -f rpc.sql -f tests/test_v1_5.sql
-- Every check prints "PASS <name>"; any failure aborts with an exception.
-- v1.6.16 (Karin 30.10, agents-bot-instructions-v3): tests changed BY DESIGN and marked "v1.6.16":
--   * questionnaire Golden Spoons = participation amount from agent_settings (PCQ-12 / monthly 10,
--     Cantril / short 2, TPS-12 / IHS quarterly "לא הוגדר" → 0 + reward_status not_defined); score/10 removed;
--   * rpc_convert_golden_to_chr → 422 chr_coins_deferred_to_v2 on every call (no balance change, no row);
--   * deprived employee needs TWO consecutive weeks (previous-week fixtures added).
-- v1.6.17 (Karin 31.10): tests changed BY DESIGN and marked "v1.6.17": Cantril is MONTHLY → 10 (was short 2);
--   TPS-12 / IHS quarterly participation = 10 (was "לא הוגדר" → 0).
-- The agents tests live in tests/test_agents_v1_6_16.sql (filename kept; content v1.6.17).
-- =============================================================================
\set QUIET on
SET client_min_messages = warning;

-- ---------- test helpers (superuser-owned, invoker rights) ----------
CREATE OR REPLACE FUNCTION t_pass(p_name text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN RAISE WARNING 'PASS %', p_name; END $$;

-- Expect p_sql to fail with message/HINT = p_code (or SQLSTATE = p_code).
CREATE OR REPLACE FUNCTION t_expect_err(p_name text, p_sql text, p_code text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RAISE EXCEPTION 'FAIL % — no error (expected %)', p_name, p_code;
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE 'FAIL %' THEN RAISE; END IF;
  IF SQLERRM = p_code OR SQLSTATE = p_code THEN
    PERFORM t_pass(p_name);
  ELSE
    RAISE EXCEPTION 'FAIL % — got [%] %, expected %', p_name, SQLSTATE, SQLERRM, p_code;
  END IF;
END $$;

-- v1.6.6: expect code p_code AND the Error Contract HTTP hint (DETAIL 'http_hint=<p_http>;code=<p_code>').
CREATE OR REPLACE FUNCTION t_expect_http(p_name text, p_sql text, p_code text, p_http int) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_detail text; v_state text;
BEGIN
  EXECUTE p_sql;
  RAISE EXCEPTION 'FAIL % — no error (expected % %)', p_name, p_http, p_code;
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE 'FAIL %' THEN RAISE; END IF;
  GET STACKED DIAGNOSTICS v_detail = PG_EXCEPTION_DETAIL, v_state = RETURNED_SQLSTATE;
  IF SQLERRM = p_code AND v_detail = format('http_hint=%s;code=%s', p_http, p_code) THEN
    PERFORM t_pass(p_name);
  ELSE
    RAISE EXCEPTION 'FAIL % — got [%] % / %, expected % %', p_name, v_state, SQLERRM, v_detail, p_http, p_code;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION t_assert(p_name text, p_ok boolean) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_ok IS NOT TRUE THEN RAISE EXCEPTION 'FAIL %', p_name; END IF;
  PERFORM t_pass(p_name);
END $$;

-- Impersonate a user for auth.uid()
CREATE OR REPLACE FUNCTION t_as(p_uid uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', p_uid::text, false);
$$;

GRANT EXECUTE ON FUNCTION t_pass(text), t_expect_err(text, text, text), t_expect_http(text, text, text, int), t_assert(text, boolean), t_as(uuid) TO authenticated;

-- ---------- fixtures ----------
-- Company C; departments D4/D5/D9/D10 with that many employees; manager M (dept Mgmt).
-- v1.6.5: company calendar set explicitly for fixtures (Monday override keeps earlier expectations).
INSERT INTO companies (company_id, company_name, country, week_start_dow, last_workday_dow, timezone)
VALUES ('00000000-0000-0000-0000-0000000000c1', 'TestCo', 'IL', 1, 5, 'Asia/Jerusalem');

DO $$
DECLARE
  d record; i int; v_uid uuid;
BEGIN
  INSERT INTO auth.users (id) VALUES ('00000000-0000-0000-0000-00000000aaaa');
  INSERT INTO users (user_id, company_id, email, full_name, department, app_role, org_role_code, timezone, hire_date)
  VALUES ('00000000-0000-0000-0000-00000000aaaa', '00000000-0000-0000-0000-0000000000c1',
          'm@x', 'Manager M', 'Mgmt', 'manager', 'direct_manager', 'Asia/Jerusalem', CURRENT_DATE - 400);
  INSERT INTO auth.users (id) VALUES ('00000000-0000-0000-0000-00000000bbbb');
  INSERT INTO users (user_id, company_id, email, full_name, department, app_role, org_role_code, timezone, hire_date)
  VALUES ('00000000-0000-0000-0000-00000000bbbb', '00000000-0000-0000-0000-0000000000c1',
          'hr@x', 'VP HR', 'Mgmt', 'vp_hr', 'vp', 'Asia/Jerusalem', CURRENT_DATE - 400);
  FOR d IN SELECT * FROM (VALUES ('D4', 4), ('D5', 5), ('D8', 8), ('D9', 9), ('D10', 10)) AS t(dept, n) LOOP
    FOR i IN 1..d.n LOOP
      v_uid := gen_random_uuid();
      INSERT INTO auth.users (id) VALUES (v_uid);
      INSERT INTO users (user_id, company_id, reports_to, email, full_name, department, app_role,
                         timezone, hire_date, display_pseudonym)
      VALUES (v_uid, '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-00000000aaaa',
              d.dept || '-' || i || '@x', 'Real Name ' || d.dept || '-' || i, d.dept, 'employee',
              'Asia/Jerusalem', CURRENT_DATE - 100, 'כינוי-' || d.dept || '-' || i);
    END LOOP;
  END LOOP;
END $$;

-- Handy lookup
CREATE OR REPLACE FUNCTION t_emp(p_dept text, p_i int) RETURNS uuid LANGUAGE sql SECURITY DEFINER AS $$
  SELECT user_id FROM users WHERE email = p_dept || '-' || p_i || '@x'
$$;
GRANT EXECUTE ON FUNCTION t_emp(text, int) TO authenticated;

-- System-assigned pseudonym of a fixture employee
CREATE OR REPLACE FUNCTION t_pseudo(p_dept text, p_i int) RETURNS varchar LANGUAGE sql SECURITY DEFINER AS $$
  SELECT display_pseudonym FROM users WHERE email = p_dept || '-' || p_i || '@x'
$$;
GRANT EXECUTE ON FUNCTION t_pseudo(text, int) TO authenticated;

-- Mark today's spoons as REPORTED for the first n employees of a team (actual contributors).
CREATE OR REPLACE FUNCTION t_report(p_dept text, p_n int, p_spoons int DEFAULT 12) RETURNS void LANGUAGE plpgsql AS $$
DECLARE i int;
BEGIN
  FOR i IN 1..p_n LOOP
    PERFORM fn_ensure_local_spoon_budget(t_emp(p_dept, i));
    UPDATE spoon_budget SET reported_at = clock_timestamp(), current_spoon_count = p_spoons
     WHERE user_id = t_emp(p_dept, i) AND budget_date = fn_user_local_date(t_emp(p_dept, i));
  END LOOP;
END $$;

-- Salary record (system/superuser path) for the first n employees of a team.
CREATE OR REPLACE FUNCTION t_salary(p_dept text, p_n int) RETURNS void LANGUAGE sql AS $$
  INSERT INTO employee_value_asset (user_id, company_id, annual_salary)
  SELECT t_emp(p_dept, i), '00000000-0000-0000-0000-0000000000c1', 100000 FROM generate_series(1, p_n) i
  ON CONFLICT (user_id) DO NOTHING
$$;

-- ============ 0. Pseudonyms (lock #8) ============
SELECT t_assert('new users get a system pseudonym automatically (colour + animal)',
  NOT EXISTS (SELECT 1 FROM users WHERE display_pseudonym IS NULL OR display_pseudonym !~ '^\S+ \S+'));
SELECT t_assert('client-supplied pseudonym is ignored (fixtures sent כינוי-…)',
  NOT EXISTS (SELECT 1 FROM users WHERE display_pseudonym LIKE 'כינוי-%'));
SELECT t_assert('pseudonyms unique per company',
  (SELECT count(*) = count(DISTINCT display_pseudonym) FROM users WHERE company_id = '00000000-0000-0000-0000-0000000000c1'));
SELECT t_assert('pseudonym never derived from name / id',
  NOT EXISTS (SELECT 1 FROM users WHERE strpos(lower(display_pseudonym), lower(full_name)) > 0
                                     OR strpos(display_pseudonym, split_part(email, '@', 1)) > 0
                                     OR strpos(display_pseudonym, left(user_id::text, 8)) > 0));
SELECT t_assert('no self-set pseudonym RPC exists',
  NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname IN ('rpc_set_display_pseudonym')));
SELECT t_assert('generator is not callable by clients',
  NOT has_function_privilege('authenticated', 'fn_generate_pseudonym(uuid)', 'EXECUTE'));
SELECT t_as(t_emp('D5', 3));
SET ROLE authenticated;
SELECT t_expect_err('employee cannot set her pseudonym (no write path)',
  $$UPDATE users SET display_pseudonym = 'בחרתי לבד' WHERE user_id = auth.uid()$$, '42501');
SELECT t_expect_err('employee cannot call the generator', $$SELECT fn_generate_pseudonym(NULL)$$, '42501');
RESET ROLE;
SELECT t_expect_err('pseudonym immutable even for the owner role',
  format($$UPDATE users SET display_pseudonym = 'שם חדש' WHERE user_id = %L$$, t_emp('D5', 3)), 'pseudonym_immutable');

-- ============ 1. Turnover tiers ============
SELECT t_assert('tiers seeded junior 30–50 / mid 100–150 / senior 200–400',
  (SELECT string_agg(tier || ':' || min_pct::int || '-' || max_pct::int, ',' ORDER BY min_pct) FROM turnover_tier_config)
  = 'junior:30-50,mid:100-150,senior:200-400');
SELECT t_expect_err('tier CHECK rejects junior min 25', $$UPDATE turnover_tier_config SET min_pct = 25 WHERE tier = 'junior'$$, '23514');
SELECT t_expect_err('tier CHECK rejects senior max 500', $$UPDATE turnover_tier_config SET max_pct = 500 WHERE tier = 'senior'$$, '23514');
SELECT t_expect_err('tier CHECK rejects unknown tier', $$INSERT INTO turnover_tier_config VALUES ('intern', 10, 20)$$, '23514');
SELECT t_assert('role_cost_config removed', to_regclass('public.role_cost_config') IS NULL);
SELECT t_assert('EVA has no multiplier / role_key columns',
  NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'employee_value_asset'
               AND column_name IN ('replacement_cost_multiplier', 'role_key', 'replacement_cost', 'deprivation_tax')));

-- Salaries/tiers for D5 (vp_hr path) + deprivation flags (system path)
SELECT t_as('00000000-0000-0000-0000-00000000bbbb');
SET ROLE authenticated;
SELECT rpc_upsert_employee_value_asset(t_emp('D5', i), 100000, NULL, NULL,
       CASE WHEN i <= 2 THEN 'junior' WHEN i <= 4 THEN 'mid' ELSE 'senior' END)
  FROM generate_series(1, 5) i;
RESET ROLE;
SELECT t_as('00000000-0000-0000-0000-00000000aaaa');
SET ROLE authenticated;
SELECT t_expect_err('manager cannot set turnover tier',
  format($$SELECT rpc_upsert_employee_value_asset(%L, 1, NULL, NULL, 'senior')$$, t_emp('D5', 1)), 'anti_get_blocked');
SELECT t_expect_err('client cannot set deprivation flag',
  format($$SELECT rpc_set_deprivation_flag(%L, true)$$, t_emp('D5', 1)), '42501');
RESET ROLE;
SELECT rpc_set_deprivation_flag(t_emp('D5', 1), true);
SELECT rpc_set_deprivation_flag(t_emp('D5', 2), true);
SELECT t_assert('turnover range view: junior 100000 → 30000–50000',
  (SELECT turnover_cost_min = 30000 AND turnover_cost_max = 50000 FROM employee_turnover_cost_range_v WHERE user_id = t_emp('D5', 1)));

-- ============ 2/3. Thresholds = ACTUAL contributors (lock #3) + deprivation tax ============
SELECT t_report('D4', 4);
SELECT t_report('D9', 9);
SELECT t_salary('D9', 9);
SELECT t_salary('D10', 10);
SELECT t_as('00000000-0000-0000-0000-00000000aaaa');
SET ROLE authenticated;
SELECT t_expect_err('regular: 4 contributors → 403', $$SELECT rpc_team_aggregate_refresh('00000000-0000-0000-0000-0000000000c1', 'D4')$$, 'aggregation_privacy_threshold');
SELECT t_assert('regular: 5 contributors (salary records) → data',
  (SELECT contributor_count = 5 FROM rpc_team_aggregate_refresh('00000000-0000-0000-0000-0000000000c1', 'D5')));
SELECT t_assert('regular: 9 contributors → data (team of 5–9 sees regular data)',
  (SELECT contributor_count = 9 FROM rpc_team_aggregate_refresh('00000000-0000-0000-0000-0000000000c1', 'D9')));
SELECT t_expect_err('team of 8 members with 0 contributors → 403 (size never counts)',
  $$SELECT rpc_team_aggregate_refresh('00000000-0000-0000-0000-0000000000c1', 'D8')$$, 'aggregation_privacy_threshold');
SELECT t_assert('deprivation tax = 2 × 100000 × 0.12 = 24000',
  (SELECT deprived_count = 2 AND avg_annual_salary = 100000 AND deprivation_tax_amount = 24000
     FROM team_aggregate WHERE department = 'D5' ORDER BY calculated_at DESC LIMIT 1));
SELECT t_assert('turnover range sums D5: min 2×30k+2×100k+200k=460000, max 2×50k+2×150k+400k=800000',
  (SELECT turnover_cost_min_sum = 460000 AND turnover_cost_max_sum = 800000
     FROM team_aggregate WHERE department = 'D5' ORDER BY calculated_at DESC LIMIT 1));
SELECT t_assert('manager reads team_aggregate N≥5', (SELECT count(*) >= 2 FROM team_aggregate));
SELECT t_expect_err('shadow balance: 9 salary contributors → 403', $$SELECT rpc_shadow_balance_refresh('00000000-0000-0000-0000-0000000000c1', 'D9')$$, 'aggregation_privacy_threshold');
SELECT t_assert('shadow balance: 10 salary contributors → data',
  (SELECT contributor_count = 10 FROM rpc_shadow_balance_refresh('00000000-0000-0000-0000-0000000000c1', 'D10')));
RESET ROLE;
-- Karin's test: a team of 8 with only 4 answers → 403; 5 answers → passes.
SELECT t_as(t_emp('D8', 1));
SET ROLE authenticated;
SELECT rpc_submit_questionnaire('TPS-12', '{4,2,4,2,4,2,4,2,4,2,4,2}') IS NOT NULL AS answer_1;
RESET ROLE;
SELECT t_as(t_emp('D8', 2));
SET ROLE authenticated;
SELECT rpc_submit_questionnaire('TPS-12', '{4,2,4,2,4,2,4,2,4,2,4,2}') IS NOT NULL AS answer_2;
RESET ROLE;
SELECT t_as(t_emp('D8', 3));
SET ROLE authenticated;
SELECT rpc_submit_questionnaire('TPS-12', '{4,2,4,2,4,2,4,2,4,2,4,2}') IS NOT NULL AS answer_3;
RESET ROLE;
SELECT t_as(t_emp('D8', 4));
SET ROLE authenticated;
SELECT rpc_submit_questionnaire('TPS-12', '{4,2,4,2,4,2,4,2,4,2,4,2}') IS NOT NULL AS answer_4;
RESET ROLE;
SELECT t_as('00000000-0000-0000-0000-00000000aaaa');
SET ROLE authenticated;
SELECT t_expect_err('team of 8 with only 4 answers → 403 aggregation_privacy_threshold',
  $$SELECT rpc_team_aggregate_refresh('00000000-0000-0000-0000-0000000000c1', 'D8')$$, 'aggregation_privacy_threshold');
RESET ROLE;
SELECT t_as(t_emp('D8', 5));
SET ROLE authenticated;
SELECT rpc_submit_questionnaire('TPS-12', '{4,2,4,2,4,2,4,2,4,2,4,2}') IS NOT NULL AS fifth_answer;
RESET ROLE;
SELECT t_as('00000000-0000-0000-0000-00000000aaaa');
SET ROLE authenticated;
SELECT t_assert('team of 8 with 5 answers → passes (N = 5 respondents, TPS average shown)',
  (SELECT contributor_count = 5 AND tps_respondent_count = 5 AND tps_team_avg IS NOT NULL
     FROM rpc_team_aggregate_refresh('00000000-0000-0000-0000-0000000000c1', 'D8')));
SELECT t_assert('figures below their own N stay hidden (no salary data in D8)',
  (SELECT avg_annual_salary IS NULL AND deprivation_tax_amount IS NULL AND team_spoon_avg IS NULL
     FROM team_aggregate WHERE department = 'D8' ORDER BY calculated_at DESC LIMIT 1));
RESET ROLE;
SELECT t_assert('team-size helpers removed', to_regprocedure('fn_team_member_count(uuid,varchar)') IS NULL
  AND to_regprocedure('fn_require_team_threshold(uuid,varchar,text)') IS NULL);
SELECT t_expect_err('direct insert team_aggregate with 4 contributors → 403 (trigger)',
  $$INSERT INTO team_aggregate (org_id, department, contributor_count) VALUES ('00000000-0000-0000-0000-0000000000c1', 'X', 4)$$, 'aggregation_privacy_threshold');
SELECT t_expect_err('direct insert shadow_balance with 9 contributors → 403 (trigger)',
  $$INSERT INTO shadow_balance_aggregate (org_id, department, contributor_count) VALUES ('00000000-0000-0000-0000-0000000000c1', 'X', 9)$$, 'aggregation_privacy_threshold');
SELECT t_expect_err('threshold config locked (regular cannot become 10)', $$UPDATE privacy_threshold_config SET min_n = 10 WHERE scope = 'regular'$$, '23514');
SELECT t_assert('thresholds: regular 5, project 5, cuckoo/shadow/emergency 10, board 20',
  (SELECT string_agg(scope || '=' || min_n, ',' ORDER BY scope) FROM privacy_threshold_config)
  = 'board=20,cuckoo=10,emergency=10,project=5,regular=5,shadow_balance=10');
SELECT t_expect_err('board threshold locked at 20', $$UPDATE privacy_threshold_config SET min_n = 10 WHERE scope = 'board'$$, '23514');

-- ============ 4. Cuckoo ============
SELECT t_expect_err('cuckoo: 9 contributors → 403', format($$SELECT fn_cuckoo_raise(%L, 'nlp_distress')$$, t_emp('D9', 1)), 'aggregation_privacy_threshold');
SELECT t_report('D10', 9);
SELECT t_expect_err('cuckoo: team of 10 with 9 contributors → 403', format($$SELECT fn_cuckoo_raise(%L, 'nlp_distress')$$, t_emp('D10', 1)), 'aggregation_privacy_threshold');
SELECT t_report('D10', 10);
CREATE TEMP TABLE t_alert AS SELECT * FROM fn_cuckoo_raise(t_emp('D10', 1), 'nlp_distress', '["X1"]');
GRANT SELECT ON t_alert TO authenticated;
SELECT t_assert('cuckoo window is 60 seconds',
  (SELECT sovereign_veto_window_expiry - created_at BETWEEN interval '59 seconds' AND interval '61 seconds' FROM t_alert));
SELECT t_assert('cuckoo logic_hash is 64-hex sha256', (SELECT logic_hash ~ '^[0-9a-f]{64}$' FROM t_alert));
SELECT t_as('00000000-0000-0000-0000-00000000aaaa');
SET ROLE authenticated;
SELECT t_assert('manager cannot read cuckoo_alert base table', (SELECT count(*) = 0 FROM cuckoo_alert));
SELECT t_assert('manager inbox empty during 60-second window', (SELECT count(*) = 0 FROM cuckoo_alert_manager_v));
RESET ROLE;
SELECT t_as(t_emp('D10', 1));
SET ROLE authenticated;
SELECT t_assert('employee sees own alert first', (SELECT count(*) = 1 FROM cuckoo_alert));
RESET ROLE;
-- simulate 60 seconds passing without veto
UPDATE cuckoo_alert SET sovereign_veto_window_expiry = clock_timestamp() - interval '1 second';
SELECT t_as(t_emp('D10', 1));
SET ROLE authenticated;
SELECT t_expect_err('veto after 60 seconds refused', format($$SELECT rpc_cuckoo_veto(%L)$$, (SELECT alert_id FROM t_alert)), 'anti_get_blocked');
RESET ROLE;
SELECT t_as('00000000-0000-0000-0000-00000000aaaa');
SET ROLE authenticated;
SELECT t_assert('after 60s manager sees pseudonym only',
  (SELECT count(*) = 1 AND bool_and(target_pseudonym = t_pseudo('D10', 1)) FROM cuckoo_alert_manager_v));
SELECT t_assert('manager view has no user id / reason / medical columns',
  (SELECT array_agg(column_name::text ORDER BY column_name) = '{alert_id,delivered_at,target_pseudonym}'
     FROM information_schema.columns WHERE table_name = 'cuckoo_alert_manager_v'));
SELECT t_assert('manager view never returns the real user id',
  NOT EXISTS (SELECT 1 FROM cuckoo_alert_manager_v v WHERE v::text LIKE '%' || t_emp('D10', 1)::text || '%'));
RESET ROLE;
-- veto inside the window hides it from the manager
CREATE TEMP TABLE t_alert2 AS SELECT * FROM fn_cuckoo_raise(t_emp('D10', 2), 'nlp_distress');
GRANT SELECT ON t_alert2 TO authenticated;
SELECT t_as(t_emp('D10', 2));
SET ROLE authenticated;
SELECT t_assert('employee veto within 60s', (SELECT status = 'VETOED_BY_EMPLOYEE' FROM rpc_cuckoo_veto((SELECT alert_id FROM t_alert2))));
RESET ROLE;
UPDATE cuckoo_alert SET sovereign_veto_window_expiry = clock_timestamp() - interval '1 second';
SELECT t_as('00000000-0000-0000-0000-00000000aaaa');
SET ROLE authenticated;
SELECT t_assert('vetoed alert never reaches the manager', (SELECT count(*) = 1 FROM cuckoo_alert_manager_v));
RESET ROLE;

-- ============ 5. Spoons ============
-- Employee E = D9-1; manager assigns tasks.
SELECT fn_ensure_local_spoon_budget(t_emp('D9', 1));
SELECT t_expect_err('spoons hard max 12', format($$UPDATE spoon_budget SET current_spoon_count = 13 WHERE user_id = %L$$, t_emp('D9', 1)), '23514');
UPDATE spoon_budget SET current_spoon_count = 6 WHERE user_id = t_emp('D9', 1);
SELECT t_as('00000000-0000-0000-0000-00000000aaaa');
SET ROLE authenticated;
SELECT t_assert('fighting allowed at 6 (→5)', (SELECT s_final = 1 FROM rpc_assign_task(t_emp('D9', 1), 'f1', 'fighting')));
SELECT t_expect_err('fighting blocked at 5', format($$SELECT rpc_assign_task(%L, 'f2', 'fighting')$$, t_emp('D9', 1)), 'circuit_breaker_active');
SELECT t_assert('farming allowed at 5', (SELECT task_kind = 'farming' FROM rpc_assign_task(t_emp('D9', 1), 'farm', 'farming')));
RESET ROLE;
UPDATE spoon_budget SET current_spoon_count = 4 WHERE user_id = t_emp('D9', 1);
SELECT t_assert('day_status at 4 = FIGHTING_BLOCKED', (SELECT day_status = 'FIGHTING_BLOCKED' FROM spoon_budget WHERE user_id = t_emp('D9', 1)));
SELECT t_as('00000000-0000-0000-0000-00000000aaaa');
SET ROLE authenticated;
SELECT t_expect_err('fighting blocked at 4', format($$SELECT rpc_assign_task(%L, 'f3', 'fighting')$$, t_emp('D9', 1)), 'circuit_breaker_active');
-- farming with +1 modifier: 4 → 3 → go home logged
SELECT t_assert('farming +1 at 4 → 3', (SELECT s_final = 1 FROM rpc_assign_task(t_emp('D9', 1), 'farm2', 'farming', false, false, '[1]')));
SELECT t_expect_err('lock #1: at ≤3 ALL tasks blocked — Farming', format($$SELECT rpc_assign_task(%L, 'farm3', 'farming')$$, t_emp('D9', 1)), 'circuit_breaker_active');
SELECT t_expect_err('lock #1: at ≤3 ALL tasks blocked — Fighting', format($$SELECT rpc_assign_task(%L, 'fight3', 'fighting')$$, t_emp('D9', 1)), 'circuit_breaker_active');
SELECT t_assert('manager feed: pseudonym + locked text only',
  (SELECT count(*) = 1 AND bool_and(display_pseudonym = t_pseudo('D9', 1) AND entry_text = 'יציאה מוקדמת מאושרת') FROM early_leave_manager_v));
RESET ROLE;
SELECT t_assert('go-home at 3: text exact, full workday, no sick day',
  (SELECT count(*) = 1 AND bool_and(entry_text = 'יציאה מוקדמת מאושרת' AND counts_as_full_workday AND NOT sick_day_deducted AND left_at IS NOT NULL)
     FROM early_leave_log WHERE user_id = t_emp('D9', 1)));
SELECT t_assert('early_leave_log has no reason column',
  NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'early_leave_log' AND column_name ILIKE '%reason%'));
SELECT t_expect_err('early leave text cannot differ', format($$INSERT INTO early_leave_log (user_id, local_date, entry_text) VALUES (%L, CURRENT_DATE - 5, 'sick')$$, t_emp('D9', 1)), '23514');
SELECT t_expect_err('early leave WORM', $$UPDATE early_leave_log SET left_at = now()$$, 'ledger_immutable');
SELECT t_assert('old <3 / <14% rule gone',
  to_regprocedure('fn_cb_check_spoons(uuid)') IS NULL
  AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'spoon_budget' AND column_name IN ('available_capacity_pct', 'energy_state')));
SELECT t_as(t_emp('D9', 1));
SET ROLE authenticated;
SELECT t_assert('rpc_log_go_home idempotent at 3', (SELECT entry_text = 'יציאה מוקדמת מאושרת' FROM rpc_log_go_home()));
-- CB does not lock questionnaires: submit Cantril at 3 spoons
SELECT t_assert('questionnaire allowed at 3 spoons (CB does not lock) — Cantril participation 10.0 (v1.6.17: Cantril is monthly)',
  (SELECT reward_golden_spoons = 10.0 AND reward_status = 'set' FROM rpc_submit_questionnaire('Cantril', '{7}')));
SELECT t_assert('golden spoons balance = 10.0 (one decimal kept; v1.6.17 Cantril monthly)', (SELECT golden_spoons = 10.0 FROM avatar_state));
RESET ROLE;
SELECT t_as(t_emp('D9', 2));
SET ROLE authenticated;
SELECT t_expect_err('go-home refused above 3', $$SELECT rpc_log_go_home()$$, 'anti_get_blocked');
RESET ROLE;

-- ============ 6/7. Questionnaires ============
-- v1.6.16 (v3 §3.6): the score/10 reward is cancelled — the function is gone, no reward from a score.
SELECT t_assert('v1.6.16: fn_reward_score_div10 removed (no Golden Spoons from a questionnaire score)',
  to_regprocedure('fn_reward_score_div10(numeric)') IS NULL);
SELECT t_assert('v1.6.16: fn_questionnaire_reward takes (definition, company) — never a score',
  to_regprocedure('fn_questionnaire_reward(questionnaire_definition, uuid)') IS NOT NULL
  AND to_regprocedure('fn_questionnaire_reward(questionnaire_definition, numeric)') IS NULL);
SELECT t_assert('TPS all 3 → 50', fn_tps12_score('{3,3,3,3,3,3,3,3,3,3,3,3}', '{1,3,5,11}') = 50);
SELECT t_assert('TPS reversed items 1,3,5,11 (1s there, 5s elsewhere) → 100',
  fn_tps12_score('{1,5,1,5,1,5,5,5,5,5,1,5}', '{1,3,5,11}') = 100);
SELECT t_assert('TPS all 5 → (44−12)/48×100 = 66.67', fn_tps12_score('{5,5,5,5,5,5,5,5,5,5,5,5}', '{1,3,5,11}') = 66.67);
SELECT t_assert('TPS 11 answers → NULL', fn_tps12_score('{5,5,5,5,5,5,5,5,5,5,5}', '{1,3,5,11}') IS NULL);
SELECT t_assert('TPS bands', fn_tps_band(51.9) = 'low' AND fn_tps_band(52) = 'medium' AND fn_tps_band(60) = 'medium' AND fn_tps_band(60.1) = 'good');
SELECT t_assert('v1.6.17: seeds PCQ-12/Cantril/IHS/TPS-12 — participation rewards keyed to agent_settings (Cantril monthly)',
  (SELECT string_agg(code || ':' || frequency || ':' || reward_type || ':' || reward_setting_key || ':' || COALESCE(reward_amount::text, '-'), ',' ORDER BY code)
     FROM questionnaire_definition)
  = 'Cantril:monthly:participation:golden_spoons_per_questionnaire:-,IHS:quarterly:participation:golden_spoons_per_quarterly_questionnaire:-,'
    'PCQ-12:monthly:participation:golden_spoons_per_questionnaire:-,TPS-12:quarterly:participation:golden_spoons_per_quarterly_questionnaire:-');
SELECT t_expect_err('locked catalogue cannot drift (PCQ 12)', $$UPDATE questionnaire_definition SET reward_amount = 12 WHERE code = 'PCQ-12'$$, '23514');

SELECT t_as(t_emp('D9', 3));
SET ROLE authenticated;
SELECT t_assert('v1.6.17: TPS submit all 5 → score 66.67; quarterly participation 10 (Karin 31.10), reward_status set',
  (SELECT tps_12_score = 66.67 AND reward_golden_spoons = 10 AND reward_status = 'set'
     FROM rpc_submit_questionnaire('TPS-12', '{5,5,5,5,5,5,5,5,5,5,5,5}')));
SELECT t_expect_err('TPS once per quarter', $$SELECT rpc_submit_questionnaire('TPS-12', '{3,3,3,3,3,3,3,3,3,3,3,3}')$$, 'questionnaire_already_submitted');
SELECT t_assert('PCQ-12 via compat wrapper → +10',
  (SELECT reward_golden_spoons = 10 FROM rpc_pcq12_claim_monthly_reward('{1,2,3,4,5,6,1,2,3,4,5,6}')));
SELECT t_expect_err('PCQ-12 once per month', $$SELECT rpc_pcq12_claim_monthly_reward('{1,2,3,4,5,6,1,2,3,4,5,6}')$$, 'questionnaire_already_submitted');
SELECT t_assert('v1.6.17: balance 0 + 10 (TPS-12) + 10 (PCQ-12) = 20.0', (SELECT golden_spoons = 20.0 FROM avatar_state));
SELECT t_expect_err('IHS answer 80 out of 1–5 range → 400 (O-6: 1–5 questionnaire scale)', $$SELECT rpc_submit_questionnaire('IHS', '{80}')$$, 'questionnaire_invalid_answers');
SELECT t_expect_err('employee cannot update own answers (no grant)', $$UPDATE questionnaire_submission SET answers = '{1}'$$, '42501');
RESET ROLE;
SELECT t_as(t_emp('D9', 4));
SET ROLE authenticated;
SELECT t_expect_err('TPS all 12 required (11 given) → 400', $$SELECT rpc_submit_questionnaire('TPS-12', '{5,5,5,5,5,5,5,5,5,5,5}')$$, 'questionnaire_invalid_answers');
SELECT t_expect_err('TPS NULL answer → 400', $$SELECT rpc_submit_questionnaire('TPS-12', '{5,5,5,5,5,NULL,5,5,5,5,5,5}')$$, 'questionnaire_invalid_answers');
SELECT t_expect_err('TPS answer 6 out of range → 400', $$SELECT rpc_submit_questionnaire('TPS-12', '{6,5,5,5,5,5,5,5,5,5,5,5}')$$, 'questionnaire_invalid_answers');
RESET ROLE;
SELECT t_expect_err('answers immutable (WORM) even for owner', $$UPDATE questionnaire_submission SET answers = '{1}'$$, 'questionnaire_immutable');
SELECT t_expect_err('submissions cannot be deleted', $$DELETE FROM questionnaire_submission$$, 'questionnaire_immutable');
-- 30-day rule counts from team_joined_at (lock #5) — see section 10 for hires/transfers
-- HR-editable definitions
SELECT t_as('00000000-0000-0000-0000-00000000bbbb');
SET ROLE authenticated;
SELECT t_assert('v1.6.16: HR daily questionnaire → short participation setting, no per-questionnaire amount',
  (SELECT reward_amount IS NULL AND reward_setting_key = 'golden_spoons_per_short_questionnaire'
     FROM rpc_upsert_questionnaire_definition('MOOD', 'Mood', 'מצב רוח', 'daily', NULL, 1, 1, 5)));
SELECT t_assert('v1.6.16: HR monthly questionnaire → monthly participation setting',
  (SELECT reward_setting_key = 'golden_spoons_per_questionnaire'
     FROM rpc_upsert_questionnaire_definition('MONTHLYQ', 'Monthly', 'חודשי', 'monthly', NULL, 3, 1, 5)));
SELECT t_expect_http('v1.6.16: HR per-questionnaire amount refused → 400', $$SELECT rpc_upsert_questionnaire_definition('Q2', 'a', 'b', 'weekly', 3.0, 1)$$, 'questionnaire_reward_from_settings', 400);
SELECT t_expect_http('v1.6.16: HR 0.5 amount refused too → 400', $$SELECT rpc_upsert_questionnaire_definition('Q3', 'a', 'b', 'weekly', 0.5, 1)$$, 'questionnaire_reward_from_settings', 400);
SELECT t_expect_err('HR quarterly rejected', $$SELECT rpc_upsert_questionnaire_definition('Q4', 'a', 'b', 'quarterly', NULL, 1)$$, '23514');
SELECT t_expect_err('HR cannot edit locked TPS-12', $$SELECT rpc_upsert_questionnaire_definition('TPS-12', 'a', 'b', 'monthly', 1, 12)$$, 'questionnaire_locked');
RESET ROLE;
SELECT t_assert('period keys', fn_period_key('quarterly', '2026-10-20') = '2026-Q4' AND fn_period_key('monthly', '2026-10-20') = '2026-10');
SELECT t_as('00000000-0000-0000-0000-00000000aaaa');
SET ROLE authenticated;
SELECT t_assert('TPS team avg NULL when < 5 respondents (1 respondent in D9)',
  (SELECT tps_team_avg IS NULL AND tps_respondent_count = 1 FROM rpc_team_aggregate_refresh('00000000-0000-0000-0000-0000000000c1', 'D9')));
RESET ROLE;
SELECT t_assert('pcq12_monthly_reward table not created', to_regclass('public.pcq12_monthly_reward') IS NULL);
SELECT t_assert('tps_team_avg column exists, psc12 gone',
  EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'team_aggregate' AND column_name = 'tps_team_avg')
  AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE column_name ILIKE '%psc%'));

-- ============ 8. Golden → CHR 1:50 ============
-- v1.6.16 (Karin 30.10): the conversion is DEFINED (v2 readiness) but BLOCKED in v1 — every call → 422.
SELECT t_as(t_emp('D9', 3));   -- has 20.0 golden (v1.6.17: TPS-12 10 + PCQ-12 10)
SET ROLE authenticated;
SELECT t_expect_http('v1.6.16: convert 0.5 golden → 422 chr_coins_deferred_to_v2', $$SELECT rpc_convert_golden_to_chr(0.5, 'k1')$$, 'chr_coins_deferred_to_v2', 422);
SELECT t_expect_http('v1.6.16: convert 2 golden → 422 (same key again → 422, deterministic)', $$SELECT rpc_convert_golden_to_chr(2, 'k1')$$, 'chr_coins_deferred_to_v2', 422);
SELECT t_expect_http('v1.6.16: amount above balance → 422 (blocked before any check)', $$SELECT rpc_convert_golden_to_chr(100, 'k3')$$, 'chr_coins_deferred_to_v2', 422);
SELECT t_expect_http('v1.6.16: negative amount → 422', $$SELECT rpc_convert_golden_to_chr(-1, 'k4')$$, 'chr_coins_deferred_to_v2', 422);
SELECT t_expect_http('v1.6.16: 0.05 golden → 422', $$SELECT rpc_convert_golden_to_chr(0.05, 'k5')$$, 'chr_coins_deferred_to_v2', 422);
SELECT t_expect_err('v1.6.16: conversion error SQLSTATE is PT422 (PostgREST HTTP 422)', $$SELECT rpc_convert_golden_to_chr(1, 'k7')$$, 'PT422');
SELECT t_expect_err('no CHR→golden RPC exists', $$SELECT rpc_convert_chr_to_golden(50, 'k6')$$, '42883');
SELECT t_assert('v1.6.16: no balance change after blocked conversions (golden 20.0, CHR 0)',
  (SELECT golden_spoons = 20.0 AND chr_coins = 0 FROM avatar_state));
RESET ROLE;
SELECT t_assert('v1.6.16: no golden_chr_conversion row was written', NOT EXISTS (SELECT 1 FROM golden_chr_conversion));
SELECT t_assert('v1.6.16: rpc_convert_golden_to_chr stays defined + granted (v2 readiness)',
  to_regprocedure('rpc_convert_golden_to_chr(numeric, varchar)') IS NOT NULL
  AND has_function_privilege('authenticated', 'rpc_convert_golden_to_chr(numeric, varchar)', 'EXECUTE'));
SELECT t_expect_http('v1.6.16: blocked even for the service path (unconditional in v1)', $$SELECT rpc_convert_golden_to_chr(1, 'svc')$$, 'chr_coins_deferred_to_v2', 422);
SELECT t_assert('no reverse conversion function anywhere',
  NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname ~* '(chr|coin).*(to|2).*golden'));
SELECT t_expect_err('conversion rate pinned to 50', $$INSERT INTO golden_chr_conversion (user_id, golden_spent, rate, chr_received, idempotency_key) SELECT user_id, 1, 40, 40, 'x' FROM users LIMIT 1$$, '23514');
SELECT t_assert('golden_spoons is numeric(10,1)',
  (SELECT data_type = 'numeric' AND numeric_precision = 10 AND numeric_scale = 1 FROM information_schema.columns WHERE table_name = 'avatar_state' AND column_name = 'golden_spoons'));
SELECT t_assert('shop enum has basic/advanced/premium/custom and no Dutch tier (v1.6.13)',
  (SELECT array_agg(e::text) = '{basic,advanced,premium,custom}' FROM unnest(enum_range(NULL::shop_tier_enum)) e));
-- Shop works at ≤3 spoons (D9-1) — CB does not lock the shop
UPDATE avatar_state SET golden_spoons = 10 WHERE user_id = t_emp('D9', 1);
SELECT t_as(t_emp('D9', 1));
SET ROLE authenticated;
SELECT t_assert('shop allowed at 3 spoons (10 golden basic item)',
  (SELECT golden_spoons = 0 FROM rpc_everstore_purchase('theme_basement_office', 'p1')));
RESET ROLE;

-- ============ 9. Ledger ============
SELECT t_as('00000000-0000-0000-0000-00000000aaaa');
SET ROLE authenticated;
SELECT ledger_id IS NOT NULL AS appended FROM rpc_ledger_append('restoration_note', 1, 2, t_emp('D5', 1), '00000000-0000-0000-0000-0000000000c1', 'D5');
SELECT ledger_id IS NOT NULL AS appended FROM rpc_ledger_append('restoration_note', 3, 4, t_emp('D5', 2), '00000000-0000-0000-0000-0000000000c1', 'D5');
SELECT t_assert('ledger links previous_hash → current_hash (per company org_id chain, O-13)',
  (SELECT bool_and(l2.previous_hash = l1.current_hash)
     FROM manager_ledger l1
     JOIN manager_ledger l2 ON l2.org_id = l1.org_id AND l2.chain_seq = (
       SELECT min(l3.chain_seq) FROM manager_ledger l3 WHERE l3.org_id = l1.org_id AND l3.chain_seq > l1.chain_seq)));
SELECT t_assert('first entry has NULL previous_hash', (SELECT previous_hash IS NULL FROM manager_ledger ORDER BY chain_seq LIMIT 1));
SELECT t_assert('ledger stores pseudonym, never the user id',
  NOT EXISTS (SELECT 1 FROM manager_ledger l WHERE l::text LIKE '%' || t_emp('D5', 1)::text || '%'));
SELECT t_assert('ledger tax snapshot = team deprivation tax 24000', (SELECT bool_and(deprivation_tax_cost = 24000) FROM manager_ledger WHERE event_type <> 'GENESIS'));
SELECT t_expect_err('ledger UPDATE → ledger_immutable', $$UPDATE manager_ledger SET amount_a = 9$$, '42501');
RESET ROLE;
SELECT t_assert('chain verifies', fn_ledger_verify_chain('00000000-0000-0000-0000-0000000000c1'));
SELECT t_assert('current_hash = sha256(previous_hash || payload)',
  (SELECT bool_and(current_hash = encode(sha256(convert_to(COALESCE(previous_hash, '') || canonical_payload, 'UTF8')), 'hex')) FROM manager_ledger));
SELECT t_expect_err('ledger UPDATE (owner) → ledger_immutable', $$UPDATE manager_ledger SET amount_a = 9$$, 'ledger_immutable');
SELECT t_expect_err('ledger DELETE → ledger_immutable', $$DELETE FROM manager_ledger$$, 'ledger_immutable');
-- Crypto-shredding (lock #7): HR / manager on an active employee → 403; self works.
SELECT t_as('00000000-0000-0000-0000-00000000bbbb');
SET ROLE authenticated;
SELECT t_expect_err('HR cannot shred an active employee', format($$SELECT rpc_crypto_shred_pseudonym_key(%L)$$, t_emp('D5', 1)), 'crypto_shred_forbidden');
RESET ROLE;
SELECT t_as('00000000-0000-0000-0000-00000000aaaa');
SET ROLE authenticated;
SELECT t_expect_err('manager cannot shred an active employee', format($$SELECT rpc_crypto_shred_pseudonym_key(%L)$$, t_emp('D5', 1)), 'crypto_shred_forbidden');
RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', false);
SELECT t_expect_err('no-JWT / service caller cannot shred via the RPC', format($$SELECT rpc_crypto_shred_pseudonym_key(%L)$$, t_emp('D5', 1)), 'crypto_shred_forbidden');
SELECT t_assert('internal shred function has no client grant',
  NOT has_function_privilege('authenticated', 'fn_crypto_shred_pseudonym_key(uuid)', 'EXECUTE')
  AND NOT has_function_privilege('service_role', 'fn_crypto_shred_pseudonym_key(uuid)', 'EXECUTE'));
SELECT t_as(t_emp('D5', 1));
SET ROLE authenticated;
SELECT t_assert('employee shreds her own key (self-request)', (SELECT shredded_at IS NOT NULL FROM rpc_crypto_shred_pseudonym_key()));
RESET ROLE;
SELECT t_assert('crypto-shredding removes key material', (SELECT key_material IS NULL AND shredded_at IS NOT NULL FROM pseudonym_key WHERE user_id = t_emp('D5', 1)));
SELECT t_assert('chain still verifies after shredding', fn_ledger_verify_chain('00000000-0000-0000-0000-0000000000c1'));
SELECT t_as('00000000-0000-0000-0000-00000000aaaa');
SET ROLE authenticated;
SELECT t_expect_err('no new pseudonym for a shredded subject', format($$SELECT rpc_ledger_append('x', NULL, NULL, %L)$$, t_emp('D5', 1)), 'vault_sealed');
SELECT t_expect_err('clients cannot read pseudonym keys', $$SELECT * FROM pseudonym_key$$, '42501');
SELECT t_expect_err('clients cannot read HRV (v2 only)', $$SELECT * FROM hrv_sample$$, '42501');
RESET ROLE;
SELECT t_assert('hrv_sample kept and marked v2', obj_description('hrv_sample'::regclass) LIKE 'v2 ONLY%');


-- ============ 10. Red team alert (lock #4) — respondent-based N≥5 ============
-- D5 has 5 employees. Reset today's budgets: 4 reporters first, then 5.
SELECT fn_ensure_local_spoon_budget(t_emp('D5', i)) IS NOT NULL FROM generate_series(1, 5) i;
UPDATE spoon_budget sb SET current_spoon_count = 2, reported_at = NULL
  FROM users u WHERE u.user_id = sb.user_id AND u.department = 'D5';
UPDATE spoon_budget sb SET reported_at = clock_timestamp()
  FROM users u WHERE u.user_id = sb.user_id AND u.email IN ('D5-1@x', 'D5-2@x', 'D5-3@x', 'D5-4@x');
SELECT t_as('00000000-0000-0000-0000-00000000aaaa');
SET ROLE authenticated;
SELECT t_expect_err('red alert with 4 reporters → 403', $$SELECT * FROM rpc_team_spoon_alert('00000000-0000-0000-0000-0000000000c1', 'D5')$$, 'aggregation_privacy_threshold');
SELECT t_assert('refresh with 4 reporters → no average, no alert',
  (SELECT team_spoon_avg IS NULL AND dichotomous_alert_level IS NULL AND spoon_reporter_count = 4
     FROM rpc_team_aggregate_refresh('00000000-0000-0000-0000-0000000000c1', 'D5')));
RESET ROLE;
UPDATE spoon_budget sb SET reported_at = clock_timestamp() FROM users u WHERE u.user_id = sb.user_id AND u.email = 'D5-5@x';
SELECT t_as('00000000-0000-0000-0000-00000000aaaa');
SET ROLE authenticated;
SELECT t_assert('red alert with 5 reporters (avg 2 < 3) → RED',
  (SELECT alert_level = 'RED' AND reporter_count = 5 FROM rpc_team_spoon_alert('00000000-0000-0000-0000-0000000000c1', 'D5')));
SELECT t_assert('refresh with 5 reporters → RED stored',
  (SELECT dichotomous_alert_level = 'RED' AND spoon_reporter_count = 5 FROM rpc_team_aggregate_refresh('00000000-0000-0000-0000-0000000000c1', 'D5')));
SELECT t_assert('alert output has team-level columns only (level, avg, reporter count)',
  (SELECT proargnames FROM pg_proc WHERE proname = 'rpc_team_spoon_alert')
  = '{p_org_id,p_department,alert_level,team_spoon_avg,reporter_count}'::text[]);
CREATE TEMP TABLE t_alert_out AS SELECT r::text AS row_txt FROM rpc_team_spoon_alert('00000000-0000-0000-0000-0000000000c1', 'D5') r;
RESET ROLE;
SELECT t_assert('alert output contains no user id or pseudonym',
  NOT EXISTS (SELECT 1 FROM t_alert_out r, users u
               WHERE u.department = 'D5' AND (strpos(r.row_txt, u.user_id::text) > 0 OR strpos(r.row_txt, u.display_pseudonym) > 0)));
SELECT t_expect_err('stored alert without 5 reporters is rejected (CHECK)',
  $$INSERT INTO team_aggregate (org_id, department, contributor_count, team_spoon_avg, spoon_reporter_count, dichotomous_alert_level) VALUES ('00000000-0000-0000-0000-0000000000c1', 'X', 5, 2, 4, 'RED')$$, '23514');
SELECT t_as(t_emp('D5', 3));
SET ROLE authenticated;
SELECT t_expect_err('employee cannot read the team alert', $$SELECT * FROM rpc_team_spoon_alert('00000000-0000-0000-0000-0000000000c1', 'D5')$$, 'aggregation_privacy_threshold');
RESET ROLE;

-- ============ 11. Shop access (lock #6) ============
INSERT INTO avatar_state (user_id, golden_spoons) VALUES ('00000000-0000-0000-0000-00000000aaaa', 30)
  ON CONFLICT (user_id) DO UPDATE SET golden_spoons = 30;
SELECT t_as('00000000-0000-0000-0000-00000000aaaa');
SET ROLE authenticated;
SELECT t_assert('manager can buy in the shop', (SELECT golden_spoons = 20 FROM rpc_everstore_purchase('theme_somatic_zone', 'm1')));
SELECT t_expect_http('v1.6.16: manager conversion → 422 chr_coins_deferred_to_v2', $$SELECT rpc_convert_golden_to_chr(1, 'm2')$$, 'chr_coins_deferred_to_v2', 422);
SELECT t_assert('v1.6.16: manager balance unchanged (20, CHR 0)', (SELECT golden_spoons = 20 AND chr_coins = 0 FROM avatar_state));
RESET ROLE;
INSERT INTO auth.users (id) VALUES ('00000000-0000-0000-0000-00000000cccc');
INSERT INTO users (user_id, company_id, email, full_name, department, app_role, timezone, has_employee_profile)
VALUES ('00000000-0000-0000-0000-00000000cccc', '00000000-0000-0000-0000-0000000000c1', 'board@x', 'Board Chair', 'Board',
        'board_chair', 'Asia/Jerusalem', false);
INSERT INTO avatar_state (user_id, golden_spoons) VALUES ('00000000-0000-0000-0000-00000000cccc', 30);
SELECT t_as('00000000-0000-0000-0000-00000000cccc');
SET ROLE authenticated;
SELECT t_expect_err('board-only user (no employee profile) cannot buy', $$SELECT rpc_everstore_purchase('theme_somatic_zone', 'b1')$$, 'anti_get_blocked');
SELECT t_expect_http('v1.6.16: board-only user conversion → 422 too', $$SELECT rpc_convert_golden_to_chr(1, 'b2')$$, 'chr_coins_deferred_to_v2', 422);
RESET ROLE;
SELECT t_as(t_emp('D9', 6));
INSERT INTO avatar_state (user_id, golden_spoons) VALUES (t_emp('D9', 6), 10) ON CONFLICT (user_id) DO UPDATE SET golden_spoons = 10;
SET ROLE authenticated;
SELECT t_assert('regular employee can still buy', (SELECT golden_spoons = 0 FROM rpc_everstore_purchase('theme_basement_office', 'e1')));
RESET ROLE;

-- ============ 12. TPS 30-day rule from team_joined_at → hire_date → exempt (lock #5, O-49 21.10) ============
DO $$
DECLARE v uuid;
BEGIN
  FOREACH v IN ARRAY ARRAY['00000000-0000-0000-0000-0000000d0029'::uuid, '00000000-0000-0000-0000-0000000d0030'::uuid, '00000000-0000-0000-0000-0000000d0100'::uuid] LOOP
    INSERT INTO auth.users (id) VALUES (v);
  END LOOP;
  INSERT INTO users (user_id, company_id, email, full_name, department, app_role, timezone, hire_date) VALUES
    ('00000000-0000-0000-0000-0000000d0029', '00000000-0000-0000-0000-0000000000c1', 'h29@x', 'Hire 29', 'NEW', 'employee', 'Asia/Jerusalem', CURRENT_DATE - 29),
    ('00000000-0000-0000-0000-0000000d0030', '00000000-0000-0000-0000-0000000000c1', 'h30@x', 'Hire 30', 'NEW', 'employee', 'Asia/Jerusalem', CURRENT_DATE - 30),
    ('00000000-0000-0000-0000-0000000d0100', '00000000-0000-0000-0000-0000000000c1', 'h100@x', 'Veteran', 'NEW', 'employee', 'Asia/Jerusalem', CURRENT_DATE - 100);
END $$;
SELECT t_assert('new hire: no team_joined_at default (O-49) — the wait starts at hire_date (source hire)',
  (SELECT bool_and(u.team_joined_at IS NULL AND w.source = 'hire' AND w.wait_start = u.hire_date)
     FROM users u, fn_tps_wait_start(u.user_id) w WHERE u.email IN ('h29@x', 'h30@x', 'h100@x')));
SELECT t_as('00000000-0000-0000-0000-0000000d0029');
SET ROLE authenticated;
SELECT t_expect_err('new hire at 29 days → TPS not eligible', $$SELECT rpc_submit_questionnaire('TPS-12', '{3,3,3,3,3,3,3,3,3,3,3,3}')$$, 'questionnaire_not_eligible');
SELECT t_assert('new hire at 29 days may still answer Cantril (v1.6.17: monthly 10.0)', (SELECT reward_golden_spoons = 10.0 FROM rpc_submit_questionnaire('Cantril', '{5}')));
RESET ROLE;
SELECT t_as('00000000-0000-0000-0000-0000000d0030');
SET ROLE authenticated;
SELECT t_assert('new hire at 30 days → TPS eligible', (SELECT tps_12_score = 50 FROM rpc_submit_questionnaire('TPS-12', '{3,3,3,3,3,3,3,3,3,3,3,3}')));
RESET ROLE;
-- internal transfer of the veteran (100 days in company) to another team
UPDATE users SET department = 'NEW2' WHERE email = 'h100@x';
SELECT t_assert('transfer resets team_joined_at to the transfer time',
  (SELECT team_joined_at > clock_timestamp() - interval '1 minute' FROM users WHERE email = 'h100@x'));
SELECT t_as('00000000-0000-0000-0000-0000000d0100');
SET ROLE authenticated;
SELECT t_expect_err('transferred employee blocked again for 30 days', $$SELECT rpc_submit_questionnaire('TPS-12', '{3,3,3,3,3,3,3,3,3,3,3,3}')$$, 'questionnaire_not_eligible');
RESET ROLE;
UPDATE users SET team_joined_at = clock_timestamp() - interval '31 days' WHERE email = 'h100@x';
SELECT t_as('00000000-0000-0000-0000-0000000d0100');
SET ROLE authenticated;
SELECT t_assert('…and eligible again 30+ days after the transfer', (SELECT questionnaire_code = 'TPS-12' FROM rpc_submit_questionnaire('TPS-12', '{3,3,3,3,3,3,3,3,3,3,3,3}')));
RESET ROLE;

-- ============ B. v1.6.1 role tree, access, project, board, emergency, distress ============
-- Company C2 tree (solid line):
--   ceo ─┬─ vp1 ── div1 ─┬─ dept1 ─┬─ dm1 ── e1..e6
--        │               │         ├─ dm2 ── e7..e8   (dm2 has a DOTTED line to dm1)
--        │               │         └─ e9..e24
--        ├─ chro (vp, app_role vp_hr)   ├─ safety (safety_emergency_manager)   └─ pm (project_manager)
--   owner / board_chair / board_member: governance, no employee profile.
INSERT INTO companies (company_id, company_name, country, week_start_dow, last_workday_dow, timezone)
VALUES ('00000000-0000-0000-0000-0000000000c2', 'TreeCo', 'IL', 1, 5, 'Asia/Jerusalem');
CREATE OR REPLACE FUNCTION t_mk(p_code text, p_role text, p_app text, p_boss text, p_profile boolean DEFAULT true)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id) VALUES (v);
  INSERT INTO users (user_id, company_id, reports_to, email, full_name, department, app_role, org_role_code,
                     timezone, hire_date, has_employee_profile, phone)
  VALUES (v, '00000000-0000-0000-0000-0000000000c2',
          (SELECT user_id FROM users WHERE email = p_boss || '@c2'), p_code || '@c2', 'Person ' || p_code,
          'X', p_app, p_role, 'Asia/Jerusalem', CURRENT_DATE - 200, p_profile, '050-000' || length(p_code));
  RETURN v;
END $$;
CREATE OR REPLACE FUNCTION t_u(p_code text) RETURNS uuid LANGUAGE sql SECURITY DEFINER AS $$
  SELECT user_id FROM users WHERE email = p_code || '@c2'
$$;
GRANT EXECUTE ON FUNCTION t_u(text) TO authenticated;
SELECT t_mk('ceo', 'ceo', 'manager', NULL) IS NOT NULL;
SELECT t_mk('vp1', 'vp', 'manager', 'ceo') IS NOT NULL;
SELECT t_mk('chro', 'vp', 'vp_hr', 'ceo') IS NOT NULL;
SELECT t_mk('safety', 'safety_emergency_manager', 'employee', NULL) IS NOT NULL;   -- outside the tier cascade (lock 20.10)
SELECT t_mk('pm', 'project_manager', 'employee', 'ceo') IS NOT NULL;
SELECT t_mk('div1', 'division_manager', 'manager', 'vp1') IS NOT NULL;
SELECT t_mk('dept1', 'department_manager', 'manager', 'div1') IS NOT NULL;
SELECT t_mk('dm1', 'direct_manager', 'manager', 'dept1') IS NOT NULL;
SELECT t_mk('dm2', 'direct_manager', 'manager', 'dept1') IS NOT NULL;
UPDATE users SET dotted_line_to = t_u('dm1') WHERE user_id = t_u('dm2');
SELECT t_mk('e' || i, 'employee', 'employee', CASE WHEN i <= 6 THEN 'dm1' WHEN i <= 8 THEN 'dm2' ELSE 'dept1' END) IS NOT NULL
  FROM generate_series(1, 24) i;
SELECT t_mk('owner', 'owner_shareholder', 'owner_shareholder', NULL, false) IS NOT NULL;
SELECT t_mk('chair', 'board_chair', 'board_chair', NULL, false) IS NOT NULL;
SELECT t_mk('member', 'board_member', 'board_member', NULL, false) IS NOT NULL;
-- report spoons today for a list of C2 codes
CREATE OR REPLACE FUNCTION t_rep2(p_codes text[], p_spoons int DEFAULT 12) RETURNS void LANGUAGE plpgsql AS $$
DECLARE c text;
BEGIN
  FOREACH c IN ARRAY p_codes LOOP
    PERFORM fn_ensure_local_spoon_budget(t_u(c));
    UPDATE spoon_budget SET reported_at = clock_timestamp(), current_spoon_count = p_spoons
     WHERE user_id = t_u(c) AND budget_date = fn_user_local_date(t_u(c));
  END LOOP;
END $$;

-- ---- B1 role tree ----
SELECT t_assert('B1 roles seeded (14) with tiers 1–5',
  (SELECT count(*) = 14 AND min(tier) = 1 AND max(tier) = 5 FROM org_role)
  AND (SELECT string_agg(role_code, ',' ORDER BY role_code) FROM org_role) =
      'board_chair,board_member,ceo,department_manager,direct_manager,director,division_manager,employee,evp,functional_manager,owner_shareholder,project_manager,safety_emergency_manager,vp');
SELECT t_expect_err('B1 tier CHECK rejects 6', $$UPDATE org_role SET tier = 6 WHERE role_code = 'vp'$$, '23514');
SELECT t_assert('B1 users have reports_to + optional dotted_line_to + org_role_code',
  (SELECT count(*) = 3 FROM information_schema.columns WHERE table_name = 'users'
    AND column_name IN ('reports_to', 'dotted_line_to', 'org_role_code')));
SELECT t_assert('B1 recursive solid subtree of div1 reaches e1 (4 levels) and e24',
  (SELECT count(*) FILTER (WHERE user_id IN (t_u('e1'), t_u('e24'), t_u('dm2'))) = 3
          AND max(depth) = 3 FROM fn_solid_subtree(t_u('div1'))));
SELECT t_assert('B1 subtree excludes other branches (chro, safety)',
  NOT EXISTS (SELECT 1 FROM fn_solid_subtree(t_u('div1')) WHERE user_id IN (t_u('chro'), t_u('safety'))));
SELECT t_assert('B1 dotted line grants no subtree access (dm1 ⇢ dm2 team)',
  NOT fn_in_solid_subtree(t_u('dm1'), t_u('e7')) AND NOT fn_in_solid_subtree(t_u('dm1'), t_u('dm2')));
SELECT t_expect_err('B1 reporting cycle rejected', format($$UPDATE users SET reports_to = %L WHERE user_id = %L$$, t_u('e1'), t_u('dm1')), 'reporting_line_invalid');
SELECT t_expect_err('B1 self as manager rejected', format($$UPDATE users SET reports_to = user_id WHERE user_id = %L$$, t_u('e1')), 'reporting_line_invalid');
SELECT t_expect_err('B1 manager in another company rejected', format($$UPDATE users SET reports_to = %L WHERE user_id = %L$$, '00000000-0000-0000-0000-00000000aaaa', t_u('e1')), 'reporting_line_invalid');

-- ---- B2 access rules ----
SELECT t_rep2(ARRAY['e1','e2','e3','e4','e5','e6','e7','e8']);
SELECT t_as(t_u('e1'));
SET ROLE authenticated;
SELECT t_expect_err('B2 employee: no subtree access', $$SELECT * FROM rpc_subtree_summary()$$, 'access_denied');
SELECT t_expect_err('B2 employee: no pseudonym list', $$SELECT * FROM rpc_direct_reports_pseudonyms()$$, 'access_denied');
SELECT t_expect_err('B2 employee: no company averages', $$SELECT * FROM rpc_company_averages()$$, 'access_denied');
SELECT t_expect_err('B2 employee: no team aggregate', $$SELECT rpc_team_aggregate_refresh('00000000-0000-0000-0000-0000000000c2', 'X')$$, 'aggregation_privacy_threshold');
RESET ROLE;
SELECT t_as(t_u('dm1'));
SET ROLE authenticated;
SELECT t_assert('B2 manager sees her solid subtree (6 contributors)', (SELECT contributor_count = 6 FROM rpc_subtree_summary()));
SELECT t_expect_err('B2 manager: dotted-line team is not hers', format($$SELECT * FROM rpc_subtree_summary(%L)$$, t_u('dm2')), 'access_denied');
SELECT t_expect_err('B2 manager: peer branch denied', format($$SELECT * FROM rpc_subtree_summary(%L)$$, t_u('chro')), 'access_denied');
SELECT t_assert('B2 direct manager sees pseudonyms only (6, no names)',
  (SELECT count(*) = 6 AND bool_and(display_pseudonym NOT LIKE 'Person%') FROM rpc_direct_reports_pseudonyms()));
SELECT t_assert('B2 pseudonym list returns one column only',
  (SELECT proargnames FROM pg_proc WHERE proname = 'rpc_direct_reports_pseudonyms') = '{display_pseudonym}'::text[]);
RESET ROLE;
SELECT t_as(t_u('dm2'));
SET ROLE authenticated;
SELECT t_expect_err('B2 subtree with 2 contributors → 403', $$SELECT * FROM rpc_subtree_summary()$$, 'aggregation_privacy_threshold');
RESET ROLE;
SELECT t_as(t_u('div1'));
SET ROLE authenticated;
SELECT t_assert('B2 division manager drills into her subtree (dm1)', (SELECT contributor_count = 6 FROM rpc_subtree_summary(t_u('dm1'))));
SELECT t_assert('B2 division manager whole subtree (8)', (SELECT contributor_count = 8 FROM rpc_subtree_summary()));
RESET ROLE;
SELECT t_as(t_u('ceo'));
SET ROLE authenticated;
SELECT t_assert('B2 CEO sees company averages', (SELECT contributor_count = 8 AND team_spoon_avg = 12 FROM rpc_company_averages()));
SELECT t_expect_err('B2 CEO: no pseudonyms (averages only)', $$SELECT * FROM rpc_direct_reports_pseudonyms()$$, 'access_denied');
SELECT t_assert('B2 CEO: pseudonymous feeds return nothing', NOT fn_viewer_may_see_pseudonyms()
  AND (SELECT count(*) = 0 FROM early_leave_manager_v) AND (SELECT count(*) = 0 FROM cuckoo_alert_manager_v));
SELECT t_expect_err('B2 CEO: no named data', format($$SELECT * FROM rpc_chro_named_view(%L, 'x')$$, t_u('e1')), 'access_denied');
RESET ROLE;
SELECT t_as(t_u('owner'));
SET ROLE authenticated;
SELECT t_assert('B2 owner sees company averages', (SELECT contributor_count = 8 FROM rpc_company_averages()));
SELECT t_expect_err('B2 owner: no subtree drill-down', format($$SELECT * FROM rpc_subtree_summary(%L)$$, t_u('dm1')), 'access_denied');
SELECT t_expect_err('B2 owner: no pseudonyms', $$SELECT * FROM rpc_direct_reports_pseudonyms()$$, 'access_denied');
RESET ROLE;
SELECT t_as(t_u('chro'));
SET ROLE authenticated;
SELECT t_expect_err('B2 CHRO named data without reason → 400', format($$SELECT * FROM rpc_chro_named_view(%L, '  ')$$, t_u('e1')), 'reason_required');
SELECT t_assert('B2 CHRO named data with reason', (SELECT full_name = 'Person e1' FROM rpc_chro_named_view(t_u('e1'), 'בירור לפי חוק')));
SELECT t_expect_err('B2 CHRO: other company denied', format($$SELECT * FROM rpc_chro_named_view(%L, 'x')$$, t_emp('D5', 3)), 'access_denied');
RESET ROLE;
SELECT t_assert('B2 CHRO view audited with reason and subject',
  (SELECT count(*) = 1 FROM access_audit_log WHERE action = 'chro_named_view' AND subject_user_id = t_u('e1') AND reason = 'בירור לפי חוק'));
SELECT t_assert('B2 every manager view audited (subtree, pseudonyms, averages)',
  (SELECT count(DISTINCT action) = 3 FROM access_audit_log WHERE action IN ('subtree_summary', 'direct_reports_pseudonyms', 'company_averages')));
SELECT t_expect_err('B2 audit log is WORM', $$UPDATE access_audit_log SET reason = 'x'$$, 'ledger_immutable');
SELECT t_as(t_u('chro'));
SET ROLE authenticated;
SELECT t_expect_err('B2 audit log not readable by clients', $$SELECT count(*) FROM access_audit_log$$, '42501');
RESET ROLE;

-- ---- B3 project manager (v1.6.3: workload aggregates replace the removed load index) ----
-- v1.6.4 (Q4): fixture projects carry an explicit core choice (no default exists).
INSERT INTO project (project_id, company_id, name, project_manager_id, is_core) VALUES
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000c2', 'P1', t_u('pm'), true)
  ON CONFLICT DO NOTHING;
INSERT INTO project (project_id, company_id, name, project_manager_id, is_core) VALUES
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000c2', 'P2', t_u('pm'), true),
  ('00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000c2', 'P3', t_u('dm1'), true);
INSERT INTO project_member SELECT '00000000-0000-0000-0000-0000000000a1', t_u('e' || i) FROM generate_series(1, 6) i;
INSERT INTO project_member SELECT '00000000-0000-0000-0000-0000000000a2', t_u('e' || i) FROM generate_series(7, 12) i;
INSERT INTO project_member SELECT '00000000-0000-0000-0000-0000000000a3', t_u('e' || i) FROM generate_series(1, 6) i;
-- Fixture path (system): this week's self-report for a C2 employee.
CREATE OR REPLACE FUNCTION t_wr(p_code text, p_contract numeric, p_worked numeric, p_overtime numeric, p_parallel int,
                                p_week date DEFAULT NULL, p_stress smallint DEFAULT NULL, p_drop smallint DEFAULT NULL)
RETURNS void LANGUAGE sql AS $$
  INSERT INTO workload_self_report (user_id, company_id, work_date, contract_hours, hours_worked, overtime_hours,
                                    parallel_projects, stress_1to5, productivity_drop_1to5)
  VALUES (t_u(p_code), '00000000-0000-0000-0000-0000000000c2', COALESCE(p_week, fn_local_week_start(t_u(p_code))),
          p_contract, p_worked, p_overtime, p_parallel, p_stress, p_drop)
$$;
SELECT t_wr('e' || i, 40, 40, 0, 2) FROM generate_series(1, 6) i;     -- P1: 6 respondents, equal loads
SELECT t_wr('e' || i, 40, 40, 0, 1) FROM generate_series(7, 10) i;    -- P2: 4 respondents of 6 members
SELECT t_as(t_u('pm'));
SET ROLE authenticated;
SELECT t_assert('B3 PM sees project aggregates only (6 respondents, AIDB 100, PEWI = mean EPWI_time 40/40 = 1)',
  (SELECT respondent_count = 6 AND aidb = 100 AND aidb_band = 'target' AND pewi = 1
     FROM rpc_project_workload('00000000-0000-0000-0000-0000000000a1')));
SELECT t_assert('B3 PM result carries no individual data (column list)',
  (SELECT proargnames FROM pg_proc WHERE proname = 'rpc_project_workload')
  = '{p_project_id,p_week_start_date,week_start_date,respondent_count,pewi,aidb,aidb_band,trr,trr_band,m_spof,spof_alert}'::text[]);
SELECT t_expect_err('B3 project of 6 members with 4 respondents → 403',
  $$SELECT * FROM rpc_project_workload('00000000-0000-0000-0000-0000000000a2')$$, 'aggregation_privacy_threshold');
-- v1.6.7 P. PEWI alone (Karin 20.10): below 5 reporters → NULL + suppressed (no 403)
SELECT t_assert('P PEWI: 4 reporters → pewi NULL, suppressed = true (no 403)',
  (SELECT pewi IS NULL AND suppressed FROM rpc_project_pewi('00000000-0000-0000-0000-0000000000a2')));
SELECT t_assert('P PEWI: 6 reporters (40/40 each) → 1, not suppressed',
  (SELECT pewi = 1 AND NOT suppressed FROM rpc_project_pewi('00000000-0000-0000-0000-0000000000a1')));
SELECT t_expect_err('P PEWI: only the PM of the project', $$SELECT * FROM rpc_project_pewi('00000000-0000-0000-0000-0000000000a3')$$, 'access_denied');
SELECT t_expect_err('B3 PM: another PM''s project denied (no comparisons)',
  $$SELECT * FROM rpc_project_workload('00000000-0000-0000-0000-0000000000a3')$$, 'access_denied');
SELECT t_expect_err('B3 PM: no subtree / team aggregates', $$SELECT * FROM rpc_subtree_summary()$$, 'access_denied');
SELECT t_expect_err('B3 PM: no company averages', $$SELECT * FROM rpc_company_averages()$$, 'access_denied');
SELECT t_expect_err('B3 PM: no individual data', format($$SELECT * FROM rpc_chro_named_view(%L, 'x')$$, t_u('e1')), 'access_denied');
SELECT t_expect_err('B3 PM: no pseudonym feed', $$SELECT * FROM rpc_direct_reports_pseudonyms()$$, 'access_denied');
SELECT t_assert('B3 PM: no journals, open questionnaires, feedback or member self-reports',
  (SELECT count(*) = 0 FROM journal_entry) AND (SELECT count(*) = 0 FROM questionnaire_submission)
  AND (SELECT count(*) = 0 FROM spoon_budget) AND (SELECT count(*) = 0 FROM workload_self_report));
SELECT t_expect_err('B3 PM: membership table closed', $$SELECT count(*) FROM project_member$$, '42501');
RESET ROLE;
SELECT t_assert('B3 old v1.6.2 project load index removed', to_regprocedure('rpc_project_load(uuid)') IS NULL);
SELECT t_as(t_u('dm1'));
SET ROLE authenticated;
SELECT t_expect_err('B3 project view needs the project_manager role', $$SELECT * FROM rpc_project_workload('00000000-0000-0000-0000-0000000000a3')$$, 'access_denied');
RESET ROLE;
SELECT t_assert('B3 every project view audited', (SELECT count(*) = 1 FROM access_audit_log WHERE action = 'project_workload_view'));

-- ---- B4 board ----
-- TPS-12 history (system path): last closed quarter 20 respondents, the quarter before 19,
-- last year 20, and the current quarter 24 (must never show: no real-time).
INSERT INTO questionnaire_submission (user_id, questionnaire_code, period_key, local_date, answers, score, reward_golden_spoons, submitted_at)
SELECT t_u('e' || i), 'TPS-12', 'hist-' || p.k, p.d::date, '{3,3,3,3,3,3,3,3,3,3,3,3}', p.score, 0, p.d
  FROM (VALUES ('q-1', date_trunc('quarter', now()) - interval '1 month', 60, 20),
               ('q-2', date_trunc('quarter', now()) - interval '4 months', 40, 19),
               ('y-1', date_trunc('year', now()) - interval '9 months', 50, 20),
               ('now', now() - interval '1 hour', 90, 24)) AS p(k, d, score, n),
       generate_series(1, 24) i
 WHERE i <= p.n;
SELECT t_as(t_u('chair'));
SET ROLE authenticated;
SELECT t_assert('B4 board quarterly trend: only closed quarters with ≥20 respondents',
  (SELECT count(*) >= 1 AND bool_and(respondent_count >= 20)
          AND bool_and(period_start < date_trunc('quarter', now())::date)
          AND bool_or(period_start = (date_trunc('quarter', now()) - interval '3 months')::date AND tps_avg = 60)
     FROM rpc_board_macro_trends('quarter')));
SELECT t_assert('B4 quarter with 19 respondents suppressed',
  NOT EXISTS (SELECT 1 FROM rpc_board_macro_trends('quarter') WHERE period_start = (date_trunc('quarter', now()) - interval '6 months')::date));
SELECT t_assert('B4 no real-time: current quarter never shown',
  NOT EXISTS (SELECT 1 FROM rpc_board_macro_trends('quarter') WHERE period_start >= date_trunc('quarter', now())::date));
SELECT t_assert('B4 annual trend excludes the current year',
  (SELECT bool_and(period_start < date_trunc('year', now())::date) AND count(*) >= 1 FROM rpc_board_macro_trends('year')));
SELECT t_assert('B4 division-level trend', (SELECT count(*) >= 1 FROM rpc_board_macro_trends('quarter', t_u('div1'))));
SELECT t_expect_err('B4 no drill-down below division (department root)', format($$SELECT * FROM rpc_board_macro_trends('quarter', %L)$$, t_u('dept1')), 'access_denied');
SELECT t_expect_err('B4 no monthly / real-time granularity', $$SELECT * FROM rpc_board_macro_trends('month')$$, 'invalid_period');
SELECT t_assert('B4 / O-25 board sees whole-company organizational averages (never team or individual)',
  (SELECT contributor_count = 8 AND team_spoon_avg = 12 FROM rpc_company_averages()));
SELECT t_expect_err('B4 board: no subtree drill-down', $$SELECT * FROM rpc_subtree_summary()$$, 'access_denied');
RESET ROLE;
SELECT t_as(t_u('member'));
SET ROLE authenticated;
SELECT t_assert('B4 board member same macro view', (SELECT count(*) >= 1 FROM rpc_board_macro_trends('year')));
RESET ROLE;
SELECT t_as(t_u('ceo'));
SET ROLE authenticated;
SELECT t_expect_err('B4 board trends are board-only', $$SELECT * FROM rpc_board_macro_trends('year')$$, 'access_denied');
RESET ROLE;
SELECT t_as(t_u('chair'));
SET ROLE authenticated;
RESET ROLE;

-- ---- B5 safety & emergency manager ----
SELECT t_assert('B5 exactly the 3 locked emergency types (13.10)',
  (SELECT string_agg(t::text, ',') FROM unnest(enum_range(NULL::emergency_type_enum)) t) = 'health_or_life_danger,work_stopping_disaster,war_or_security');
SELECT t_expect_err('B5 placeholder type rejected', $$SELECT 'type_1'::emergency_type_enum$$, '22P02');
SELECT t_as(t_u('ceo'));
SET ROLE authenticated;
SELECT t_expect_err('B5 CEO cannot declare', $$SELECT rpc_emergency_declare('health_or_life_danger')$$, 'access_denied');
RESET ROLE;
SELECT t_as(t_u('chro'));
SET ROLE authenticated;
SELECT t_expect_err('B5 CHRO cannot declare', $$SELECT rpc_emergency_declare('work_stopping_disaster')$$, 'access_denied');
RESET ROLE;
SELECT t_as(t_u('dm1'));
SET ROLE authenticated;
SELECT t_expect_err('B5 manager cannot declare', $$SELECT rpc_emergency_declare('war_or_security')$$, 'access_denied');
RESET ROLE;
SELECT t_as(t_u('safety'));
SET ROLE authenticated;
SELECT t_assert('B5 safety manager declares (ACTIVE)', (SELECT status = 'ACTIVE' AND emergency_type = 'war_or_security' FROM rpc_emergency_declare('war_or_security')));
SELECT t_expect_err('B5 one active emergency per company → 409', $$SELECT rpc_emergency_declare('health_or_life_danger')$$, 'emergency_already_active');
SELECT t_assert('B5 immediate roster access (name + phone + location), no threshold',
  (SELECT count(*) >= 24 AND bool_and(full_name IS NOT NULL AND phone IS NOT NULL)
     FROM rpc_emergency_roster((SELECT event_id FROM emergency_event WHERE status = 'ACTIVE' AND company_id = '00000000-0000-0000-0000-0000000000c2'))));
RESET ROLE;
SELECT t_assert('B5 CHRO notified of declaration', (SELECT count(*) = 1 FROM notification WHERE recipient_id = t_u('chro') AND kind = 'emergency_declared'));
SELECT t_as(t_u('dm1'));
SET ROLE authenticated;
SELECT t_expect_err('B5 managers get no roster', format($$SELECT * FROM rpc_emergency_roster(%L)$$,
  (SELECT event_id FROM emergency_event WHERE status = 'ACTIVE' AND company_id = '00000000-0000-0000-0000-0000000000c2')), 'access_denied');
SELECT t_assert('B5 employees of the company see the active emergency', (SELECT count(*) = 1 FROM emergency_event WHERE status = 'ACTIVE'));
RESET ROLE;
CREATE TEMP TABLE t_ev AS SELECT event_id FROM emergency_event WHERE status = 'ACTIVE' AND company_id = '00000000-0000-0000-0000-0000000000c2';
GRANT SELECT ON t_ev TO authenticated;
SELECT t_as(t_u('e1'));
SET ROLE authenticated;
SELECT rpc_emergency_report_safe((SELECT event_id FROM t_ev)) IS NOT NULL AS safe_1;
RESET ROLE;
SELECT t_as(t_u('e2'));
SET ROLE authenticated;
SELECT rpc_emergency_report_safe((SELECT event_id FROM t_ev)) IS NOT NULL AS safe_2;
RESET ROLE;
SELECT t_as(t_u('e3'));
SET ROLE authenticated;
SELECT rpc_emergency_report_safe((SELECT event_id FROM t_ev)) IS NOT NULL AS safe_3;
RESET ROLE;
SELECT t_as(t_u('e4'));
SET ROLE authenticated;
SELECT rpc_emergency_report_safe((SELECT event_id FROM t_ev)) IS NOT NULL AS safe_4;
RESET ROLE;
SELECT t_as(t_u('e5'));
SET ROLE authenticated;
SELECT rpc_emergency_report_safe((SELECT event_id FROM t_ev)) IS NOT NULL AS safe_5;
RESET ROLE;
SELECT t_as(t_u('e6'));
SET ROLE authenticated;
SELECT rpc_emergency_report_safe((SELECT event_id FROM t_ev)) IS NOT NULL AS safe_6;
RESET ROLE;
SELECT t_as(t_u('e7'));
SET ROLE authenticated;
SELECT rpc_emergency_report_safe((SELECT event_id FROM t_ev)) IS NOT NULL AS safe_7;
RESET ROLE;
SELECT t_as(t_u('e8'));
SET ROLE authenticated;
SELECT rpc_emergency_report_safe((SELECT event_id FROM t_ev)) IS NOT NULL AS safe_8;
RESET ROLE;
SELECT t_as(t_u('e9'));
SET ROLE authenticated;
SELECT rpc_emergency_report_safe((SELECT event_id FROM t_ev)) IS NOT NULL AS safe_9;
RESET ROLE;
SELECT t_as(t_u('dm1'));
SET ROLE authenticated;
SELECT t_expect_err('B5 team status with 9 safe reports → 403 (N≥10)', format($$SELECT * FROM rpc_emergency_team_status(%L, 'X')$$, (SELECT event_id FROM t_ev)), 'aggregation_privacy_threshold');
RESET ROLE;
SELECT t_as(t_u('e10'));
SET ROLE authenticated;
SELECT rpc_emergency_report_safe((SELECT event_id FROM t_ev)) IS NOT NULL AS tenth;
RESET ROLE;
SELECT t_as(t_u('dm1'));
SET ROLE authenticated;
SELECT t_assert('B5 team status with 10 safe reports → shown', (SELECT safe_reporter_count = 10 FROM rpc_emergency_team_status((SELECT event_id FROM t_ev), 'X')));
SELECT t_expect_err('B5 manager cannot end the emergency', format($$SELECT rpc_emergency_end(%L)$$, (SELECT event_id FROM t_ev)), 'access_denied');
RESET ROLE;
SELECT t_as(t_u('chro'));
SET ROLE authenticated;
SELECT t_expect_err('B5 CHRO cannot end the emergency', format($$SELECT rpc_emergency_end(%L)$$, (SELECT event_id FROM t_ev)), 'access_denied');
SELECT t_expect_err('B5 HR review only after the end', format($$SELECT rpc_emergency_hr_review(%L, 'MISUSE')$$, (SELECT event_id FROM t_ev)), 'emergency_review_not_pending');
RESET ROLE;
SELECT t_as(t_u('safety'));
SET ROLE authenticated;
SELECT t_assert('B5 safety manager ends → HR review PENDING', (SELECT status = 'ENDED' AND hr_review_status = 'PENDING' FROM rpc_emergency_end((SELECT event_id FROM t_ev))));
SELECT t_expect_err('B5 misuse rule: no roster after the end', format($$SELECT * FROM rpc_emergency_roster(%L)$$, (SELECT event_id FROM t_ev)), 'emergency_not_active');
RESET ROLE;
SELECT t_assert('B5 CHRO asked for HR review', (SELECT count(*) = 1 FROM notification WHERE recipient_id = t_u('chro') AND kind = 'emergency_hr_review'));
SELECT t_as(t_u('dm1'));
SET ROLE authenticated;
SELECT t_expect_err('B5 HR review is CHRO-only', format($$SELECT rpc_emergency_hr_review(%L, 'JUSTIFIED')$$, (SELECT event_id FROM t_ev)), 'access_denied');
RESET ROLE;
SELECT t_as(t_u('chro'));
SET ROLE authenticated;
SELECT t_expect_err('B5 HR review outcome validated', format($$SELECT rpc_emergency_hr_review(%L, 'OK')$$, (SELECT event_id FROM t_ev)), 'invalid_review_outcome');
SELECT t_assert('B5 CHRO marks MISUSE', (SELECT hr_review_status = 'MISUSE' FROM rpc_emergency_hr_review((SELECT event_id FROM t_ev), 'MISUSE')));
SELECT t_expect_err('B5 review is final', format($$SELECT rpc_emergency_hr_review(%L, 'JUSTIFIED')$$, (SELECT event_id FROM t_ev)), 'emergency_review_not_pending');
RESET ROLE;
SELECT t_assert('B5 misuse recorded immutably in the audit log',
  (SELECT count(*) = 1 FROM access_audit_log WHERE action = 'emergency_misuse' AND scope->>'declared_by' = t_u('safety')::text));
SELECT t_assert('B5 declare / roster / end audited',
  (SELECT count(DISTINCT action) = 3 FROM access_audit_log WHERE action IN ('emergency_declare', 'emergency_roster', 'emergency_end')));

SELECT t_as(t_u('safety'));
SET ROLE authenticated;
SELECT t_assert('B5 health_or_life_danger can be declared and ended',
  (SELECT e.status = 'ENDED' FROM rpc_emergency_end((SELECT event_id FROM rpc_emergency_declare('health_or_life_danger'))) e));
SELECT t_assert('B5 work_stopping_disaster can be declared and ended',
  (SELECT e.status = 'ENDED' FROM rpc_emergency_end((SELECT event_id FROM rpc_emergency_declare('work_stopping_disaster'))) e));
RESET ROLE;

-- ---- B6 distress button ----
UPDATE users SET last_location = 'site' WHERE user_id IN (t_u('e1'), t_u('e2'), t_u('e3'));
SELECT t_assert('B6 no free-text / NLP columns on the distress record',
  NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name IN ('distress_event', 'distress_silent_log', 'notification')
               AND (data_type = 'text' AND column_name NOT IN ('status', 'last_location', 'kind'))));
SELECT t_assert('B6 press is manual and self-only (no user parameter)',
  (SELECT proargnames FROM pg_proc WHERE proname = 'rpc_distress_press') = '{p_location,event_id,grace_expires_at}'::text[]);
SELECT t_assert('B6 dispatch is a system job (not callable by clients)',
  NOT has_function_privilege('authenticated', 'rpc_distress_dispatch_job()', 'EXECUTE'));
SELECT t_as(t_u('chair'));
SET ROLE authenticated;
SELECT t_expect_err('B6 employee-only: board (no employee profile) cannot press', $$SELECT * FROM rpc_distress_press()$$, 'access_denied');
RESET ROLE;
SELECT t_as(t_u('e1'));
SET ROLE authenticated;
CREATE TEMP TABLE t_d1 AS SELECT * FROM rpc_distress_press();
SELECT t_assert('B6 press opens a 60-second grace',
  (SELECT grace_expires_at - clock_timestamp() BETWEEN interval '50 seconds' AND interval '60 seconds' FROM t_d1));
SELECT t_assert('B6 second press returns the same open event', (SELECT event_id FROM rpc_distress_press()) = (SELECT event_id FROM t_d1));
SELECT t_assert('B6 cancel inside grace', rpc_distress_cancel((SELECT event_id FROM t_d1)) = 'CANCELLED');
SELECT t_expect_err('B6 employee cannot read distress records', $$SELECT count(*) FROM distress_event$$, '42501');
RESET ROLE;
SELECT t_assert('B6 cancel → silent log row, nothing sent',
  (SELECT count(*) = 1 FROM distress_silent_log WHERE event_id = (SELECT event_id FROM t_d1))
  AND NOT EXISTS (SELECT 1 FROM notification WHERE ref_id = (SELECT event_id FROM t_d1)));
SELECT rpc_distress_dispatch_job() = 0 AS cancelled_not_dispatched;
SELECT t_assert('B6 cancelled event never dispatched', (SELECT status = 'CANCELLED' AND subject_name IS NULL FROM distress_event WHERE event_id = (SELECT event_id FROM t_d1)));
SELECT t_as(t_u('e2'));
SET ROLE authenticated;
CREATE TEMP TABLE t_d2 AS SELECT * FROM rpc_distress_press('office');
RESET ROLE;
SELECT rpc_distress_dispatch_job() = 0 AS not_before_60s;
SELECT t_assert('B6 nothing sent during the grace', NOT EXISTS (SELECT 1 FROM notification WHERE ref_id = (SELECT event_id FROM t_d2)));
-- simulate 61 seconds passing (system clock fixture)
UPDATE distress_event SET pressed_at = pressed_at - interval '61 seconds', grace_expires_at = grace_expires_at - interval '61 seconds'
 WHERE event_id = (SELECT event_id FROM t_d2);
SELECT t_as(t_u('e2'));
SET ROLE authenticated;
SELECT t_expect_err('B6 cancel after 60 s refused', format($$SELECT rpc_distress_cancel(%L)$$, (SELECT event_id FROM t_d2)), 'distress_grace_expired');
RESET ROLE;
SELECT t_assert('B6 dispatch after 60 s', rpc_distress_dispatch_job() = 1);
SELECT t_assert('B6 safety manager alerted, CHRO awareness only, nobody else',
  (SELECT string_agg(kind || '@' || CASE recipient_id WHEN t_u('safety') THEN 'safety' WHEN t_u('chro') THEN 'chro' ELSE 'other' END, ',' ORDER BY kind)
     FROM notification WHERE ref_id = (SELECT event_id FROM t_d2)) = 'distress_alert@safety,distress_awareness@chro');
SELECT t_assert('B6 notifications carry no PII columns',
  (SELECT string_agg(column_name, ',' ORDER BY column_name) FROM information_schema.columns WHERE table_name = 'notification')
  = 'created_at,kind,notification_id,recipient_id,ref_id,silent');
SELECT t_as(t_u('safety'));
SET ROLE authenticated;
SELECT t_assert('B6 safety inbox: name, phone, last location, timestamp',
  (SELECT subject_name = 'Person e2' AND subject_phone IS NOT NULL AND last_location = 'office' AND pressed_at IS NOT NULL
     FROM rpc_distress_safety_inbox() WHERE event_id = (SELECT event_id FROM t_d2)));
RESET ROLE;
SELECT t_as(t_u('chro'));
SET ROLE authenticated;
SELECT t_expect_err('B6 CHRO gets no PII inbox', $$SELECT * FROM rpc_distress_safety_inbox()$$, 'access_denied');
SELECT t_expect_err('B6 CHRO cannot close', format($$SELECT * FROM rpc_distress_close(%L, 'threat_removed')$$, (SELECT event_id FROM t_d2)), 'access_denied');
SELECT t_assert('B6 CHRO sees only her own notifications', (SELECT count(*) >= 1 AND bool_and(recipient_id = t_u('chro')) FROM notification));
RESET ROLE;
SELECT t_as(t_u('dm2'));
SET ROLE authenticated;
SELECT t_expect_err('B6 no team access opened: manager has no inbox', $$SELECT * FROM rpc_distress_safety_inbox()$$, 'access_denied');
SELECT t_expect_err('B6 manager cannot close', format($$SELECT * FROM rpc_distress_close(%L, 'threat_removed')$$, (SELECT event_id FROM t_d2)), 'access_denied');
SELECT t_assert('B6 manager not notified', (SELECT count(*) = 0 FROM notification));
RESET ROLE;
SELECT t_as(t_u('e2'));
SET ROLE authenticated;
SELECT t_expect_err('B6 presser cannot close', format($$SELECT * FROM rpc_distress_close(%L, 'threat_removed')$$, (SELECT event_id FROM t_d2)), 'access_denied');
RESET ROLE;
SELECT t_assert('B6 close reasons are exactly the 3 enums',
  (SELECT string_agg(r::text, ',') FROM unnest(enum_range(NULL::distress_close_reason_enum)) r) = 'threat_removed,referred_to_external_help,pressed_by_mistake');
SELECT t_as(t_u('safety'));
SET ROLE authenticated;
SELECT t_expect_err('B6 free-text close reason rejected', format($$SELECT * FROM rpc_distress_close(%L, 'all good')$$, (SELECT event_id FROM t_d2)), '22P02');
SELECT t_assert('B6 safety manager closes with reason', (SELECT status = 'CLOSED' FROM rpc_distress_close((SELECT event_id FROM t_d2), 'threat_removed')));
SELECT t_assert('B6 closed event leaves the safety view', NOT EXISTS (SELECT 1 FROM rpc_distress_safety_inbox() WHERE event_id = (SELECT event_id FROM t_d2)));
SELECT t_expect_err('B6 closed record cannot be closed again', format($$SELECT * FROM rpc_distress_close(%L, 'pressed_by_mistake')$$, (SELECT event_id FROM t_d2)), 'distress_record_immutable');
RESET ROLE;
SELECT t_assert('B6 PII removed on close',
  (SELECT user_id IS NULL AND subject_name IS NULL AND subject_phone IS NULL AND last_location IS NULL AND close_reason = 'threat_removed'
     FROM distress_event WHERE event_id = (SELECT event_id FROM t_d2)));
SELECT t_expect_err('B6 closed record read-only (even for the owner role)',
  format($$UPDATE distress_event SET close_reason = 'pressed_by_mistake' WHERE event_id = %L$$, (SELECT event_id FROM t_d2)), 'distress_record_immutable');
SELECT t_expect_err('B6 closed record cannot be deleted', format($$DELETE FROM distress_event WHERE event_id = %L$$, (SELECT event_id FROM t_d2)), 'distress_record_immutable');
SELECT t_assert('B6 immutable audit row on close',
  (SELECT count(*) = 1 FROM access_audit_log WHERE action = 'distress_closed' AND scope->>'event_id' = (SELECT event_id FROM t_d2)::text));
SELECT t_expect_err('B6 close audit row is WORM', $$DELETE FROM access_audit_log WHERE action = 'distress_closed'$$, 'ledger_immutable');
SELECT t_assert('B6 CHRO silent notice on close',
  (SELECT count(*) = 1 AND bool_and(silent) FROM notification WHERE ref_id = (SELECT event_id FROM t_d2) AND kind = 'distress_closed' AND recipient_id = t_u('chro')));
-- False alarm: pressed, dispatched, closed as pressed_by_mistake → excluded from analytics.
SELECT t_as(t_u('e3'));
SET ROLE authenticated;
CREATE TEMP TABLE t_d3 AS SELECT * FROM rpc_distress_press();
RESET ROLE;
UPDATE distress_event SET pressed_at = pressed_at - interval '61 seconds', grace_expires_at = grace_expires_at - interval '61 seconds'
 WHERE event_id = (SELECT event_id FROM t_d3);
SELECT rpc_distress_dispatch_job() = 1 AS third_dispatched;
SELECT t_as(t_u('safety'));
SET ROLE authenticated;
SELECT (SELECT status FROM rpc_distress_close((SELECT event_id FROM t_d3), 'pressed_by_mistake')) = 'CLOSED' AS false_alarm_closed;
RESET ROLE;
SELECT t_assert('B6 analytics exclude false alarms (only threat_removed counted)',
  (SELECT string_agg(close_reason || '=' || events, ',') FROM distress_analytics_v WHERE company_id = '00000000-0000-0000-0000-0000000000c2') = 'threat_removed=1');
SELECT t_assert('B6 analytics view closed to clients', NOT has_table_privilege('authenticated', 'distress_analytics_v', 'SELECT'));

-- ============ v1.6.3 C. Cuckoo rolling 30-day reporter window (lock 20.10) ============
DO $$
DECLARE i int; v_uid uuid;
BEGIN
  FOR i IN 1..10 LOOP
    v_uid := gen_random_uuid();
    INSERT INTO auth.users (id) VALUES (v_uid);
    INSERT INTO users (user_id, company_id, reports_to, email, full_name, department, app_role, timezone, hire_date)
    VALUES (v_uid, '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-00000000aaaa',
            'DW-' || i || '@x', 'Real Name DW-' || i, 'DW', 'employee', 'Asia/Jerusalem', CURRENT_DATE - 100);
  END LOOP;
END $$;
-- Move one DW reporter's last report to a given day (day 1 = within the last 24 h).
CREATE OR REPLACE FUNCTION t_report_day(p_i int, p_day int) RETURNS void LANGUAGE sql AS $$
  UPDATE spoon_budget SET reported_at = clock_timestamp() - make_interval(days => p_day - 1) - interval '12 hours'
   WHERE user_id = t_emp('DW', p_i)
$$;
SELECT t_report('DW', 10);
SELECT t_assert('C cuckoo window locked: rolling 30 days', fn_cuckoo_window() = interval '30 days');
SELECT t_report_day(10, 31);
SELECT t_assert('C day 31 is outside the window (9 recent reporters)',
  fn_cuckoo_recent_reporters('00000000-0000-0000-0000-0000000000c1', 'DW') = 9);
SELECT t_expect_err('C boundary: 9 in window + 1 on day 31 → 403',
  format($$SELECT fn_cuckoo_raise(%L, 'nlp_distress')$$, t_emp('DW', 1)), 'aggregation_privacy_threshold');
SELECT t_report_day(10, 30);
SELECT t_assert('C day 30 is inside the window (10 recent reporters)',
  fn_cuckoo_recent_reporters('00000000-0000-0000-0000-0000000000c1', 'DW') = 10);
SELECT t_assert('C boundary: reporter on day 30 counts → 10 → Cuckoo raised',
  (SELECT status IS NOT NULL FROM fn_cuckoo_raise(t_emp('DW', 1), 'nlp_distress')));
SELECT t_report_day(9, 45);
SELECT t_expect_err('C threshold: 9 recent reporters → 403',
  format($$SELECT fn_cuckoo_raise(%L, 'nlp_distress')$$, t_emp('DW', 2)), 'aggregation_privacy_threshold');
SELECT t_report_day(9, 2);
SELECT t_assert('C threshold: 10 recent reporters → passes',
  (SELECT status IS NOT NULL FROM fn_cuckoo_raise(t_emp('DW', 2), 'nlp_distress')));

-- ============ v1.6.3 W. Workload formulas (locked numbers) ============
SELECT t_assert('W L(P) locked: 1→0, 2→20, 3→40, 4→60, 5→75 %',
  (SELECT string_agg(parallel_projects || ':' || loss_fraction, ',' ORDER BY parallel_projects) FROM context_switch_loss_config)
  = '1:0.00,2:0.20,3:0.40,4:0.60,5:0.75');
SELECT t_expect_err('W L(P) table is pinned by CHECK', $$UPDATE context_switch_loss_config SET loss_fraction = 0.17 WHERE parallel_projects = 3$$, '23514');
SELECT t_assert('W P>5 counts as 5 (Karin Q3, v1.6.4): L(6) = 0.75, EPWI_cognitive(0.9, 6) = 3.60; P=0 still NULL',
  fn_context_switch_loss(6) = 0.75 AND fn_epwi_cognitive(0.9, 6) = 3.6 AND fn_epwi_cognitive(0.9, 0) IS NULL);
SELECT t_assert('W EPWI_time = Σ(T×D)/W: 36/40 = 0.90 → target', fn_epwi_time(36, 40) = 0.9 AND fn_epwi_time_band(fn_epwi_time(36, 40)) = 'target');
SELECT t_assert('W EPWI_time 0.75 → target (lower edge)', fn_epwi_time_band(fn_epwi_time(30, 40)) = 'target');
SELECT t_assert('W EPWI_time 0.725 → below target', fn_epwi_time_band(fn_epwi_time(29, 40)) = 'below_target');
SELECT t_assert('W EPWI_time 1.00 → not yet overload', fn_epwi_time_band(fn_epwi_time(40, 40)) = 'above_target');
SELECT t_assert('W EPWI_time 1.01 → overload (>1.00)', fn_epwi_time_band(fn_epwi_time(40.4, 40)) = 'overload');
SELECT t_assert('W EPWI_time NULL when capacity 0', fn_epwi_time(10, 0) IS NULL);
SELECT t_assert('W EPWI_cognitive P=1: 0.90/(1−0) = 0.90 → target', fn_epwi_cognitive(0.9, 1) = 0.9 AND fn_epwi_cognitive_band(0.9) = 'target');
SELECT t_assert('W EPWI_cognitive P=2: 0.88/(1−0.20) = 1.10 → target', fn_epwi_cognitive(0.88, 2) = 1.1 AND fn_epwi_cognitive_band(fn_epwi_cognitive(0.88, 2)) = 'target');
SELECT t_assert('W EPWI_cognitive P=3: 0.90/(1−0.40) = 1.50 → not yet overload', fn_epwi_cognitive(0.9, 3) = 1.5 AND fn_epwi_cognitive_band(1.5) = 'above_target');
SELECT t_assert('W EPWI_cognitive P=4: 0.90/(1−0.60) = 2.25 → overload (>1.50)', fn_epwi_cognitive(0.9, 4) = 2.25 AND fn_epwi_cognitive_band(2.25) = 'overload');
SELECT t_assert('W EPWI_cognitive P=5: 0.90/(1−0.75) = 3.60', fn_epwi_cognitive(0.9, 5) = 3.6);
SELECT t_assert('W B_t = 0.41·S + 0.37·O + 0.22·D: stress 3, overtime 5 h, drop 3 → 0.205 + 0.185 + 0.11 = 0.50 → medium',
  fn_b_t(3, 5, 3) = 0.5 AND fn_b_t_band(fn_b_t(3, 5, 3)) = 'medium');
SELECT t_assert('W B_t stress weight 0.41 (stress 5, rest 0)', fn_b_t(5, 0, 1) = 0.41);
SELECT t_assert('W B_t productivity-drop weight is POSITIVE 0.22 (drop 5, rest 0)', fn_b_t(1, 0, 5) = 0.22);
SELECT t_assert('W B_t bands: <0.35 low, 0.35 medium, 0.6499 medium, ≥0.65 high',
  fn_b_t_band(0.3499) = 'low' AND fn_b_t_band(0.35) = 'medium' AND fn_b_t_band(0.6499) = 'medium' AND fn_b_t_band(0.65) = 'high');
SELECT t_assert('W AIDB = (1 − 9/50) × 100 = 82 → target (>80)', fn_aidb(9, 50) = 82 AND fn_aidb_band(82) = 'target');
SELECT t_assert('W AIDB 80 is not above target', fn_aidb(10, 50) = 80 AND fn_aidb_band(80) = 'below_target');
SELECT t_assert('W AIDB 64 → selective burnout risk (<65); 65 is not', fn_aidb(18, 50) = 64
  AND fn_aidb_band(64) = 'selective_burnout_risk' AND fn_aidb_band(65) = 'below_target');
SELECT t_assert('W AIDB of loads {30,40,50} = 79.59 (population σ)', round(fn_aidb_of(ARRAY[30, 40, 50]::numeric[]), 2) = 79.59);
SELECT t_assert('W TRR = 19/100 = 19 % → planning failure (>18 %)', fn_trr(19, 100) = 19 AND fn_trr_band(19) = 'planning_failure');
SELECT t_assert('W TRR 18 % is not a planning failure', fn_trr_band(fn_trr(18, 100)) = 'ok');
SELECT t_assert('W M_SPOF = 1 + 2/8 = 1.25', fn_m_spof(2, 8) = 1.25 AND fn_m_spof(0, 8) = 1 AND fn_m_spof(1, 0) IS NULL);

-- ============ v1.6.3 W. Self-report, employee-only RLS, PM N≥5, audit ============
SELECT t_as(t_u('e13'));
SET ROLE authenticated;
SELECT t_assert('W employee submits her weekly self-report', (SELECT extract(dow FROM week_start_date) = 1 AND week_start_date > CURRENT_DATE - 7
   FROM rpc_submit_workload_self_report(40, 44, 4, 3)));
SELECT t_expect_err('W one self-report per week → 409', $$SELECT * FROM rpc_submit_workload_self_report(40, 40, 0, 1)$$, 'workload_report_already_submitted');
SELECT t_assert('W personal indices: EPWI_time 44/40 = 1.10 overload; EPWI_cognitive 1.10/0.60 = 1.8333 overload; B_t NULL (stress / drop not answered)',
  (SELECT epwi_time = 1.1 AND epwi_time_band = 'overload' AND round(epwi_cognitive, 4) = 1.8333
          AND epwi_cognitive_band = 'overload' AND b_t IS NULL FROM rpc_my_workload_indices()));
SELECT t_assert('W employee sees her own self-report', (SELECT count(*) = 1 FROM workload_self_report));
SELECT t_expect_err('W self-report is WORM', $$UPDATE workload_self_report SET hours_worked = 1$$, '42501');
RESET ROLE;
SELECT t_as(t_u('e14'));
SET ROLE authenticated;
SELECT t_expect_err('W invalid answers (overtime > hours) → 400', $$SELECT * FROM rpc_submit_workload_self_report(40, 10, 12, 1)$$, 'workload_invalid_answers');
SELECT t_expect_err('W invalid answers (capacity 0) → 400', $$SELECT * FROM rpc_submit_workload_self_report(0, 10, 0, 1)$$, 'workload_invalid_answers');
SELECT t_assert('W another employee cannot see her self-report (RLS)', (SELECT count(*) = 0 FROM workload_self_report));
SELECT t_assert('W no indices for another employee (no report of her own)', (SELECT count(*) = 0 FROM rpc_my_workload_indices()));
RESET ROLE;
SELECT t_assert('W personal-index RPC has no user parameter (self only)',
  (SELECT pronargs = 1 AND proargnames[1] = 'p_week_start_date' FROM pg_proc WHERE proname = 'rpc_my_workload_indices'));
SELECT t_as(t_u('dm2'));
SET ROLE authenticated;
SELECT t_assert('W direct manager sees no self-reports', (SELECT count(*) = 0 FROM workload_self_report));
RESET ROLE;
SELECT t_as(t_u('chro'));
SET ROLE authenticated;
SELECT t_assert('W CHRO sees no self-reports', (SELECT count(*) = 0 FROM workload_self_report));
RESET ROLE;
SELECT t_as(t_u('ceo'));
SET ROLE authenticated;
SELECT t_assert('W CEO sees no self-reports', (SELECT count(*) = 0 FROM workload_self_report));
RESET ROLE;
SELECT t_wr('e11', 40, 60, 20, 1);     -- P2: 5th respondent
CREATE TEMP TABLE t_pm_last_week AS SELECT fn_local_week_start(t_u('pm')) - 7 AS wk;   -- company week, not ISO
GRANT SELECT ON t_pm_last_week TO authenticated;
SELECT t_as(t_u('pm'));
SET ROLE authenticated;
SELECT t_assert('W PM: 5 respondents → passes; AIDB loads {40,40,40,40,60} = 81.82 target; PEWI (1+1+1+1+1.5)/5 = 1.1; TRR NULL',
  (SELECT respondent_count = 5 AND round(aidb, 2) = 81.82 AND aidb_band = 'target' AND pewi = 1.1 AND trr IS NULL AND trr_band IS NULL
     FROM rpc_project_workload('00000000-0000-0000-0000-0000000000a2')));
SELECT t_assert('W PM: no SPOF data in v1 → M_SPOF NULL', (SELECT m_spof IS NULL AND spof_alert IS NULL FROM rpc_project_workload('00000000-0000-0000-0000-0000000000a1')));
SELECT t_expect_err('W PM: last week has <5 respondents → 403',
  format($$SELECT * FROM rpc_project_workload('00000000-0000-0000-0000-0000000000a1', %L)$$, (SELECT wk FROM t_pm_last_week)), 'aggregation_privacy_threshold');
SELECT t_expect_err('W PM cannot read SPOF items directly', $$SELECT count(*) FROM project_spof_item$$, '42501');
SELECT t_assert('P PEWI: 5 reporters (EPWI_time 1, 1, 1, 1, 1.5) → mean 1.1, not suppressed',
  (SELECT pewi = 1.1 AND NOT suppressed FROM rpc_project_pewi('00000000-0000-0000-0000-0000000000a2')));
SELECT t_assert('P PEWI: last week below 5 → NULL + suppressed (no 403)',
  (SELECT pewi IS NULL AND suppressed AND week_start_date = (SELECT wk FROM t_pm_last_week)
     FROM rpc_project_pewi('00000000-0000-0000-0000-0000000000a1', (SELECT wk FROM t_pm_last_week))));
RESET ROLE;
SELECT t_assert('P every PEWI view audited (project, week, suppressed flag; never values)',
  (SELECT count(*) = 4 AND bool_and(scope ? 'project_id' AND scope ? 'week_start_date' AND scope ? 'suppressed' AND NOT scope ? 'pewi')
     FROM access_audit_log WHERE action = 'project_pewi_view')
  AND (SELECT count(*) FILTER (WHERE (scope->>'suppressed')::boolean) = 2 FROM access_audit_log WHERE action = 'project_pewi_view'));
SELECT t_assert('P PEWI output has no individual fields (week, pewi, suppressed only)',
  (SELECT proargnames FROM pg_proc WHERE proname = 'rpc_project_pewi') = '{p_project_id,p_week_start_date,week_start_date,pewi,suppressed}'::text[]);
SELECT t_assert('P PEWI helper and table not callable / readable by clients',
  NOT has_function_privilege('authenticated', 'fn_project_pewi_of(uuid, date)', 'EXECUTE')
  AND has_function_privilege('authenticated', 'rpc_project_pewi(uuid, date)', 'EXECUTE'));
SELECT t_assert('W every PM view audited with project and week',
  (SELECT count(*) = 3 AND bool_and(scope ? 'project_id' AND scope ? 'week_start_date') FROM access_audit_log WHERE action = 'project_workload_view'));
INSERT INTO project_spof_item (project_id, item_ref, is_critical, single_holder)
SELECT '00000000-0000-0000-0000-0000000000a1', 'TASK-' || i, i <= 3, i <= 2 FROM generate_series(1, 8) i;
SELECT t_as(t_u('pm'));
SET ROLE authenticated;
SELECT t_assert('W SPOF: 2 critical single-holder items of 8 → M_SPOF 1.25 + alert',
  (SELECT m_spof = 1.25 AND spof_alert FROM rpc_project_workload('00000000-0000-0000-0000-0000000000a1')));
RESET ROLE;
SELECT t_assert('W SPOF items have no employee column',
  (SELECT string_agg(column_name, ',' ORDER BY column_name) FROM information_schema.columns WHERE table_name = 'project_spof_item')
  = 'is_critical,item_id,item_ref,project_id,single_holder,source,updated_at');
SELECT t_assert('W project workload output has no employee column',
  NOT EXISTS (SELECT 1 FROM unnest((SELECT proargnames FROM pg_proc WHERE proname = 'rpc_project_workload')) a WHERE a LIKE '%user%' OR a LIKE '%employee%'));
SELECT t_assert('W v2 adapter stub does nothing', rpc_workload_integration_sync('jira') = 'not_implemented_v2'
  AND rpc_workload_integration_sync('asana') = 'not_implemented_v2' AND rpc_workload_integration_sync('monday') = 'not_implemented_v2');
SELECT t_expect_err('W v2 adapter: unknown provider → 400', $$SELECT rpc_workload_integration_sync('trello')$$, 'invalid_provider');
SELECT t_assert('W v2 adapter is system-only', NOT has_function_privilege('authenticated', 'rpc_workload_integration_sync(text)', 'EXECUTE'));

-- ============ v1.6.3 WIP soft limit (lock 3) ============
SELECT t_assert('WIP: two core projects → no alert', (SELECT count(*) = 0 FROM wip_alert WHERE recipient_id = t_u('e1')));
SELECT t_as(t_u('pm'));
SET ROLE authenticated;
SELECT t_assert('WIP: third core assignment succeeds — no blocking', (SELECT core_assignment_count = 3
   FROM rpc_project_assign_member('00000000-0000-0000-0000-0000000000a2', t_u('e1'))));
SELECT t_assert('WIP: PM alert carries the count only', (SELECT count(*) = 1 AND bool_and(core_assignment_count = 3 AND audience = 'project_manager')
   FROM wip_alert));
CREATE TEMP TABLE t_nc1 AS SELECT project_id FROM rpc_project_create('NC1', false);
SELECT t_assert('WIP: assignment to a non-core project raises no alert (v1.6.4: core = project toggle)', (SELECT core_assignment_count = 2
   FROM rpc_project_assign_member((SELECT project_id FROM t_nc1), t_u('e2'))));
SELECT t_expect_err('WIP: PM cannot assign to another PM''s project', format($$SELECT * FROM rpc_project_assign_member(%L, %L)$$,
  '00000000-0000-0000-0000-0000000000a3', t_u('e3')), 'access_denied');
RESET ROLE;
SELECT t_as(t_u('e1'));
SET ROLE authenticated;
SELECT t_assert('WIP: the employee gets her own alert', (SELECT count(*) = 1 AND bool_and(audience = 'employee' AND core_assignment_count = 3) FROM wip_alert));
RESET ROLE;
SELECT t_assert('WIP: alert table has no wellbeing or employee-subject column',
  (SELECT string_agg(column_name, ',' ORDER BY column_name) FROM information_schema.columns WHERE table_name = 'wip_alert')
  = 'alert_id,audience,core_assignment_count,created_at,project_id,recipient_id');
SELECT t_assert('WIP: e2 got no alert', NOT EXISTS (SELECT 1 FROM wip_alert WHERE recipient_id = t_u('e2')));

-- ============ v1.6.3 D. Distress delivery: push AND sms together at dispatch (lock 20.10) ============
SELECT t_assert('D both channels queued for the safety manager at dispatch',
  (SELECT string_agg(channel, ',' ORDER BY channel) FROM distress_alert_delivery WHERE event_id = (SELECT event_id FROM t_d2)) = 'push,sms');
SELECT t_assert('D push and sms share one timestamp (same transaction, no wait)',
  (SELECT count(DISTINCT queued_at) = 1 AND count(*) = 2 FROM distress_alert_delivery WHERE event_id = (SELECT event_id FROM t_d3)));
SELECT t_assert('D delivery rows do not reference each other (no fallback / ordering column)',
  (SELECT string_agg(column_name, ',' ORDER BY column_name) FROM information_schema.columns WHERE table_name = 'distress_alert_delivery')
  = 'attempted_at,channel,delivery_id,event_id,queued_at,recipient_id,status');
SELECT t_assert('D nothing delivered for a grace-cancelled press', NOT EXISTS (SELECT 1 FROM distress_alert_delivery WHERE event_id = (SELECT event_id FROM t_d1)));
UPDATE distress_alert_delivery SET status = 'FAILED' WHERE event_id = (SELECT event_id FROM t_d3) AND channel = 'sms';
SELECT t_assert('D an SMS failure leaves push untouched', (SELECT status = 'QUEUED' FROM distress_alert_delivery WHERE event_id = (SELECT event_id FROM t_d3) AND channel = 'push'));
SELECT t_assert('D delivery job attempts each queued channel on its own', rpc_distress_delivery_job() = 3);
SELECT t_assert('D both stubs report provider not configured (SMS adapter TODO להשלמה)',
  (SELECT count(*) = 3 AND bool_and(status = 'PROVIDER_NOT_CONFIGURED' AND attempted_at IS NOT NULL) FROM distress_alert_delivery WHERE status <> 'FAILED'));
SELECT t_assert('D delivery job and table are system-only', NOT has_function_privilege('authenticated', 'rpc_distress_delivery_job()', 'EXECUTE')
  AND NOT has_table_privilege('authenticated', 'distress_alert_delivery', 'SELECT'));
SELECT t_assert('D 60-second cancel window unchanged', EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_distress_grace_60s'));

-- ============ v1.6.3 S. Safety & emergency manager — outside the tiers, least privilege (lock 20.10) ============
SELECT t_assert('S safety manager has no tier', (SELECT tier IS NULL AND NOT is_management FROM org_role WHERE role_code = 'safety_emergency_manager'));
SELECT t_expect_err('S safety manager cannot be put on a tier', $$UPDATE org_role SET tier = 2 WHERE role_code = 'safety_emergency_manager'$$, '23514');
SELECT t_expect_err('S other roles must stay on a tier', $$UPDATE org_role SET tier = NULL WHERE role_code = 'vp'$$, '23514');
SELECT t_expect_err('S safety manager reports to nobody (no cascade)', format($$UPDATE users SET reports_to = %L WHERE user_id = %L$$, t_u('ceo'), t_u('safety')), 'reporting_line_invalid');
SELECT t_expect_err('S nobody reports to the safety manager', format($$UPDATE users SET reports_to = %L WHERE user_id = %L$$, t_u('safety'), t_u('e20')), 'reporting_line_invalid');
SELECT t_expect_err('S no dotted line to the safety manager', format($$UPDATE users SET dotted_line_to = %L WHERE user_id = %L$$, t_u('safety'), t_u('e20')), 'reporting_line_invalid');
SELECT t_assert('S not part of any tier cascade (CEO subtree excludes her)',
  NOT EXISTS (SELECT 1 FROM fn_solid_subtree(t_u('ceo')) WHERE user_id = t_u('safety')));
SELECT t_as(t_u('safety'));
SET ROLE authenticated;
SELECT t_expect_err('S denied: team / subtree wellbeing', $$SELECT * FROM rpc_subtree_summary()$$, 'access_denied');
SELECT t_expect_err('S denied: company wellbeing averages', $$SELECT * FROM rpc_company_averages()$$, 'access_denied');
SELECT t_expect_err('S denied: team aggregate', $$SELECT rpc_team_aggregate_refresh('00000000-0000-0000-0000-0000000000c2', 'X')$$, 'aggregation_privacy_threshold');
SELECT t_expect_err('S denied: team spoon alert', $$SELECT * FROM rpc_team_spoon_alert('00000000-0000-0000-0000-0000000000c2', 'X')$$, 'aggregation_privacy_threshold');
SELECT t_expect_err('S denied: team pseudonyms', $$SELECT * FROM rpc_direct_reports_pseudonyms()$$, 'access_denied');
SELECT t_expect_err('S denied: project load / EPWI aggregates', $$SELECT * FROM rpc_project_workload('00000000-0000-0000-0000-0000000000a1')$$, 'access_denied');
SELECT t_assert('S denied: employees'' EPWI self-reports (RLS)', (SELECT count(*) = 0 FROM workload_self_report));
SELECT t_assert('S denied: climate / questionnaire answers of others (RLS)', (SELECT count(*) = 0 FROM questionnaire_submission));
SELECT t_expect_err('S denied: climate trends', $$SELECT * FROM rpc_board_macro_trends('quarter')$$, 'access_denied');
SELECT t_assert('S denied: team aggregates / shadow balance / manager feeds (RLS)',
  (SELECT count(*) = 0 FROM team_aggregate) AND (SELECT count(*) = 0 FROM shadow_balance_aggregate)
  AND (SELECT count(*) = 0 FROM cuckoo_alert_manager_v) AND (SELECT count(*) = 0 FROM early_leave_manager_v));
SELECT t_expect_err('S denied: named employee data', format($$SELECT * FROM rpc_chro_named_view(%L, 'x')$$, t_u('e1')), 'access_denied');
CREATE TEMP TABLE t_ev2 AS SELECT event_id FROM rpc_emergency_declare('war_or_security');
SELECT t_assert('S access during an active emergency (roster)', (SELECT count(*) >= 24 FROM rpc_emergency_roster((SELECT event_id FROM t_ev2))));
SELECT t_expect_err('S even during an emergency: no team wellbeing', format($$SELECT * FROM rpc_emergency_team_status(%L, 'X')$$, (SELECT event_id FROM t_ev2)), 'access_denied');
SELECT rpc_emergency_end((SELECT event_id FROM t_ev2)) IS NOT NULL AS ended;
SELECT t_expect_err('S access locks immediately when the emergency closes', format($$SELECT * FROM rpc_emergency_roster(%L)$$, (SELECT event_id FROM t_ev2)), 'emergency_not_active');
RESET ROLE;
SELECT t_as(t_u('e20'));
SET ROLE authenticated;
CREATE TEMP TABLE t_d4 AS SELECT * FROM rpc_distress_press('home');
RESET ROLE;
UPDATE distress_event SET pressed_at = pressed_at - interval '61 seconds', grace_expires_at = grace_expires_at - interval '61 seconds'
 WHERE event_id = (SELECT event_id FROM t_d4);
SELECT rpc_distress_dispatch_job() = 1 AS d4_dispatched;
SELECT t_as(t_u('safety'));
SET ROLE authenticated;
SELECT t_assert('S distress access while the event is open', (SELECT count(*) = 1 FROM rpc_distress_safety_inbox() WHERE event_id = (SELECT event_id FROM t_d4)));
SELECT (SELECT status FROM rpc_distress_close((SELECT event_id FROM t_d4), 'referred_to_external_help')) = 'CLOSED' AS d4_closed;
SELECT t_assert('S distress access locks on close', NOT EXISTS (SELECT 1 FROM rpc_distress_safety_inbox() WHERE event_id = (SELECT event_id FROM t_d4)));
RESET ROLE;

-- ============ v1.6.3 Q5. Emergency misuse: close → notify → talk; 2nd misuse → no opening alone ============
SELECT t_assert('Q5 MISUSE notified the declarer', (SELECT count(*) = 1 FROM notification WHERE recipient_id = t_u('safety') AND kind = 'emergency_misuse_notice'));
SELECT t_assert('Q5 one MISUSE so far → still may open alone', fn_emergency_misuse_count(t_u('safety')) = 1 AND fn_emergency_may_open_alone(t_u('safety')));
SELECT t_as(t_u('chro'));
SET ROLE authenticated;
SELECT t_expect_err('Q5 talk only after a MISUSE notice (JUSTIFIED event)',
  format($$SELECT rpc_emergency_misuse_talk(%L)$$, (SELECT event_id FROM rpc_emergency_hr_review((SELECT event_id FROM t_ev2), 'JUSTIFIED'))), 'emergency_misuse_sequence');
SELECT t_assert('Q5 talk step recorded after the notice',
  (SELECT misuse_talk_at IS NOT NULL FROM rpc_emergency_misuse_talk((SELECT event_id FROM t_ev))));
SELECT t_expect_err('Q5 talk recorded once', format($$SELECT rpc_emergency_misuse_talk(%L)$$, (SELECT event_id FROM t_ev)), 'emergency_misuse_sequence');
RESET ROLE;
SELECT t_as(t_u('safety'));
SET ROLE authenticated;
CREATE TEMP TABLE t_ev3 AS SELECT event_id, status FROM rpc_emergency_declare('health_or_life_danger');
RESET ROLE;
SELECT t_assert('Q5 with one MISUSE the declarer still opens alone (ACTIVE)', (SELECT status = 'ACTIVE' FROM t_ev3));
SELECT t_as(t_u('chro'));
SET ROLE authenticated;
SELECT t_expect_err('Q5 close step is not the CHRO''s (Q7: the CHRO never closes)', format($$SELECT rpc_emergency_end(%L)$$, (SELECT event_id FROM t_ev3)), 'access_denied');
RESET ROLE;
SELECT t_as(t_u('safety'));
SET ROLE authenticated;
SELECT t_assert('Q5 close step: the safety manager ends the misused emergency',
  (SELECT status = 'ENDED' AND ended_by = t_u('safety') FROM rpc_emergency_end((SELECT event_id FROM t_ev3))));
RESET ROLE;
SELECT t_as(t_u('chro'));
SET ROLE authenticated;
SELECT t_assert('Q5 notify step: CHRO review MISUSE → declarer notified',
  (SELECT hr_review_status = 'MISUSE' AND misuse_notified_at IS NOT NULL FROM rpc_emergency_hr_review((SELECT event_id FROM t_ev3), 'MISUSE')));
SELECT t_expect_err('Q5 a reviewed emergency cannot be re-marked', format($$SELECT rpc_emergency_hr_review(%L, 'MISUSE')$$, (SELECT event_id FROM t_ev3)), 'emergency_review_not_pending');
RESET ROLE;
SELECT t_assert('Q5 rule applies to the declarer: second notice to her', (SELECT count(*) = 2 FROM notification WHERE recipient_id = t_u('safety') AND kind = 'emergency_misuse_notice'));
SELECT t_assert('Q5 two MISUSE findings → loses the right to open alone', fn_emergency_misuse_count(t_u('safety')) = 2 AND NOT fn_emergency_may_open_alone(t_u('safety')));
SELECT t_as(t_u('safety'));
SET ROLE authenticated;
CREATE TEMP TABLE t_ev4 AS SELECT event_id, status FROM rpc_emergency_declare('work_stopping_disaster');
SELECT t_assert('Q5 after the 2nd misuse a declaration waits for a co-signer', (SELECT status = 'PENDING_COSIGN' FROM t_ev4));
SELECT t_expect_err('Q5 no roster before co-sign', format($$SELECT * FROM rpc_emergency_roster(%L)$$, (SELECT event_id FROM t_ev4)), 'emergency_not_active');
SELECT t_expect_err('Q5 declarer cannot co-sign herself', format($$SELECT rpc_emergency_cosign(%L)$$, (SELECT event_id FROM t_ev4)), 'access_denied');
SELECT t_expect_err('Q5 pending declaration blocks a second one (409)', $$SELECT rpc_emergency_declare('war_or_security')$$, 'emergency_already_active');
RESET ROLE;
SELECT t_assert('Q5 co-sign requested from the CHRO', (SELECT count(*) = 1 FROM notification WHERE recipient_id = t_u('chro') AND kind = 'emergency_cosign_request'));
SELECT t_as(t_u('e5'));
SET ROLE authenticated;
SELECT t_expect_err('Q5 employees cannot co-sign', format($$SELECT rpc_emergency_cosign(%L)$$, (SELECT event_id FROM t_ev4)), 'access_denied');
RESET ROLE;
SELECT t_as(t_u('chro'));
SET ROLE authenticated;
SELECT t_assert('Q5 CHRO co-signs → ACTIVE', (SELECT status = 'ACTIVE' AND cosigned_by = t_u('chro') FROM rpc_emergency_cosign((SELECT event_id FROM t_ev4))));
SELECT t_expect_err('Q5 co-sign only once', format($$SELECT rpc_emergency_cosign(%L)$$, (SELECT event_id FROM t_ev4)), 'emergency_not_pending_cosign');
RESET ROLE;
SELECT t_as(t_u('safety'));
SET ROLE authenticated;
SELECT t_assert('Q5 co-signed emergency opens the roster', (SELECT count(*) >= 24 FROM rpc_emergency_roster((SELECT event_id FROM t_ev4))));
SELECT rpc_emergency_end((SELECT event_id FROM t_ev4)) IS NOT NULL AS ev4_ended;
RESET ROLE;
SELECT t_assert('Q5 every misuse step audited immutably',
  (SELECT count(*) FILTER (WHERE action = 'emergency_misuse') = 2 AND count(*) FILTER (WHERE action = 'emergency_misuse_talk') = 1
          AND count(*) FILTER (WHERE action = 'emergency_cosign') = 1 FROM access_audit_log));
SELECT t_expect_err('Q5 notify-before-misuse blocked by CHECK',
  format($$UPDATE emergency_event SET misuse_notified_at = now() WHERE event_id = %L$$, (SELECT event_id FROM t_ev4)), '23514');

-- ============ v1.6.3 Q6. CHRO legal reason (locked 12.10) ============
SELECT t_expect_err('Q6 audit row for a named view without reason rejected (CHECK)',
  $$INSERT INTO access_audit_log (action, reason) VALUES ('chro_named_view', NULL)$$, '23514');
SELECT t_expect_err('Q6 blank reason rejected (CHECK)',
  $$INSERT INTO access_audit_log (action, reason) VALUES ('chro_named_view', '   ')$$, '23514');
SELECT t_as(t_u('chro'));
SET ROLE authenticated;
SELECT t_assert('Q6 any free-text labour-law reason accepted', (SELECT count(*) = 1 FROM rpc_chro_named_view(t_u('e2'), 'בירור תלונה לפי חוק למניעת הטרדה מינית')));
RESET ROLE;
SELECT t_assert('Q6 that view is audited with its reason',
  (SELECT count(*) = 1 FROM access_audit_log WHERE action = 'chro_named_view' AND subject_user_id = t_u('e2') AND reason LIKE 'בירור תלונה%'));

-- ============ v1.6.4 BT. B_t = 0.41·S + 0.37·O + 0.22·D (Karin 20.10) ============
SELECT t_assert('BT Likert maps (x−1)/4: 1→0, 2→0.25, 3→0.5, 4→0.75, 5→1',
  fn_likert_unit(1) = 0 AND fn_likert_unit(2) = 0.25 AND fn_likert_unit(3) = 0.5 AND fn_likert_unit(4) = 0.75 AND fn_likert_unit(5) = 1);
SELECT t_assert('BT overtime 5 h → O = 0.5', fn_overtime_unit(5) = 0.5);
SELECT t_assert('BT overtime 10 h and 15 h → O = 1 (10-hour cap)', fn_overtime_unit(10) = 1 AND fn_overtime_unit(15) = 1);
SELECT t_assert('BT O clamped at 0 (pure helper)', fn_overtime_unit(-3) = 0);
SELECT t_assert('BT all-minimum inputs (stress 1, 0 h, drop 1) → 0 → low', fn_b_t(1, 0, 1) = 0 AND fn_b_t_band(fn_b_t(1, 0, 1)) = 'low');
SELECT t_assert('BT all-maximum inputs (stress 5, 10 h, drop 5) → 1.0 → high', fn_b_t(5, 10, 5) = 1 AND fn_b_t_band(fn_b_t(5, 10, 5)) = 'high');
SELECT t_assert('BT overtime above the cap scores the same (15 h = 10 h)', fn_b_t(5, 15, 5) = 1);
SELECT t_assert('BT edge from real inputs: stress 1, 5 h, drop 4 → 0.35 exactly → medium',
  fn_b_t(1, 5, 4) = 0.35 AND fn_b_t_band(fn_b_t(1, 5, 4)) = 'medium');
SELECT t_assert('BT edge from real inputs: stress 2, 5.2 h, drop 2 → 0.3499 → low',
  fn_b_t(2, 5.2, 2) = 0.3499 AND fn_b_t_band(fn_b_t(2, 5.2, 2)) = 'low');
SELECT t_assert('BT edge from real inputs: stress 5, 5 h, drop 2 → 0.65 exactly → high',
  fn_b_t(5, 5, 2) = 0.65 AND fn_b_t_band(fn_b_t(5, 5, 2)) = 'high');
SELECT t_assert('BT edge 0.6499 → medium (band function; no 1–5 / 2-decimal-hours combo yields it)',
  fn_b_t_band(0.6499) = 'medium');
SELECT t_assert('BT missing stress → NULL (no partial score)', fn_b_t(NULL, 5, 3) IS NULL AND fn_b_t_band(fn_b_t(NULL, 5, 3)) IS NULL);
SELECT t_assert('BT missing overtime → NULL', fn_b_t(3, NULL, 3) IS NULL);
SELECT t_assert('BT missing productivity drop → NULL', fn_b_t(3, 5, NULL) IS NULL);
SELECT t_expect_err('BT stress 0 rejected', $$SELECT fn_b_t(0, 5, 3)$$, 'workload_invalid_answers');
SELECT t_expect_err('BT stress 6 rejected', $$SELECT fn_b_t(6, 5, 3)$$, 'workload_invalid_answers');
SELECT t_expect_err('BT non-integer Likert 2.5 rejected', $$SELECT fn_b_t(3, 5, 2.5)$$, 'workload_invalid_answers');
SELECT t_expect_err('BT negative overtime rejected', $$SELECT fn_b_t(3, -1, 3)$$, 'workload_invalid_answers');
SELECT t_expect_err('BT table CHECK rejects stress 6', format($$INSERT INTO workload_self_report (user_id, company_id, work_date,
  contract_hours, hours_worked, overtime_hours, parallel_projects, stress_1to5) VALUES (%L, %L, %L, 40, 40, 0, 1, 6)$$,
  t_u('e17'), '00000000-0000-0000-0000-0000000000c2', fn_local_week_start(t_u('e17'))), '23514');
SELECT t_assert('BT L(P) P=6 and P=9 → 0.75 (P>5 counts as 5)', fn_context_switch_loss(6) = 0.75 AND fn_context_switch_loss(9) = 0.75);
SELECT t_assert('BT sigmoid removed', NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_sigmoid'));

-- ---- weekly self-report: separate from spoons; one per week (reject duplicate); B_t from that week ----
SELECT t_rep2(ARRAY['e16'], 7);
CREATE TEMP TABLE t_spoon_before AS
  SELECT budget_date, current_spoon_count, reported_at FROM spoon_budget WHERE user_id = t_u('e16');
GRANT SELECT ON t_spoon_before TO authenticated;
SELECT t_as(t_u('e16'));
SET ROLE authenticated;
SELECT t_expect_err('BT submit rejects stress 6 → 400', $$SELECT * FROM rpc_submit_workload_self_report(40, 45, 5, 2, 6, 4)$$, 'workload_invalid_answers');
SELECT t_expect_err('BT submit rejects drop 0 → 400', $$SELECT * FROM rpc_submit_workload_self_report(40, 45, 5, 2, 1, 0)$$, 'workload_invalid_answers');
SELECT t_expect_err('BT submit rejects non-integer stress 3.5 → 400', $$SELECT * FROM rpc_submit_workload_self_report(40, 45, 5, 2, 3.5, 4)$$, 'workload_invalid_answers');
SELECT t_expect_err('BT submit rejects negative overtime → 400', $$SELECT * FROM rpc_submit_workload_self_report(40, 45, -1, 2, 1, 4)$$, 'workload_invalid_answers');
SELECT t_assert('BT weekly report with stress 1, overtime 5 h, drop 4 accepted (any weekday — reminder is not a rule)',
  (SELECT report_id IS NOT NULL FROM rpc_submit_workload_self_report(40, 45, 5, 2, 1, 4)));
SELECT t_expect_err('BT second report in the same week rejected (409, no update in place)',
  $$SELECT * FROM rpc_submit_workload_self_report(40, 50, 10, 2, 5, 5)$$, 'workload_report_already_submitted');
SELECT t_assert('BT employee sees her own B_t: 0.35 → medium',
  (SELECT b_t = 0.35 AND b_t_band = 'medium' FROM rpc_my_workload_indices()));
SELECT t_assert('BT the stored week report is unchanged by the rejected duplicate',
  (SELECT count(*) = 1 AND bool_and(stress_1to5 = 1 AND productivity_drop_1to5 = 4 AND overtime_hours = 5) FROM workload_self_report));
SELECT t_assert('BT daily spoons unaffected by the weekly report',
  (SELECT count(*) = (SELECT count(*) FROM t_spoon_before) FROM spoon_budget)
  AND NOT EXISTS (SELECT 1 FROM spoon_budget s JOIN t_spoon_before b USING (budget_date)
                   WHERE s.current_spoon_count IS DISTINCT FROM b.current_spoon_count OR s.reported_at IS DISTINCT FROM b.reported_at));
RESET ROLE;
SELECT t_assert('BT spoon table holds no weekly-report fields (not merged)',
  NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'spoon_budget'
               AND column_name IN ('stress_1to5', 'productivity_drop_1to5', 'overtime_hours', 'parallel_projects', 'week_start_date')));
SELECT t_wr('e16', 40, 50, 10, 2, fn_local_week_start(t_u('e16')) - 7, 5::smallint, 5::smallint);   -- previous week
SELECT t_assert('BT a report in a different week is allowed',
  (SELECT count(*) = 2 FROM workload_self_report WHERE user_id = t_u('e16')));
CREATE TEMP TABLE t_prev_week AS SELECT fn_local_week_start(t_u('e16')) - 7 AS wk;
GRANT SELECT ON t_prev_week TO authenticated;
SELECT t_as(t_u('e16'));
SET ROLE authenticated;
SELECT t_assert('BT B_t uses THAT week''s report: previous week 1.00 → high',
  (SELECT b_t = 1 AND b_t_band = 'high' FROM rpc_my_workload_indices((SELECT wk FROM t_prev_week))));
SELECT t_assert('BT …and this week still 0.35 → medium', (SELECT b_t = 0.35 FROM rpc_my_workload_indices()));
RESET ROLE;
SELECT t_assert('BT reminder is a company setting (last workday + reminder_time), not a submission rule',
  (SELECT reminder_time = '14:00' AND last_workday_dow = 5 FROM companies WHERE company_id = '00000000-0000-0000-0000-0000000000c2'));
SELECT t_assert('BT v1.6.4 global reminder table replaced', to_regclass('workload_reminder_setting') IS NULL);
SELECT t_expect_err('BT last workday must be 0–6', $$UPDATE companies SET last_workday_dow = 7$$, '23514');

-- ---- B_t is employee-only: PM, direct manager, line manager, CHRO, safety manager get nothing ----
CREATE OR REPLACE FUNCTION t_bt_denied(p_code text) RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE v_rows int; v_reports int;
BEGIN
  PERFORM t_as(t_u(p_code));
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_rows FROM rpc_my_workload_indices() WHERE b_t IS NOT NULL;
  SELECT count(*) INTO v_reports FROM workload_self_report;
  RESET ROLE;
  RETURN v_rows = 0 AND v_reports = 0;
END $$;
SELECT t_assert('BT PM gets no individual B_t', t_bt_denied('pm'));
SELECT t_assert('BT direct manager gets no individual B_t', t_bt_denied('dm1'));
SELECT t_assert('BT e16''s line manager gets no individual B_t', t_bt_denied('dept1'));
SELECT t_assert('BT CHRO gets no individual B_t', t_bt_denied('chro'));
SELECT t_assert('BT safety manager gets no individual B_t', t_bt_denied('safety'));
SELECT t_assert('BT indices RPC has no user parameter (self only)',
  (SELECT pronargs = 1 AND proargtypes[0] = 'date'::regtype FROM pg_proc WHERE proname = 'rpc_my_workload_indices'));
SELECT t_assert('BT no B_t in the PM project aggregate',
  NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_project_workload' AND array_to_string(proargnames, ',') LIKE '%b_t%'));

-- ============ v1.6.4 Q4. Core is a project toggle set by the PM ============
SELECT t_as(t_u('pm'));
SET ROLE authenticated;
SELECT t_expect_err('Q4 create without is_core rejected (400)', $$SELECT * FROM rpc_project_create('NX', NULL)$$, 'project_is_core_required');
CREATE TEMP TABLE t_nc2 AS SELECT project_id, is_core FROM rpc_project_create('NC2', false);
CREATE TEMP TABLE t_nc3 AS SELECT project_id, is_core FROM rpc_project_create('NC3', false);
SELECT t_assert('Q4 PM creates a project with an explicit choice', (SELECT NOT is_core FROM t_nc2));
SELECT * FROM rpc_project_assign_member((SELECT project_id FROM t_nc2), t_u('e2'));
SELECT t_assert('Q4 2 core + 3 non-core projects → count 2, no alert',
  (SELECT core_assignment_count = 2 FROM rpc_project_assign_member((SELECT project_id FROM t_nc3), t_u('e2'))));
RESET ROLE;
SELECT t_assert('Q4 …e2 is in 5 projects and has no WIP alert',
  (SELECT count(*) = 5 FROM project_member WHERE user_id = t_u('e2')) AND NOT EXISTS (SELECT 1 FROM wip_alert WHERE recipient_id = t_u('e2')));
SELECT t_expect_err('Q4 direct insert without is_core rejected (NOT NULL, no default)',
  $$INSERT INTO project (company_id, name) VALUES ('00000000-0000-0000-0000-0000000000c2', 'NoChoice')$$, '23502');
SELECT t_assert('Q4 is_core has no default', (SELECT column_default IS NULL AND is_nullable = 'NO' FROM information_schema.columns
  WHERE table_name = 'project' AND column_name = 'is_core'));
SELECT t_assert('Q4 member-level core flag removed', NOT EXISTS (SELECT 1 FROM information_schema.columns
  WHERE table_name = 'project_member' AND column_name = 'is_core'));
SELECT t_as(t_u('e1'));
SET ROLE authenticated;
SELECT t_expect_err('Q4 employee cannot toggle core', format($$SELECT * FROM rpc_project_set_core(%L, true)$$, (SELECT project_id FROM t_nc2)), 'access_denied');
SELECT t_expect_err('Q4 employee cannot create a project', $$SELECT * FROM rpc_project_create('E', true)$$, 'access_denied');
RESET ROLE;
SELECT t_as(t_u('dm1'));
SET ROLE authenticated;
SELECT t_expect_err('Q4 non-PM owner of a project cannot toggle it (PM role required)',
  $$SELECT * FROM rpc_project_set_core('00000000-0000-0000-0000-0000000000a3', false)$$, 'access_denied');
RESET ROLE;
SELECT t_as(t_u('chro'));
SET ROLE authenticated;
SELECT t_expect_err('Q4 CHRO cannot toggle core', format($$SELECT * FROM rpc_project_set_core(%L, true)$$, (SELECT project_id FROM t_nc2)), 'access_denied');
RESET ROLE;
SELECT t_as(t_u('pm'));
SET ROLE authenticated;
SELECT t_expect_err('Q4 PM cannot toggle another PM''s project',
  $$SELECT * FROM rpc_project_set_core('00000000-0000-0000-0000-0000000000a3', false)$$, 'access_denied');
SELECT t_expect_err('Q4 toggle needs an explicit value', format($$SELECT * FROM rpc_project_set_core(%L, NULL)$$, (SELECT project_id FROM t_nc2)), 'project_is_core_required');
SELECT t_assert('Q4 PM toggles her project to core', (SELECT is_core FROM rpc_project_set_core((SELECT project_id FROM t_nc2), true)));
SELECT t_assert('Q4 3 core projects → PM alert with the count only',
  (SELECT count(*) = 1 AND bool_and(core_assignment_count = 3 AND audience = 'project_manager' AND recipient_id = t_u('pm'))
     FROM wip_alert WHERE project_id = (SELECT project_id FROM t_nc2)));
RESET ROLE;
SELECT t_assert('Q4 …and e2 gets her own alert (count 3); nothing blocked',
  (SELECT count(*) = 1 AND bool_and(core_assignment_count = 3) FROM wip_alert WHERE recipient_id = t_u('e2') AND audience = 'employee')
  AND (SELECT count(*) = 5 FROM project_member WHERE user_id = t_u('e2')));

-- ============ v1.6.4 Q7. Co-signer = the CHRO only; the CHRO never closes ============
SELECT t_mk('safety2', 'safety_emergency_manager', 'employee', NULL) IS NOT NULL;
SELECT t_as(t_u('safety'));
SET ROLE authenticated;
CREATE TEMP TABLE t_ev5 AS SELECT event_id, status FROM rpc_emergency_declare('health_or_life_danger');
SELECT t_assert('Q7 restricted declarer cannot open alone (PENDING_COSIGN)', (SELECT status = 'PENDING_COSIGN' FROM t_ev5));
RESET ROLE;
SELECT t_assert('Q7 co-sign request goes to the CHRO only, not to other safety managers',
  (SELECT count(*) = 0 FROM notification WHERE recipient_id = t_u('safety2') AND kind = 'emergency_cosign_request'));
SELECT t_as(t_u('safety2'));
SET ROLE authenticated;
SELECT t_expect_err('Q7 another safety manager''s co-sign rejected', format($$SELECT rpc_emergency_cosign(%L)$$, (SELECT event_id FROM t_ev5)), 'access_denied');
RESET ROLE;
SELECT t_as(t_u('chro'));
SET ROLE authenticated;
SELECT t_assert('Q7 opens with the CHRO''s co-approval', (SELECT status = 'ACTIVE' AND cosigned_by = t_u('chro') FROM rpc_emergency_cosign((SELECT event_id FROM t_ev5))));
SELECT t_expect_err('Q7 the CHRO cannot close', format($$SELECT rpc_emergency_end(%L)$$, (SELECT event_id FROM t_ev5)), 'access_denied');
RESET ROLE;
SELECT t_assert('Q7 the CHRO force-close RPC no longer exists', NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_emergency_misuse_close'));
SELECT t_as(t_u('safety'));
SET ROLE authenticated;
SELECT t_assert('Q7 closing stays with the safety manager alone', (SELECT status = 'ENDED' AND ended_by = t_u('safety') FROM rpc_emergency_end((SELECT event_id FROM t_ev5))));
RESET ROLE;

-- ============ v1.6.4 Q8. Role → tier (Karin's 5 tiers; label only) ============
SELECT t_assert('Q8 tier 1: employee, direct_manager',
  (SELECT bool_and(tier = 1) AND count(*) = 2 FROM org_role WHERE role_code IN ('employee', 'direct_manager')));
SELECT t_assert('Q8 tier 2 (swapped v1.6.5): functional_manager, project_manager',
  (SELECT bool_and(tier = 2) AND count(*) = 2 FROM org_role WHERE role_code IN ('functional_manager', 'project_manager')));
SELECT t_assert('Q8 tier 3 (swapped v1.6.5): department_manager, division_manager, director',
  (SELECT bool_and(tier = 3) AND count(*) = 3 FROM org_role WHERE role_code IN ('department_manager', 'division_manager', 'director')));
SELECT t_assert('Q8 tier 4: vp, evp, ceo',
  (SELECT bool_and(tier = 4) AND count(*) = 3 FROM org_role WHERE role_code IN ('vp', 'evp', 'ceo')));
SELECT t_assert('Q8 tier 5: board_chair, board_member, owner_shareholder',
  (SELECT bool_and(tier = 5) AND count(*) = 3 FROM org_role WHERE role_code IN ('board_chair', 'board_member', 'owner_shareholder')));
SELECT t_assert('Q8 safety_emergency_manager stays outside the tiers; 13 tiered roles in total',
  (SELECT tier IS NULL FROM org_role WHERE role_code = 'safety_emergency_manager')
  AND (SELECT count(*) = 13 FROM org_role WHERE tier IS NOT NULL));
SELECT t_assert('Q8 tier is never read for access: only the O-2 turnover-tier helpers read org_role.tier',
  NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
               WHERE n.nspname = 'public' AND p.proname ~ '^(fn|rpc)_'
                 AND p.proname NOT IN ('fn_user_default_turnover_tier', 'fn_effective_turnover_tier')
                 AND p.prosrc ~* 'org_role'
                 AND regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~* '\mtier\M'));   -- comments ignored

-- ============ v1.6.5 K. Company calendar: country default, week key = week_start_date ============
INSERT INTO companies (company_id, company_name, country, last_workday_dow, timezone)
VALUES ('00000000-0000-0000-0000-0000000000c3', 'SunCo', 'IL', 4, 'Asia/Jerusalem'),
       ('00000000-0000-0000-0000-0000000000c4', 'MonCo', 'DE', 5, 'Europe/Berlin'),
       ('00000000-0000-0000-0000-0000000000c5', 'OtherCo', 'fr', 5, 'Europe/Paris');
INSERT INTO companies (company_id, company_name, country, week_start_dow, last_workday_dow, timezone)
VALUES ('00000000-0000-0000-0000-0000000000c6', 'OverCo', 'IL', 1, 5, 'Asia/Jerusalem');
SELECT t_assert('K IL company gets Sunday (0) automatically',
  (SELECT week_start_dow = 0 FROM companies WHERE company_id = '00000000-0000-0000-0000-0000000000c3'));
SELECT t_assert('K DE company gets Monday (1) automatically',
  (SELECT week_start_dow = 1 FROM companies WHERE company_id = '00000000-0000-0000-0000-0000000000c4'));
SELECT t_assert('K FR company gets Monday (CLDR firstDay mon); country stored upper-case',
  (SELECT week_start_dow = 1 AND country = 'FR' FROM companies WHERE company_id = '00000000-0000-0000-0000-0000000000c5'));
SELECT t_assert('K a company can override the country default on create',
  (SELECT week_start_dow = 1 FROM companies WHERE company_id = '00000000-0000-0000-0000-0000000000c6'));
SELECT t_expect_err('K country is required', $$INSERT INTO companies (company_name, last_workday_dow, timezone) VALUES ('NoCountry', 4, 'Asia/Jerusalem')$$, '23502');
SELECT t_expect_err('K country must be ISO alpha-2', $$INSERT INTO companies (company_name, country, last_workday_dow, timezone) VALUES ('Bad', 'ISR', 4, 'Asia/Jerusalem')$$, '23514');
SELECT t_expect_err('K last workday is required (no default)', $$INSERT INTO companies (company_name, country, timezone) VALUES ('NoLast', 'IL', 'Asia/Jerusalem')$$, '23502');
SELECT t_expect_err('K timezone is required (no default)', $$INSERT INTO companies (company_name, country, last_workday_dow) VALUES ('NoTz', 'IL', 4)$$, 'timezone_required');
SELECT t_expect_err('K timezone must be valid IANA', $$INSERT INTO companies (company_name, country, last_workday_dow, timezone) VALUES ('BadTz', 'IL', 4, 'Mars/Base')$$, 'invalid_timezone');
SELECT t_assert('K reminder_time defaults to 14:00 (locked)',
  (SELECT bool_and(reminder_time = '14:00') FROM companies WHERE company_id IN ('00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000c4')));
-- week key
SELECT t_assert('K Sunday-start: a Sunday 2026-10-25 report gets week_start_date 2026-10-25',
  fn_week_start_for(DATE '2026-10-25', 0::smallint) = DATE '2026-10-25');
SELECT t_assert('K Monday-start: Sunday 2026-10-25 counts in the previous week (2026-10-19)',
  fn_week_start_for(DATE '2026-10-25', 1::smallint) = DATE '2026-10-19');
SELECT t_assert('K a week is always 7 days (v1.6.8: no long transition week — a bridge instead): week_start_date + 6 is the last day',
  fn_week_last_day(DATE '2026-10-25') = DATE '2026-10-31'
  AND fn_company_week_end('00000000-0000-0000-0000-0000000000c3', DATE '2026-10-25') = DATE '2026-10-31'
  AND fn_week_start_for(DATE '2026-10-31', 0::smallint) = DATE '2026-10-25'
  AND fn_week_start_for(DATE '2026-11-01', 0::smallint) = DATE '2026-11-01');
SELECT t_assert('K Friday–Saturday workers still have a 7-day week (start Saturday)',
  fn_week_start_for(DATE '2026-10-30', 6::smallint) = DATE '2026-10-24' AND fn_week_last_day(DATE '2026-10-24') = DATE '2026-10-30');
SELECT t_assert('K no ISO week usage left in workload functions',
  NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
               WHERE n.nspname = 'public' AND p.proname ~ '(week|workload)' AND p.prosrc ~* '(isodow|isoyear|date_trunc\(.week)'));
-- employees in the Sunday-start and Monday-start companies
DO $$
DECLARE v uuid;
BEGIN
  v := gen_random_uuid(); INSERT INTO auth.users (id) VALUES (v);
  INSERT INTO users (user_id, company_id, email, full_name, department, app_role, org_role_code, timezone, hire_date, has_employee_profile, phone)
  VALUES (v, '00000000-0000-0000-0000-0000000000c3', 'sun1@c3', 'Sun One', 'X', 'employee', 'employee', 'Asia/Jerusalem', CURRENT_DATE - 200, true, '050-0000301');
  v := gen_random_uuid(); INSERT INTO auth.users (id) VALUES (v);
  INSERT INTO users (user_id, company_id, email, full_name, department, app_role, org_role_code, timezone, hire_date, has_employee_profile, phone)
  VALUES (v, '00000000-0000-0000-0000-0000000000c4', 'mon1@c4', 'Mon One', 'X', 'employee', 'employee', 'Europe/Berlin', CURRENT_DATE - 200, true, '050-0000401');
  v := gen_random_uuid(); INSERT INTO auth.users (id) VALUES (v);
  INSERT INTO users (user_id, company_id, email, full_name, department, app_role, org_role_code, timezone, hire_date, has_employee_profile, phone)
  VALUES (v, '00000000-0000-0000-0000-0000000000c3', 'chro@c3', 'Sun CHRO', 'X', 'vp_hr', 'vp', 'Asia/Jerusalem', CURRENT_DATE - 200, true, '050-0000302');
  -- v1.6.6: RPC-path users (work dates relative to their local today, O-40 range)
  v := gen_random_uuid(); INSERT INTO auth.users (id) VALUES (v);
  INSERT INTO users (user_id, company_id, email, full_name, department, app_role, org_role_code, timezone, hire_date, has_employee_profile, phone)
  VALUES (v, '00000000-0000-0000-0000-0000000000c3', 'sun2@c3', 'Sun Two', 'X', 'employee', 'employee', 'Asia/Jerusalem', CURRENT_DATE - 200, true, '050-0000303');
  v := gen_random_uuid(); INSERT INTO auth.users (id) VALUES (v);
  INSERT INTO users (user_id, company_id, email, full_name, department, app_role, org_role_code, timezone, hire_date, has_employee_profile, phone)
  VALUES (v, '00000000-0000-0000-0000-0000000000c4', 'mon2@c4', 'Mon Two', 'X', 'employee', 'employee', 'Europe/Berlin', CURRENT_DATE - 200, true, '050-0000402');
  v := gen_random_uuid(); INSERT INTO auth.users (id) VALUES (v);
  INSERT INTO users (user_id, company_id, email, full_name, department, app_role, org_role_code, timezone, hire_date, has_employee_profile, phone)
  VALUES (v, '00000000-0000-0000-0000-0000000000c3', 'rng1@c3', 'Range One', 'X', 'employee', 'employee', 'Asia/Jerusalem', CURRENT_DATE - 200, true, '050-0000304');
  v := gen_random_uuid(); INSERT INTO auth.users (id) VALUES (v);
  INSERT INTO users (user_id, company_id, email, full_name, department, app_role, org_role_code, timezone, hire_date, has_employee_profile, phone)
  VALUES (v, '00000000-0000-0000-0000-0000000000c3', 'rng2@c3', 'Range Two', 'X', 'employee', 'employee', 'Asia/Jerusalem', CURRENT_DATE - 200, true, '050-0000305');
END $$;
CREATE OR REPLACE FUNCTION t_x(p_email text) RETURNS uuid LANGUAGE sql SECURITY DEFINER AS $$ SELECT user_id FROM users WHERE email = p_email $$;
GRANT EXECUTE ON FUNCTION t_x(text) TO authenticated;
SELECT t_assert('K employee week key follows her company (Sunday-start, Sunday report → same day)',
  fn_local_week_start(t_x('sun1@c3'), TIMESTAMPTZ '2026-10-25 10:00 Asia/Jerusalem') = DATE '2026-10-25');
SELECT t_assert('K employee week key follows her company (Monday-start, Sunday report → previous Monday)',
  fn_local_week_start(t_x('mon1@c4'), TIMESTAMPTZ '2026-10-25 10:00 Europe/Berlin') = DATE '2026-10-19');
-- v1.6.6: Karin's fixed example dates lie outside the O-40 submit range (today − 14 … today + 1), so
-- they are checked on the stored-row path (same trigger the RPC uses); the RPC path below uses
-- dates relative to the employee's local today.
CREATE OR REPLACE FUNCTION t_wk(p_email text, p_work date) RETURNS date LANGUAGE sql AS $$
  INSERT INTO workload_self_report (user_id, company_id, work_date, contract_hours, hours_worked, overtime_hours, parallel_projects)
  SELECT u.user_id, u.company_id, p_work, 40, 40, 0, 1 FROM users u WHERE u.email = p_email
  RETURNING week_start_date $$;
SELECT t_assert('K Sunday-start: report with work date 2026-10-25 → week_start_date 2026-10-25',
  t_wk('sun1@c3', DATE '2026-10-25') = DATE '2026-10-25');
SELECT t_assert('K night shift Sat 2026-10-24 22:00–06:00 counts toward its start day → week 2026-10-18',
  t_wk('sun1@c3', DATE '2026-10-24') = DATE '2026-10-18');
SELECT t_expect_err('K duplicate in the same company week rejected on the stored-row path (Mon 2026-10-26)',
  $$SELECT t_wk('sun1@c3', DATE '2026-10-26')$$, '23505');
SELECT t_assert('K stored rows: work date kept, keyed by week_start_date',
  (SELECT string_agg(work_date || '>' || week_start_date, ',' ORDER BY work_date) FROM workload_self_report WHERE user_id = t_x('sun1@c3'))
  = '2026-10-24>2026-10-18,2026-10-25>2026-10-25');
SELECT t_assert('K Monday-start: work date Sun 2026-10-25 → week 2026-10-19', t_wk('mon1@c4', DATE '2026-10-25') = DATE '2026-10-19');
SELECT t_expect_err('K Monday-start duplicate: Sat 2026-10-24 is the same Monday week', $$SELECT t_wk('mon1@c4', DATE '2026-10-24')$$, '23505');
SELECT t_assert('K Monday-start: Mon 2026-10-26 opens a new week', t_wk('mon1@c4', DATE '2026-10-26') = DATE '2026-10-26');
-- RPC path: each employee's local today, precomputed (authenticated cannot call fn_user_local_day)
CREATE TEMP TABLE t_today AS SELECT email, fn_user_local_day(user_id) AS d FROM users WHERE email IN ('sun2@c3', 'mon2@c4', 'rng1@c3', 'rng2@c3');
GRANT SELECT ON t_today TO authenticated;
CREATE TEMP TABLE t_k_dates AS
  SELECT fn_week_start_for((SELECT d FROM t_today WHERE email = 'sun2@c3') - 7, 0::smallint) AS sun_wk,
         fn_week_start_for((SELECT d FROM t_today WHERE email = 'mon2@c4') - 7, 1::smallint) AS mon_wk;
GRANT SELECT ON t_k_dates TO authenticated;
SELECT t_as(t_x('sun2@c3'));
SET ROLE authenticated;
SELECT t_assert('K RPC Sunday-start: a Sunday work date keys its own week',
  (SELECT r.week_start_date = k.sun_wk FROM t_k_dates k, rpc_submit_workload_self_report(40, 42, 2, 1, 2, 2, (SELECT sun_wk FROM t_k_dates)) r));
SELECT t_expect_err('K 409 respects the company week (the following Monday is in the same Sunday week)',
  format($$SELECT * FROM rpc_submit_workload_self_report(40, 40, 0, 1, 1, 1, %L)$$, (SELECT sun_wk + 1 FROM t_k_dates)), 'workload_report_already_submitted');
RESET ROLE;
SELECT t_as(t_x('mon2@c4'));
SET ROLE authenticated;
SELECT t_assert('K RPC Monday-start: a Monday work date keys its own week',
  (SELECT r.week_start_date = k.mon_wk FROM t_k_dates k, rpc_submit_workload_self_report(40, 40, 0, 1, 1, 1, (SELECT mon_wk FROM t_k_dates)) r));
SELECT t_expect_err('K 409 Monday-start: the following Sunday counts in the same (previous-Monday) week',
  format($$SELECT * FROM rpc_submit_workload_self_report(40, 40, 0, 1, 1, 1, %L)$$, (SELECT mon_wk + 6 FROM t_k_dates)), 'workload_report_already_submitted');
SELECT t_assert('K RPC Monday-start: the next Monday opens a new week',
  (SELECT r.week_start_date = k.mon_wk + 7 FROM t_k_dates k, rpc_submit_workload_self_report(40, 40, 0, 1, 1, 1, (SELECT mon_wk + 7 FROM t_k_dates)) r));
RESET ROLE;
SELECT t_expect_err('K a stored week key must match the company week start',
  format($$INSERT INTO workload_self_report (user_id, company_id, week_start_date, work_date, contract_hours, hours_worked, overtime_hours, parallel_projects)
           VALUES (%L, %L, '2026-10-19', '2026-10-20', 40, 40, 0, 1)$$, t_x('sun1@c3'), '00000000-0000-0000-0000-0000000000c3'), 'workload_week_invalid');
SELECT t_assert('K unique key is (employee, week_start_date)',
  (SELECT pg_get_constraintdef(oid) = 'UNIQUE (user_id, week_start_date)' FROM pg_constraint WHERE conname = 'uq_workload_report_week'));

-- ============ v1.6.5 R. Reminder: last workday at reminder_time (default 14:00, company-local) ============
SELECT t_assert('R default reminder: last workday (Thu) 14:00 Asia/Jerusalem for the week of 2026-10-18',
  fn_company_reminder_at('00000000-0000-0000-0000-0000000000c3', DATE '2026-10-18') = TIMESTAMPTZ '2026-10-22 14:00 Asia/Jerusalem');
SELECT t_assert('R 14:00 is company-local (Berlin, Fri of the week of 2026-10-19)',
  fn_company_reminder_at('00000000-0000-0000-0000-0000000000c4', DATE '2026-10-19') = TIMESTAMPTZ '2026-10-23 14:00 Europe/Berlin');
SELECT t_as(t_x('chro@c3'));
SET ROLE authenticated;
SELECT t_assert('R the CHRO can change her company''s reminder time',
  (SELECT reminder_time = '16:30' FROM rpc_company_settings_update(p_reminder_time => '16:30')));
SELECT t_assert('R the CHRO can override the week start', (SELECT week_start_dow = 1 AND reminder_time = '16:30'
  FROM rpc_company_settings_update(p_week_start_dow => 1)));
SELECT * FROM rpc_company_settings_update(p_week_start_dow => 0);
SELECT t_expect_err('R invalid day-of-week rejected (400)', $$SELECT * FROM rpc_company_settings_update(p_last_workday_dow => 7)$$, 'invalid_company_setting');
SELECT t_expect_err('R invalid timezone rejected (400)', $$SELECT * FROM rpc_company_settings_update(p_timezone => 'Mars/Base')$$, 'invalid_timezone');
RESET ROLE;
SELECT t_assert('R changed time used for the reminder; other company untouched',
  fn_company_reminder_at('00000000-0000-0000-0000-0000000000c3', DATE '2026-10-18') = TIMESTAMPTZ '2026-10-22 16:30 Asia/Jerusalem'
  AND (SELECT reminder_time = '14:00' FROM companies WHERE company_id = '00000000-0000-0000-0000-0000000000c4'));
SELECT t_as(t_x('sun1@c3'));
SET ROLE authenticated;
SELECT t_expect_err('R an employee cannot change settings', $$SELECT * FROM rpc_company_settings_update(p_reminder_time => '09:00')$$, 'access_denied');
SELECT t_assert('R an employee can read her company settings', (SELECT week_start_dow = 0 AND reminder_time = '16:30' FROM rpc_company_settings()));
RESET ROLE;
CREATE OR REPLACE FUNCTION t_settings_denied(p_code text) RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN
  PERFORM t_as(t_u(p_code));
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM * FROM rpc_company_settings_update(p_reminder_time => '09:00');
  EXCEPTION WHEN insufficient_privilege THEN
    RESET ROLE; RETURN true;
  END;
  RESET ROLE; RETURN false;
END $$;
SELECT t_assert('R CEO cannot change settings', t_settings_denied('ceo'));
SELECT t_assert('R PM cannot change settings', t_settings_denied('pm'));
SELECT t_assert('R safety manager cannot change settings', t_settings_denied('safety'));
SELECT t_assert('R direct manager cannot change settings', t_settings_denied('dm1'));
SELECT t_assert('R c2 reminder unchanged by the denied calls', (SELECT reminder_time = '14:00' FROM companies WHERE company_id = '00000000-0000-0000-0000-0000000000c2'));
SELECT t_assert('R sender job is a stub (service_role only)', rpc_workload_reminder_job() = 'reminder_sender_not_configured'
  AND NOT has_function_privilege('authenticated', 'rpc_workload_reminder_job()', 'EXECUTE'));
SELECT t_assert('R settings changes are audited', (SELECT count(*) >= 2 FROM access_audit_log WHERE action = 'company_settings_update'));

-- ============ v1.6.7/1.6.8 T. Week-start change: 7-day last old week + 1–6-day bridge (Karin 21.10, O-41) ============
CREATE OR REPLACE FUNCTION t_mkuser(p_email text, p_company uuid, p_app text, p_org text, p_tz text) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id) VALUES (v);
  INSERT INTO users (user_id, company_id, email, full_name, department, app_role, org_role_code, timezone, hire_date, has_employee_profile)
  VALUES (v, p_company, p_email, p_email, 'X', p_app, p_org, p_tz, CURRENT_DATE - 200, true);
  RETURN v;
END $$;
-- One segment per day: its week (start, end = start + 6) or its bridge (start, end) — never both.
CREATE OR REPLACE FUNCTION t_day_segment(p_company uuid, p_day date, OUT seg_start date, OUT seg_end date, OUT is_bridge boolean)
LANGUAGE sql AS $$
  SELECT COALESCE(w.ws, b.bridge_start), COALESCE(fn_company_week_end(p_company, w.ws), b.bridge_end), b.bridge_start IS NOT NULL
    FROM (SELECT fn_company_week_start(p_company, p_day) AS ws) w
    LEFT JOIN fn_company_bridge_at(p_company, p_day) b ON true
   WHERE (w.ws IS NULL) = (b.bridge_start IS NOT NULL)
$$;
-- No overlap and no gap between two dates: every day lies in exactly one week or one bridge, and
-- consecutive segments (old week → bridge → new week) touch.
CREATE OR REPLACE FUNCTION t_weeks_contiguous(p_company uuid, p_from date, p_to date) RETURNS boolean LANGUAGE sql AS $$
  WITH d AS (SELECT g::date AS day, s.* FROM generate_series(p_from, p_to, interval '1 day') g
               LEFT JOIN LATERAL t_day_segment(p_company, g::date) s ON true),
       k AS (SELECT d.*, lag(seg_start) OVER (ORDER BY day) AS prev_start, lag(seg_end) OVER (ORDER BY day) AS prev_end FROM d)
  SELECT bool_and(seg_start IS NOT NULL AND seg_start <= day AND day <= seg_end
                  AND (prev_start IS NULL OR seg_start = prev_start OR (seg_start = day AND prev_end = day - 1))) FROM k
$$;
-- Lengths of the weeks that START inside the range (bridge days excluded).
CREATE OR REPLACE FUNCTION t_week_lengths(p_company uuid, p_from date, p_to date) RETURNS int[] LANGUAGE sql AS $$
  SELECT array_agg(fn_company_week_end(p_company, ws) - ws + 1 ORDER BY ws)
    FROM (SELECT DISTINCT fn_company_week_start(p_company, g::date) AS ws
            FROM generate_series(p_from, p_to, interval '1 day') g) w WHERE ws >= p_from
$$;
-- The bridges inside a range as 'start..end' strings.
CREATE OR REPLACE FUNCTION t_bridges(p_company uuid, p_from date, p_to date) RETURNS text LANGUAGE sql AS $$
  SELECT string_agg(DISTINCT b.bridge_start || '..' || b.bridge_end, ',')
    FROM generate_series(p_from, p_to, interval '1 day') g, fn_company_bridge_at(p_company, g::date) b
$$;
INSERT INTO companies (company_id, company_name, country, last_workday_dow, timezone) VALUES
  ('00000000-0000-0000-0000-0000000000e1', 'TrSun', 'IL', 4, 'Asia/Jerusalem'),
  ('00000000-0000-0000-0000-0000000000e2', 'TrMon', 'DE', 5, 'Europe/Berlin'),
  ('00000000-0000-0000-0000-0000000000e3', 'TrRpc', 'IL', 4, 'Asia/Jerusalem');
SELECT t_assert('T every company gets an initial history row (in force since -infinity)',
  (SELECT count(*) = 3 AND bool_and(effective_from = '-infinity') FROM company_week_start_history
    WHERE company_id IN ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000e3'))
  AND NOT EXISTS (SELECT 1 FROM companies c WHERE NOT EXISTS (SELECT 1 FROM company_week_start_history h WHERE h.company_id = c.company_id)));
SELECT t_assert('T rule: effective_from = first new start day on/after old week start + 7 (Sun→Mon 10-18 → 10-26; Mon→Sun 10-19 → 11-01)',
  fn_week_start_effective_from(DATE '2026-10-18', 1::smallint) = DATE '2026-10-26'
  AND fn_week_start_effective_from(DATE '2026-10-19', 0::smallint) = DATE '2026-11-01');
SELECT t_assert('T bridge length = 1–6 days for every real change (all 42 old/new pairs); 0 only when the day is unchanged',
  (SELECT bool_and(fn_week_start_effective_from(DATE '2026-10-18' + o, n::smallint) - (DATE '2026-10-18' + o + 7)
                   BETWEEN CASE WHEN o = n THEN 0 ELSE 1 END AND CASE WHEN o = n THEN 0 ELSE 6 END)
     FROM generate_series(0, 6) o, generate_series(0, 6) n));
SELECT t_assert('T same start day → no change scheduled (and so no bridge)', fn_schedule_week_start_change('00000000-0000-0000-0000-0000000000e1', 0::smallint, DATE '2026-10-21') IS NULL);
SELECT t_wk(e, DATE '2026-10-20') FROM (SELECT t_mkuser('trs1@e1', '00000000-0000-0000-0000-0000000000e1', 'employee', 'employee', 'Asia/Jerusalem') IS NOT NULL, 'trs1@e1') x(ok, e);
CREATE TEMP TABLE t_trs_before AS SELECT report_id, work_date, week_start_date FROM workload_self_report
  WHERE company_id = '00000000-0000-0000-0000-0000000000e1';
SELECT t_assert('T Sun→Mon change made on Wed 2026-10-21 takes effect Mon 2026-10-26',
  fn_schedule_week_start_change('00000000-0000-0000-0000-0000000000e1', 1::smallint, DATE '2026-10-21') = DATE '2026-10-26');
SELECT t_assert('T Mon→Sun change made on Wed 2026-10-21 takes effect Sun 2026-11-01',
  fn_schedule_week_start_change('00000000-0000-0000-0000-0000000000e2', 0::smallint, DATE '2026-10-21') = DATE '2026-11-01');
SELECT t_assert('T Sun→Mon: old week, bridge, new week — no overlap, no gap (Sep–Dec 2026)', t_weeks_contiguous('00000000-0000-0000-0000-0000000000e1', DATE '2026-09-01', DATE '2026-12-31'));
SELECT t_assert('T Mon→Sun: old week, bridge, new week — no overlap, no gap (Sep–Dec 2026)', t_weeks_contiguous('00000000-0000-0000-0000-0000000000e2', DATE '2026-09-01', DATE '2026-12-31'));
SELECT t_assert('T Sun→Mon: last old week Sun 2026-10-18 … Sat 2026-10-24 (7 days), bridge Sun 2026-10-25 (1 day), new week Mon 2026-10-26 … Sun 2026-11-01',
  fn_company_week_start('00000000-0000-0000-0000-0000000000e1', DATE '2026-10-24') = DATE '2026-10-18'
  AND fn_company_week_end('00000000-0000-0000-0000-0000000000e1', DATE '2026-10-18') = DATE '2026-10-24'
  AND fn_company_week_start('00000000-0000-0000-0000-0000000000e1', DATE '2026-10-25') IS NULL
  AND t_bridges('00000000-0000-0000-0000-0000000000e1', DATE '2026-09-01', DATE '2026-12-31') = '2026-10-25..2026-10-25'
  AND fn_company_week_start('00000000-0000-0000-0000-0000000000e1', DATE '2026-10-26') = DATE '2026-10-26'
  AND fn_company_week_start('00000000-0000-0000-0000-0000000000e1', DATE '2026-11-01') = DATE '2026-10-26');
SELECT t_assert('T Mon→Sun: last old week Mon 2026-10-19 … Sun 2026-10-25 (7 days), bridge Mon 2026-10-26 … Sat 2026-10-31 (6 days), new week Sun 2026-11-01 … Sat 2026-11-07',
  fn_company_week_start('00000000-0000-0000-0000-0000000000e2', DATE '2026-10-25') = DATE '2026-10-19'
  AND fn_company_week_end('00000000-0000-0000-0000-0000000000e2', DATE '2026-10-19') = DATE '2026-10-25'
  AND t_bridges('00000000-0000-0000-0000-0000000000e2', DATE '2026-09-01', DATE '2026-12-31') = '2026-10-26..2026-10-31'
  AND fn_company_week_start('00000000-0000-0000-0000-0000000000e2', DATE '2026-11-01') = DATE '2026-11-01'
  AND fn_company_week_end('00000000-0000-0000-0000-0000000000e2', DATE '2026-11-01') = DATE '2026-11-07');
SELECT t_assert('T every week is exactly 7 days, transition included (Sep–Dec 2026, both companies)',
  (SELECT array_remove(a, 7) = '{}'::int[] AND cardinality(a) > 10 FROM t_week_lengths('00000000-0000-0000-0000-0000000000e1', DATE '2026-09-06', DATE '2026-12-31') a)
  AND (SELECT array_remove(a, 7) = '{}'::int[] AND cardinality(a) > 10 FROM t_week_lengths('00000000-0000-0000-0000-0000000000e2', DATE '2026-09-07', DATE '2026-12-31') a));
SELECT t_assert('T stored reports are never recalculated by a change',
  (SELECT count(*) = 1 FROM t_trs_before b JOIN workload_self_report w USING (report_id)
    WHERE w.work_date = b.work_date AND w.week_start_date = b.week_start_date AND w.week_start_date = DATE '2026-10-18'));
SELECT t_mkuser('trs2@e1', '00000000-0000-0000-0000-0000000000e1', 'employee', 'employee', 'Asia/Jerusalem') IS NOT NULL;
SELECT t_expect_err('T a report on the bridge day Sun 2026-10-25 → 422 bridge_period', $$SELECT t_wk('trs2@e1', DATE '2026-10-25')$$, 'bridge_period');
SELECT t_mkuser('trm1@e2', '00000000-0000-0000-0000-0000000000e2', 'employee', 'employee', 'Europe/Berlin') IS NOT NULL;
SELECT t_expect_err('T a report on any bridge day (Mon 2026-10-26 … Sat 2026-10-31) → 422 bridge_period',
  $$SELECT t_wk('trm1@e2', d::date) FROM generate_series(DATE '2026-10-26', DATE '2026-10-31', interval '1 day') d$$, 'bridge_period');
SELECT t_assert('T no report was stored on a bridge day', NOT EXISTS (SELECT 1 FROM workload_self_report w WHERE EXISTS (SELECT 1 FROM fn_company_bridge_at(w.company_id, w.work_date))));
SELECT t_expect_err('T 409 still works in a normal week: Sat 2026-10-24 duplicates week 2026-10-18',
  $$SELECT t_wk('trs1@e1', DATE '2026-10-24')$$, '23505');
SELECT t_assert('T the first new week starts Monday 2026-10-26 for the same employee',
  t_wk('trs1@e1', DATE '2026-10-26') = DATE '2026-10-26');
SELECT t_assert('T Mon→Sun: the last old week accepts a report (Sun 2026-10-25 → week 2026-10-19)',
  t_wk('trm1@e2', DATE '2026-10-25') = DATE '2026-10-19');
SELECT t_assert('T Mon→Sun: the first new week accepts a report (Sun 2026-11-01 → week 2026-11-01)',
  t_wk('trm1@e2', DATE '2026-11-01') = DATE '2026-11-01');
SELECT t_assert('T the history is append-only', (SELECT count(*) = 2 FROM company_week_start_history WHERE company_id = '00000000-0000-0000-0000-0000000000e1'));
SELECT t_expect_err('T a history row cannot be rewritten',
  $$UPDATE company_week_start_history SET week_start_dow = 3 WHERE company_id = '00000000-0000-0000-0000-0000000000e1'$$, 'week_start_history_immutable');
SELECT t_assert('T every change audited with the bridge dates (old, new, effective_from, 7-day last old week, bridge start / end / days)',
  (SELECT count(*) = 2 AND bool_and(scope ? 'old_week_start_dow' AND scope ? 'new_week_start_dow' AND scope ? 'effective_from'
                                    AND (scope->>'final_old_week_days')::int = 7)
     FROM access_audit_log WHERE action = 'company_week_start_change'
      AND company_id IN ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000e2'))
  AND (SELECT string_agg(concat_ws('/', scope->>'final_old_week_end', scope->>'bridge_start', scope->>'bridge_end', scope->>'bridge_days'), ',' ORDER BY company_id)
         FROM access_audit_log WHERE action = 'company_week_start_change'
          AND company_id IN ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000e2'))
      = '2026-10-24/2026-10-25/2026-10-25/1,2026-10-25/2026-10-26/2026-10-31/6');
SELECT t_assert('T reminder of the last old week: Fri 2026-10-23 14:00 Berlin (inside its 7 days)',
  fn_company_reminder_at('00000000-0000-0000-0000-0000000000e2', DATE '2026-10-19') = TIMESTAMPTZ '2026-10-23 14:00 Europe/Berlin');
SELECT t_assert('T no reminder in a bridge: none for a bridge day, and no week reminder falls on a bridge day (Sep–Dec, both companies)',
  fn_company_reminder_at('00000000-0000-0000-0000-0000000000e2', DATE '2026-10-26') IS NULL
  AND fn_company_reminder_at('00000000-0000-0000-0000-0000000000e1', DATE '2026-10-25') IS NULL
  AND (SELECT bool_and(NOT EXISTS (SELECT 1 FROM fn_company_bridge_at(c, (fn_company_reminder_at(c, g::date) AT TIME ZONE z)::date))
                       AND (fn_company_reminder_at(c, g::date) AT TIME ZONE z)::date BETWEEN g::date AND g::date + 6)
         FROM (VALUES ('00000000-0000-0000-0000-0000000000e1'::uuid, 'Asia/Jerusalem'), ('00000000-0000-0000-0000-0000000000e2'::uuid, 'Europe/Berlin')) x(c, z),
              generate_series(DATE '2026-09-01', DATE '2026-12-31', interval '1 day') g
        WHERE fn_company_week_start(c, g::date) = g::date));
SELECT t_assert('T the CHRO change (R) went through the history at the next boundary, after every stored report',
  (SELECT count(*) = 3 FROM company_week_start_history WHERE company_id = '00000000-0000-0000-0000-0000000000c3')
  AND (SELECT min(effective_from) FILTER (WHERE effective_from > '-infinity') > (SELECT max(work_date) FROM workload_self_report WHERE company_id = '00000000-0000-0000-0000-0000000000c3')
         FROM company_week_start_history WHERE company_id = '00000000-0000-0000-0000-0000000000c3')
  AND t_weeks_contiguous('00000000-0000-0000-0000-0000000000c3', CURRENT_DATE - 30, CURRENT_DATE + 60));
INSERT INTO companies (company_id, company_name, country, last_workday_dow, timezone) VALUES ('00000000-0000-0000-0000-0000000000e4', 'TrUpd', 'IL', 4, 'Asia/Jerusalem');
CREATE TEMP TABLE t_e4_ws AS SELECT fn_company_week_start('00000000-0000-0000-0000-0000000000e4', fn_week_change_base('00000000-0000-0000-0000-0000000000e4')) AS ws;
UPDATE companies SET week_start_dow = 1 WHERE company_id = '00000000-0000-0000-0000-0000000000e4';
SELECT t_assert('T a change is never blocked: a direct UPDATE is scheduled at fn_week_start_effective_from(current week, new day)',
  (SELECT h.effective_from = fn_week_start_effective_from(t.ws, 1::smallint) AND h.week_start_dow = 1 AND h.effective_from > CURRENT_DATE
     FROM company_week_start_history h, t_e4_ws t
    WHERE h.company_id = '00000000-0000-0000-0000-0000000000e4' AND h.effective_from > '-infinity'));
-- RPC path around a bridge inside the submit range: a Sun→Mon change whose last old week starts S
SELECT t_mkuser('trr1@e3', '00000000-0000-0000-0000-0000000000e3', 'employee', 'employee', 'Asia/Jerusalem') IS NOT NULL;
CREATE TEMP TABLE t_tr AS SELECT fn_week_start_for(fn_user_local_day(t_x('trr1@e3')) - 8, 0::smallint) AS s;
INSERT INTO company_week_start_history (company_id, effective_from, week_start_dow)
  SELECT '00000000-0000-0000-0000-0000000000e3', fn_week_start_effective_from(s, 1::smallint), 1 FROM t_tr;
GRANT SELECT ON t_tr TO authenticated;
SELECT t_as(t_x('trr1@e3'));
SET ROLE authenticated;
SELECT t_assert('T RPC: Sunday S of the last old week keys S',
  (SELECT r.week_start_date = t.s FROM t_tr t, rpc_submit_workload_self_report(40, 40, 0, 1, 1, 1, (SELECT s FROM t_tr)) r));
SELECT t_expect_err('T RPC 409 in a normal week: S + 1 is the same week as S',
  format($$SELECT * FROM rpc_submit_workload_self_report(40, 40, 0, 1, 1, 1, %L)$$, (SELECT s + 1 FROM t_tr)), 'workload_report_already_submitted');
SELECT t_expect_err('T RPC 422 in the bridge: S + 7 (Sunday, bridge day) → bridge_period',
  format($$SELECT * FROM rpc_submit_workload_self_report(40, 40, 0, 1, 1, 1, %L)$$, (SELECT s + 7 FROM t_tr)), 'bridge_period');
SELECT t_assert('T RPC: S + 8 (first Monday) opens the first new week',
  (SELECT r.week_start_date = t.s + 8 FROM t_tr t, rpc_submit_workload_self_report(40, 40, 0, 1, 1, 1, (SELECT s + 8 FROM t_tr)) r));
RESET ROLE;

-- ============ v1.6.5 M. Migration: legacy projects → non-core until the PM marks them ============
ALTER TABLE project ALTER COLUMN is_core DROP NOT NULL;     -- simulate a pre-1.6.4 database
INSERT INTO project (project_id, company_id, name, project_manager_id) VALUES
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000c2', 'Legacy', t_u('pm'));
INSERT INTO project_member VALUES ('00000000-0000-0000-0000-0000000000b1', t_u('e4'));
CREATE TEMP TABLE t_mig AS SELECT fn_migrate_project_is_core() AS n;
SELECT t_assert('M migration step marks the legacy project non-core', (SELECT n = 1 FROM t_mig)
  AND (SELECT is_core = false FROM project WHERE project_id = '00000000-0000-0000-0000-0000000000b1'));
SELECT t_assert('M legacy project does not count toward WIP (e4: P1 + P3 core only)',
  fn_core_assignment_count(t_u('e4')) = 2 AND NOT EXISTS (SELECT 1 FROM wip_alert WHERE recipient_id = t_u('e4')));
SELECT t_assert('M after migration is_core is NOT NULL with no default',
  (SELECT is_nullable = 'NO' AND column_default IS NULL FROM information_schema.columns WHERE table_name = 'project' AND column_name = 'is_core'));
SELECT t_as(t_u('pm'));
SET ROLE authenticated;
SELECT t_expect_err('M new project without is_core still rejected', $$SELECT * FROM rpc_project_create('New', NULL)$$, 'project_is_core_required');
RESET ROLE;
SELECT t_expect_err('M direct insert without is_core still rejected', $$INSERT INTO project (company_id, name) VALUES ('00000000-0000-0000-0000-0000000000c2', 'N2')$$, '23502');

-- ============ v1.6.6 L. CLDR / tz reference (Chief of Drive, O-37) ============
SELECT t_assert('L reference table generated from CLDR + IANA tz (source recorded)',
  (SELECT cldr_source LIKE 'CLDR 48 %weekData.json' AND tz_source LIKE 'IANA tzdata % zone.tab' FROM ref_country_calendar_source)
  AND (SELECT count(*) > 200 FROM ref_country_calendar));
SELECT t_assert('L CLDR world default 001: firstDay Monday, weekend starts Saturday',
  (SELECT first_day_dow = 1 AND weekend_start_dow = 6 FROM ref_country_calendar WHERE country = '001'));
SELECT t_assert('L IL default week start = Sunday (pinned; CLDR also sun)',
  fn_default_week_start_dow('IL') = 0 AND (SELECT first_day_dow = 0 FROM ref_country_calendar WHERE country = 'IL'));
SELECT t_assert('L US default week start = Sunday (CLDR firstDay sun)', fn_default_week_start_dow('US') = 0);
SELECT t_assert('L DE default week start = Monday (CLDR firstDay mon)', fn_default_week_start_dow('de') = 1);
SELECT t_assert('L country unknown to CLDR falls back to 001 (Monday)',
  NOT EXISTS (SELECT 1 FROM ref_country_calendar WHERE country = 'XX') AND fn_default_week_start_dow('XX') = 1);
SELECT t_assert('L no hand-coded country list in the default function (only the IL pin)',
  (SELECT prosrc !~ '''(US|DE|FR|GB)''' FROM pg_proc WHERE proname = 'fn_default_week_start_dow'));
INSERT INTO companies (company_name, country, last_workday_dow, timezone) VALUES ('UsCo', 'US', 5, 'America/New_York');
SELECT t_assert('L US company created with the CLDR default (Sunday)',
  (SELECT week_start_dow = 0 FROM companies WHERE company_name = 'UsCo'));
SELECT t_assert('L last workday = day before the CLDR weekend: IL Thu (4), DE Fri (5), US Fri (5)',
  fn_default_last_workday_dow('IL') = 4 AND fn_default_last_workday_dow('DE') = 5 AND fn_default_last_workday_dow('US') = 5);
SELECT t_assert('L main zone = first zone.tab entry: IL Asia/Jerusalem, DE Europe/Berlin, US America/New_York',
  fn_default_timezone('IL') = 'Asia/Jerusalem' AND fn_default_timezone('DE') = 'Europe/Berlin' AND fn_default_timezone('US') = 'America/New_York');
SELECT t_assert('L multi-zone countries flagged (US > 1 zone; IL 1; DE 1 — v1.6.8; CY, MH, MY, PS 1 — v1.6.9 exclusions; UZ 1 — v1.6.10)',
  (SELECT count(*) = 8 AND bool_and(CASE country WHEN 'US' THEN tz_zone_count > 1 ELSE tz_zone_count = 1 END)
     FROM ref_country_calendar WHERE country IN ('IL', 'US', 'DE', 'CY', 'MH', 'MY', 'PS', 'UZ')));
SELECT t_assert('L zone exclusion list documented in the table: exactly one excluded zone each for CY, DE, MH, MY, PS, UZ (rulings 21.10; UZ: Samarkand since v1.6.10)',
  (SELECT string_agg(country || ':' || split_part(tz_zones_excluded, ' ', 1), ',' ORDER BY country) FROM ref_country_calendar WHERE tz_zones_excluded IS NOT NULL)
    = 'CY:Asia/Famagusta,DE:Europe/Busingen,MH:Pacific/Kwajalein,MY:Asia/Kuching,PS:Asia/Hebron,UZ:Asia/Samarkand'
  AND (SELECT bool_and(tz_zones_excluded LIKE '%(ruling: Chief of Drive 21.10%' AND tz_zones_excluded NOT LIKE '%); %') FROM ref_country_calendar WHERE tz_zones_excluded IS NOT NULL));
SELECT t_assert('L multi-zone countries after the exclusions: 25 (zone.tab 2026c; was 30 in v1.6.8)',
  (SELECT count(*) = 25 FROM ref_country_calendar WHERE tz_zone_count > 1));
SELECT t_assert('L UA pinned to Europe/Kyiv (explicit override, O-51); Simferopol not excluded → still 2 zones',
  (SELECT main_timezone = 'Europe/Kyiv' AND main_timezone_source LIKE 'override: Chief of Drive 21.10%' AND tz_zone_count = 2 AND tz_zones_excluded IS NULL
     FROM ref_country_calendar WHERE country = 'UA') AND fn_default_timezone('UA') = 'Europe/Kyiv');
-- v1.6.10 (Chief of Drive 21.10): the pin is final — a pinned country is never needs_review (generic rule)
SELECT t_assert('L v1.6.10 multi-zone countries needing review (zone count > 1, not pinned): 24 = 25 − UA',
  (SELECT count(*) = 24 FROM ref_country_calendar WHERE fn_country_tz_needs_review(country))
  AND NOT fn_country_tz_needs_review('UA') AND fn_country_tz_needs_review('US') AND NOT fn_country_tz_needs_review('IL'));
SELECT t_assert('L v1.6.10 pin rule is generic: every pinned (override) country is exempt from review',
  (SELECT bool_and(NOT fn_country_tz_needs_review(country)) FROM ref_country_calendar WHERE main_timezone_source LIKE 'override:%'));
SELECT t_assert('L v1.6.10 UZ keeps the capital Asia/Tashkent; Samarkand excluded (same offset), 1 zone',
  (SELECT main_timezone = 'Asia/Tashkent' AND tz_zone_count = 1 AND tz_zones_excluded LIKE 'Asia/Samarkand (ruling: Chief of Drive 21.10%'
     FROM ref_country_calendar WHERE country = 'UZ') AND fn_default_timezone('UZ') = 'Asia/Tashkent');
SELECT t_assert('L v1.6.10 UZ: Asia/Samarkand has the same UTC offset as Asia/Tashkent every hour 2026–2037',
  (SELECT bool_and(((t AT TIME ZONE 'Asia/Samarkand') - (t AT TIME ZONE 'Asia/Tashkent')) = interval '0')
     FROM generate_series(TIMESTAMPTZ '2026-01-01 00:00+00', TIMESTAMPTZ '2037-12-31 23:00+00', interval '1 hour') t));
SELECT t_expect_err('L reference table not readable by clients', $$SET LOCAL ROLE authenticated; SELECT count(*) FROM ref_country_calendar$$, '42501');

-- ============ v1.6.6 U. Upgrade backfill of legacy companies (O-39) ============
ALTER TABLE companies ALTER COLUMN week_start_dow DROP NOT NULL, ALTER COLUMN last_workday_dow DROP NOT NULL,
                      ALTER COLUMN timezone DROP NOT NULL;      -- simulate a pre-1.6.5 database
ALTER TABLE companies DISABLE TRIGGER trg_companies_timezone;
ALTER TABLE companies DISABLE TRIGGER trg_companies_week_start;
INSERT INTO companies (company_id, company_name, country) VALUES
  ('00000000-0000-0000-0000-0000000000d1', 'LegacyIL', 'IL'),
  ('00000000-0000-0000-0000-0000000000d2', 'LegacyDE', 'DE');
INSERT INTO companies (company_id, company_name, country, week_start_dow, last_workday_dow, timezone) VALUES
  ('00000000-0000-0000-0000-0000000000d3', 'LegacyKept', 'DE', 0, 3, 'Asia/Jerusalem');
ALTER TABLE companies ENABLE TRIGGER trg_companies_timezone;
ALTER TABLE companies ENABLE TRIGGER trg_companies_week_start;
CREATE TEMP TABLE t_bf AS SELECT fn_backfill_company_calendar() AS n;
SELECT t_assert('U backfill filled 6 values (3 per legacy company)', (SELECT n = 6 FROM t_bf));
SELECT t_assert('U IL legacy company → Sunday, Thursday, Asia/Jerusalem',
  (SELECT week_start_dow = 0 AND last_workday_dow = 4 AND timezone = 'Asia/Jerusalem' FROM companies WHERE company_id = '00000000-0000-0000-0000-0000000000d1'));
SELECT t_assert('U DE legacy company → Monday, Friday, Europe/Berlin',
  (SELECT week_start_dow = 1 AND last_workday_dow = 5 AND timezone = 'Europe/Berlin' FROM companies WHERE company_id = '00000000-0000-0000-0000-0000000000d2'));
SELECT t_assert('U explicit legacy values are never overwritten',
  (SELECT week_start_dow = 0 AND last_workday_dow = 3 AND timezone = 'Asia/Jerusalem' FROM companies WHERE company_id = '00000000-0000-0000-0000-0000000000d3'));
SELECT t_assert('U every backfilled value audited as auto-filled (field, value, source)',
  (SELECT count(*) = 6 AND bool_and((scope->>'auto_filled')::boolean AND scope ? 'field' AND scope ? 'value' AND scope ? 'cldr_source' AND scope ? 'tz_source')
     FROM access_audit_log WHERE action = 'company_calendar_autofill')
  AND (SELECT string_agg(scope->>'field' || '=' || (scope->>'value'), ',' ORDER BY scope->>'field')
         FROM access_audit_log WHERE action = 'company_calendar_autofill' AND company_id = '00000000-0000-0000-0000-0000000000d1')
      = 'last_workday_dow=4,timezone=Asia/Jerusalem,week_start_dow=0');
SELECT t_assert('U calendar columns NOT NULL again after a complete backfill',
  (SELECT bool_and(attnotnull) FROM pg_attribute WHERE attrelid = 'companies'::regclass
     AND attname IN ('country', 'week_start_dow', 'last_workday_dow', 'timezone')));
SELECT t_assert('U backfill is idempotent (nothing left to fill)', fn_backfill_company_calendar() = 0);
SELECT t_assert('U new companies still need last workday and timezone (no create-time default)',
  (SELECT column_default IS NULL FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'last_workday_dow')
  AND (SELECT column_default IS NULL FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'timezone'));

-- ============ v1.6.7 Z. Timezone review + reminder hold (Chief of Drive, O-43) ============
SELECT t_assert('Z XK and AN zones are explicit, documented overrides in the generated table (next to the IL pin)',
  (SELECT string_agg(country || '=' || main_timezone || '|' || main_timezone_source, ',' ORDER BY country) FROM ref_country_calendar WHERE country IN ('XK', 'AN'))
    = 'AN=America/Curacao|override: Chief of Drive 20.10 (O-43),XK=Europe/Belgrade|override: Chief of Drive 20.10 (O-43)'
  AND (SELECT first_day_source LIKE 'override: Karin%' FROM ref_country_calendar WHERE country = 'IL'));
ALTER TABLE companies ALTER COLUMN country DROP NOT NULL, ALTER COLUMN week_start_dow DROP NOT NULL,
                      ALTER COLUMN last_workday_dow DROP NOT NULL, ALTER COLUMN timezone DROP NOT NULL;   -- legacy again
ALTER TABLE companies DISABLE TRIGGER trg_companies_timezone;
ALTER TABLE companies DISABLE TRIGGER trg_companies_week_start;
INSERT INTO companies (company_id, company_name, country) VALUES
  ('00000000-0000-0000-0000-0000000000f1', 'LegUS', 'US'), ('00000000-0000-0000-0000-0000000000f2', 'LegIL', 'IL'),
  ('00000000-0000-0000-0000-0000000000f3', 'LegDE', 'DE'), ('00000000-0000-0000-0000-0000000000f4', 'LegXK', 'XK'),
  ('00000000-0000-0000-0000-0000000000f5', 'LegAN', 'AN');
INSERT INTO companies (company_id, company_name) VALUES
  ('00000000-0000-0000-0000-0000000000f6', 'LegNone'), ('00000000-0000-0000-0000-0000000000f7', 'LegNone2');
ALTER TABLE companies ENABLE TRIGGER trg_companies_timezone;
ALTER TABLE companies ENABLE TRIGGER trg_companies_week_start;
CREATE TEMP TABLE t_bf2 AS SELECT fn_backfill_company_calendar() AS n;
CREATE OR REPLACE FUNCTION t_tzs(p_id text) RETURNS text LANGUAGE sql AS $$
  SELECT timezone || '|' || timezone_status FROM companies WHERE company_id = ('00000000-0000-0000-0000-0000000000' || p_id)::uuid $$;
SELECT t_assert('Z US backfill keeps the first zone.tab zone and is needs_review', t_tzs('f1') = 'America/New_York|needs_review');
SELECT t_assert('Z IL (1 zone) backfill is not flagged', t_tzs('f2') = 'Asia/Jerusalem|confirmed');
SELECT t_assert('Z DE: Busingen is excluded (exclave, ruling 21.10) → single-zone, NOT needs_review', t_tzs('f3') = 'Europe/Berlin|confirmed');
SELECT t_assert('Z XK → Europe/Belgrade, AN → America/Curacao (overrides; not multi-zone)',
  t_tzs('f4') = 'Europe/Belgrade|confirmed' AND t_tzs('f5') = 'America/Curacao|confirmed');
SELECT t_assert('Z backfilled values audited as auto-filled (15 = 5 companies × 3)', (SELECT n = 15 FROM t_bf2));
SELECT t_assert('Z no-country company: no backfill, needs_review, reminders held',
  (SELECT country IS NULL AND week_start_dow IS NULL AND timezone IS NULL AND timezone_status = 'needs_review' AND reminders_on_hold
     FROM companies WHERE company_id = '00000000-0000-0000-0000-0000000000f6'));
SELECT t_assert('Z ''reminders on hold'' audit row exists (one per held company)',
  (SELECT count(*) = 2 AND bool_and(scope->>'reason' = 'no_country') FROM access_audit_log WHERE action = 'reminders_on_hold'
    AND company_id IN ('00000000-0000-0000-0000-0000000000f6', '00000000-0000-0000-0000-0000000000f7')));
SELECT t_assert('Z held company has no reminder time', fn_company_reminder_at('00000000-0000-0000-0000-0000000000f6', DATE '2026-10-18') IS NULL);
SELECT t_assert('Z backfill again: nothing new, still held (no duplicate hold audit)',
  fn_backfill_company_calendar() = 0 AND (SELECT count(*) = 2 FROM access_audit_log WHERE action = 'reminders_on_hold'));
UPDATE companies SET country = 'il' WHERE company_id = '00000000-0000-0000-0000-0000000000f6';
SELECT t_assert('Z setting the country backfills and releases reminders (IL → Thu, Asia/Jerusalem, confirmed)',
  (SELECT country = 'IL' AND week_start_dow = 0 AND last_workday_dow = 4 AND timezone = 'Asia/Jerusalem'
          AND timezone_status = 'confirmed' AND NOT reminders_on_hold FROM companies WHERE company_id = '00000000-0000-0000-0000-0000000000f6'));
SELECT t_assert('Z ''reminders released'' audit row exists', (SELECT count(*) = 1 FROM access_audit_log
  WHERE action = 'reminders_released' AND company_id = '00000000-0000-0000-0000-0000000000f6' AND scope->>'country' = 'IL'));
SELECT t_assert('Z released company has a reminder again (Thu 2026-10-22 14:00 Asia/Jerusalem)',
  fn_company_reminder_at('00000000-0000-0000-0000-0000000000f6', DATE '2026-10-18') = TIMESTAMPTZ '2026-10-22 14:00 Asia/Jerusalem');
-- HR settings API: the flag is exposed; the CHRO confirms (audited); others cannot
SELECT t_mkuser('chro@f1', '00000000-0000-0000-0000-0000000000f1', 'vp_hr', 'vp', 'America/New_York') IS NOT NULL;
SELECT t_mkuser('emp@f1', '00000000-0000-0000-0000-0000000000f1', 'employee', 'employee', 'America/New_York') IS NOT NULL;
SELECT t_mkuser('chro@f7', '00000000-0000-0000-0000-0000000000f7', 'vp_hr', 'vp', 'Europe/Berlin') IS NOT NULL;
SELECT t_as(t_x('emp@f1'));
SET ROLE authenticated;
SELECT t_assert('Z settings API exposes timezone_status = needs_review (UI warning)',
  (SELECT timezone_status = 'needs_review' AND timezone = 'America/New_York' AND NOT reminders_on_hold FROM rpc_company_settings()));
SELECT t_expect_err('Z an employee cannot confirm the timezone', $$SELECT * FROM rpc_company_timezone_confirm()$$, 'access_denied');
RESET ROLE;
SELECT t_as(t_x('chro@f1'));
SET ROLE authenticated;
SELECT t_assert('Z the CHRO confirms the timezone → confirmed', (SELECT timezone_status = 'confirmed' AND timezone = 'America/New_York' FROM rpc_company_timezone_confirm()));
RESET ROLE;
SELECT t_assert('Z timezone confirmation audited (previous status needs_review)',
  (SELECT count(*) = 1 FROM access_audit_log WHERE action = 'company_timezone_confirmed' AND company_id = '00000000-0000-0000-0000-0000000000f1'
      AND scope->>'previous_status' = 'needs_review' AND viewer_id = t_x('chro@f1')));
SELECT t_as(t_x('chro@f7'));
SET ROLE authenticated;
SELECT t_assert('Z held company: the CHRO sees the hold', (SELECT reminders_on_hold AND timezone_status = 'needs_review' AND country IS NULL FROM rpc_company_settings()));
SELECT t_expect_http('Z unknown country code (ZZ) → 422 unknown_country', $$SELECT * FROM rpc_company_settings_update(p_country => 'zz')$$, 'unknown_country', 422);
SELECT t_assert('Z …and the hold stays (country still NULL, reminders on hold)',
  (SELECT reminders_on_hold AND country IS NULL AND timezone_status = 'needs_review' FROM rpc_company_settings()));
SELECT t_assert('Z the CHRO sets a known country (DE) → released, timezone confirmed (single-zone after the Busingen exclusion)',
  (SELECT NOT reminders_on_hold AND country = 'DE' AND timezone = 'Europe/Berlin' AND timezone_status = 'confirmed'
         AND last_workday_dow = 5 AND week_start_dow = 1 FROM rpc_company_settings_update(p_country => 'de')));
RESET ROLE;
SELECT t_expect_err('Z unknown country on a direct update is refused too (unknown_country)',
  $$UPDATE companies SET country = 'QQ' WHERE company_id = '00000000-0000-0000-0000-0000000000f7'$$, 'unknown_country');
SELECT t_assert('Z released via the CHRO API is audited too',
  (SELECT count(*) = 1 FROM access_audit_log WHERE action = 'reminders_released' AND company_id = '00000000-0000-0000-0000-0000000000f7'));
-- v1.6.9 (O-51): legacy companies of the newly single-zone countries, UA and US, backfilled
ALTER TABLE companies DISABLE TRIGGER trg_companies_timezone;
ALTER TABLE companies DISABLE TRIGGER trg_companies_week_start;
INSERT INTO companies (company_name, country) SELECT 'O51' || c, c FROM unnest(ARRAY['CY', 'MH', 'MY', 'PS', 'UZ', 'UA', 'US']) c;
INSERT INTO companies (company_name, country) VALUES ('O54UA_held', NULL);   -- v1.6.10: released later with UA
ALTER TABLE companies ENABLE TRIGGER trg_companies_timezone;
ALTER TABLE companies ENABLE TRIGGER trg_companies_week_start;
CREATE TEMP TABLE t_bf4 AS SELECT fn_backfill_company_calendar() AS n;
SELECT t_assert('Z O-51: CY, MH, MY, PS, UZ backfill → kept zone, single-zone, confirmed (not needs_review)',
  (SELECT string_agg(country || '=' || timezone || '|' || timezone_status, ',' ORDER BY country) FROM companies
    WHERE company_name IN ('O51CY', 'O51MH', 'O51MY', 'O51PS', 'O51UZ'))
    = 'CY=Asia/Nicosia|confirmed,MH=Pacific/Majuro|confirmed,MY=Asia/Kuala_Lumpur|confirmed,PS=Asia/Gaza|confirmed,UZ=Asia/Tashkent|confirmed');
SELECT t_assert('Z v1.6.10: UA backfill → Europe/Kyiv (pinned), confirmed — the pin overrides the multi-zone check',
  (SELECT timezone = 'Europe/Kyiv' AND timezone_status = 'confirmed' FROM companies WHERE company_name = 'O51UA'));
SELECT t_assert('Z v1.6.10: company without a country held by the backfill (before the UA release test)',
  (SELECT reminders_on_hold AND country IS NULL FROM companies WHERE company_name = 'O54UA_held'));
UPDATE companies SET country = 'UA' WHERE company_name = 'O54UA_held';
SELECT t_assert('Z v1.6.10: held company released with country UA → Europe/Kyiv, confirmed, reminders released (release path, same pin rule)',
  (SELECT timezone = 'Europe/Kyiv' AND timezone_status = 'confirmed' AND NOT reminders_on_hold FROM companies WHERE company_name = 'O54UA_held'));
SELECT t_assert('Z O-51: US backfill still needs_review', (SELECT timezone = 'America/New_York' AND timezone_status = 'needs_review' FROM companies WHERE company_name = 'O51US'));
CREATE TEMP TABLE t_bf3 AS SELECT fn_backfill_company_calendar() AS n;
SELECT t_assert('Z calendar complete again → columns NOT NULL after the next backfill run',
  (SELECT n = 0 FROM t_bf3) AND (SELECT bool_and(attnotnull) FROM pg_attribute WHERE attrelid = 'companies'::regclass
     AND attname IN ('country', 'week_start_dow', 'last_workday_dow', 'timezone')));

-- ============ v1.6.8 O49. TPS 30-day wait: team_join → hire → exempt, audited per user (Karin 21.10) ============
DO $$
DECLARE v uuid;
BEGIN
  FOREACH v IN ARRAY ARRAY['00000000-0000-0000-0000-0000000e4901'::uuid, '00000000-0000-0000-0000-0000000e4902'::uuid,
                           '00000000-0000-0000-0000-0000000e4903'::uuid, '00000000-0000-0000-0000-0000000e4904'::uuid,
                           '00000000-0000-0000-0000-0000000e4905'::uuid] LOOP
    INSERT INTO auth.users (id) VALUES (v);
  END LOOP;
  INSERT INTO users (user_id, company_id, email, full_name, department, app_role, timezone, hire_date, team_joined_at) VALUES
    ('00000000-0000-0000-0000-0000000e4901', '00000000-0000-0000-0000-0000000000c1', 'tj10@o49', 'TJ 10', 'O49', 'employee', 'Asia/Jerusalem', CURRENT_DATE - 100, clock_timestamp() - interval '10 days'),
    ('00000000-0000-0000-0000-0000000e4902', '00000000-0000-0000-0000-0000000000c1', 'hi40@o49', 'Hire 40', 'O49', 'employee', 'Asia/Jerusalem', CURRENT_DATE - 40, NULL),
    ('00000000-0000-0000-0000-0000000e4903', '00000000-0000-0000-0000-0000000000c1', 'hi10@o49', 'Hire 10', 'O49', 'employee', 'Asia/Jerusalem', CURRENT_DATE - 10, NULL),
    ('00000000-0000-0000-0000-0000000e4904', '00000000-0000-0000-0000-0000000000c1', 'ex@o49', 'Exempt', 'O49', 'employee', 'Asia/Jerusalem', NULL, NULL),
    ('00000000-0000-0000-0000-0000000e4905', '00000000-0000-0000-0000-0000000000c1', 'sd@o49', 'No hire date', 'O49', 'employee', 'Asia/Jerusalem', NULL, NULL);
END $$;
SELECT t_assert('O49 sources: team_join beats hire; hire when no team join; exempt with neither',
  (SELECT string_agg(u.email || '=' || w.source, ',' ORDER BY u.email) FROM users u, fn_tps_wait_start(u.user_id) w WHERE u.department = 'O49')
    = 'ex@o49=exempt,hi10@o49=hire,hi40@o49=hire,sd@o49=exempt,tj10@o49=team_join');
SELECT t_assert('O49 wait start = team join (local date) or hire_date; NULL when exempt',
  (SELECT w.wait_start = CURRENT_DATE - 10 FROM fn_tps_wait_start('00000000-0000-0000-0000-0000000e4901') w)
  AND (SELECT w.wait_start = CURRENT_DATE - 40 FROM fn_tps_wait_start('00000000-0000-0000-0000-0000000e4902') w)
  AND (SELECT w.wait_start IS NULL FROM fn_tps_wait_start('00000000-0000-0000-0000-0000000e4904') w));
SELECT t_assert('O50 a new user with no hire_date: hire_date and start_date NULL (no ''today'' default), exempt from the TPS wait',
  (SELECT team_joined_at IS NULL AND hire_date IS NULL AND start_date IS NULL FROM users WHERE email = 'sd@o49')
  AND (SELECT source = 'exempt' AND wait_start IS NULL FROM fn_tps_wait_start('00000000-0000-0000-0000-0000000e4905')));
SELECT t_as('00000000-0000-0000-0000-0000000e4901');
SET ROLE authenticated;
SELECT t_expect_err('O49 team_join 10 days ago (hired 100 days ago) → TPS not eligible', $$SELECT rpc_submit_questionnaire('TPS-12', '{3,3,3,3,3,3,3,3,3,3,3,3}')$$, 'questionnaire_not_eligible');
RESET ROLE;
SELECT t_as('00000000-0000-0000-0000-0000000e4902');
SET ROLE authenticated;
SELECT t_assert('O49 hire 40 days ago, no team join → TPS eligible', (SELECT questionnaire_code = 'TPS-12' FROM rpc_submit_questionnaire('TPS-12', '{3,3,3,3,3,3,3,3,3,3,3,3}')));
RESET ROLE;
SELECT t_as('00000000-0000-0000-0000-0000000e4903');
SET ROLE authenticated;
SELECT t_expect_err('O49 hire 10 days ago, no team join → TPS not eligible', $$SELECT rpc_submit_questionnaire('TPS-12', '{3,3,3,3,3,3,3,3,3,3,3,3}')$$, 'questionnaire_not_eligible');
RESET ROLE;
SELECT t_as('00000000-0000-0000-0000-0000000e4904');
SET ROLE authenticated;
SELECT t_assert('O49 neither date → exempt from the wait (TPS accepted on day one)', (SELECT questionnaire_code = 'TPS-12' FROM rpc_submit_questionnaire('TPS-12', '{3,3,3,3,3,3,3,3,3,3,3,3}')));
RESET ROLE;
SELECT t_assert('O49 one audit row per user with the source used (team_join / hire / exempt), no answers in it',
  (SELECT string_agg(a.scope->>'source', ',' ORDER BY u.email) FROM users u JOIN access_audit_log a
      ON a.action = 'tps_wait_source' AND a.scope->>'user_id' = u.user_id::text WHERE u.department = 'O49')
    = 'exempt,hire,hire,exempt,team_join'
  AND (SELECT bool_and(a.viewer_id IS NULL AND a.company_id = '00000000-0000-0000-0000-0000000000c1' AND NOT a.scope ? 'answers')
         FROM access_audit_log a WHERE a.action = 'tps_wait_source' AND a.scope->>'user_id' LIKE '00000000-0000-0000-0000-0000000e49%'));
UPDATE users SET hire_date = CURRENT_DATE - 35 WHERE email = 'ex@o49';
UPDATE users SET hire_date = CURRENT_DATE - 35 WHERE email = 'ex@o49';
SELECT t_assert('O49 a source change is audited again (exempt → hire); an unchanged value writes nothing',
  (SELECT string_agg(a.scope->>'source', ',' ORDER BY a.created_at) FROM access_audit_log a
    WHERE a.action = 'tps_wait_source' AND a.scope->>'user_id' = '00000000-0000-0000-0000-0000000e4904') = 'exempt,hire');
UPDATE users SET department = 'O49b' WHERE email = 'hi40@o49';
SELECT t_assert('O49 a team transfer switches the source to team_join (audited)',
  (SELECT source = 'team_join' AND wait_start = CURRENT_DATE FROM fn_tps_wait_start('00000000-0000-0000-0000-0000000e4902'))
  AND (SELECT string_agg(a.scope->>'source', ',' ORDER BY a.created_at) FROM access_audit_log a
        WHERE a.action = 'tps_wait_source' AND a.scope->>'user_id' = '00000000-0000-0000-0000-0000000e4902') = 'hire,team_join');
SELECT t_assert('O49 every user has a source audit row; the upgrade backfill is idempotent (0 written now)',
  fn_tps_wait_audit_backfill() = 0
  AND NOT EXISTS (SELECT 1 FROM users u WHERE NOT EXISTS (SELECT 1 FROM access_audit_log a WHERE a.action = 'tps_wait_source' AND a.scope->>'user_id' = u.user_id::text)));
SELECT t_assert('O49 hire_date exists, nullable, no default',
  (SELECT is_nullable = 'YES' AND column_default IS NULL AND data_type = 'date' FROM information_schema.columns
    WHERE table_name = 'users' AND column_name = 'hire_date'));

-- ============ v1.6.9 O50. hire_date single source; start_date = deprecated read-only alias (Chief of Drive 21.10) ============
SELECT t_assert('O50 start_date is a generated column = hire_date (read-only alias), no default',
  (SELECT is_generated = 'ALWAYS' AND generation_expression = 'hire_date' AND column_default IS NULL AND is_nullable = 'YES'
     FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'start_date')
  AND col_description('users'::regclass, (SELECT attnum FROM pg_attribute WHERE attrelid = 'users'::regclass AND attname = 'start_date')) LIKE 'DEPRECATED%v1.7%');
SELECT t_assert('O50 start_date equals hire_date for every user',
  NOT EXISTS (SELECT 1 FROM users WHERE start_date IS DISTINCT FROM hire_date) AND (SELECT count(*) > 0 FROM users WHERE hire_date IS NOT NULL));
SELECT t_assert('O50 changing hire_date moves start_date with it (ex@o49 → today − 35)',
  (SELECT hire_date = CURRENT_DATE - 35 AND start_date = CURRENT_DATE - 35 FROM users WHERE email = 'ex@o49'));
SELECT t_expect_err('O50 writing start_date on INSERT is rejected (428C9)',
  $$INSERT INTO users (user_id, company_id, email, full_name, department, app_role, timezone, start_date)
    VALUES (gen_random_uuid(), '00000000-0000-0000-0000-0000000000c1', 'w@o50', 'W', 'O50', 'employee', 'Asia/Jerusalem', CURRENT_DATE)$$, '428C9');
SELECT t_expect_err('O50 writing start_date on UPDATE is rejected (428C9)',
  $$UPDATE users SET start_date = CURRENT_DATE - 1 WHERE email = 'tj10@o49'$$, '428C9');
SELECT t_as('00000000-0000-0000-0000-0000000e4905');
SET ROLE authenticated;
SELECT t_assert('O50 the user with no hire_date submits TPS on day one (exempt)', (SELECT questionnaire_code = 'TPS-12' FROM rpc_submit_questionnaire('TPS-12', '{3,3,3,3,3,3,3,3,3,3,3,3}')));
RESET ROLE;
SELECT t_assert('O50 untrusted rule: start_date = date portion of created_at in UTC (09-14 10:00Z → untrusted; 09-15 vs 09-14 22:30Z → trusted; 09-01 → trusted)',
  fn_start_date_untrusted(DATE '2025-09-14', TIMESTAMPTZ '2025-09-14 10:00+00')
  AND NOT fn_start_date_untrusted(DATE '2025-09-15', TIMESTAMPTZ '2025-09-14 22:30+00')
  AND NOT fn_start_date_untrusted(DATE '2025-09-01', TIMESTAMPTZ '2025-09-14 10:00+00'));
SELECT t_assert('O50 merge is a no-op once start_date is the alias', fn_users_merge_start_date() = 0);
-- simulated upgrade from 1.6.8 (start_date a plain column again), rolled back afterwards
BEGIN;
ALTER TABLE users DROP COLUMN start_date;
ALTER TABLE users ADD COLUMN start_date date;
INSERT INTO auth.users (id) VALUES ('00000000-0000-0000-0000-0000000e5001'), ('00000000-0000-0000-0000-0000000e5002'), ('00000000-0000-0000-0000-0000000e5003');
INSERT INTO users (user_id, company_id, email, full_name, department, app_role, timezone, start_date, hire_date, created_at) VALUES
  ('00000000-0000-0000-0000-0000000e5001', '00000000-0000-0000-0000-0000000000c1', 'un@o50', 'Untrusted', 'O50', 'employee', 'Asia/Jerusalem', DATE '2025-09-14', NULL, TIMESTAMPTZ '2025-09-14 10:00+00'),
  ('00000000-0000-0000-0000-0000000e5002', '00000000-0000-0000-0000-0000000000c1', 'tr@o50', 'Trusted', 'O50', 'employee', 'Asia/Jerusalem', DATE '2025-09-01', NULL, TIMESTAMPTZ '2025-09-14 10:00+00'),
  ('00000000-0000-0000-0000-0000000e5003', '00000000-0000-0000-0000-0000000000c1', 'hk@o50', 'Hire kept', 'O50', 'employee', 'Asia/Jerusalem', DATE '2025-01-01', DATE '2025-02-02', TIMESTAMPTZ '2025-09-14 10:00+00');
SELECT t_assert('O50 upgrade merge: 1 untrusted start date audited', fn_users_merge_start_date() = 1);
SELECT t_assert('O50 upgrade merge: untrusted → hire_date NULL (exempt), trusted → copied, an existing hire_date wins; start_date is the alias again',
  (SELECT string_agg(email || '=' || COALESCE(hire_date::text, 'NULL') || '/' || COALESCE(start_date::text, 'NULL'), ',' ORDER BY email) FROM users WHERE department = 'O50')
    = 'hk@o50=2025-02-02/2025-02-02,tr@o50=2025-09-01/2025-09-01,un@o50=NULL/NULL'
  AND (SELECT source = 'exempt' FROM fn_tps_wait_start('00000000-0000-0000-0000-0000000e5001'))
  AND (SELECT attgenerated = 's' FROM pg_attribute WHERE attrelid = 'users'::regclass AND attname = 'start_date'));
SELECT t_assert('O50 upgrade merge: audit start_date_untrusted (user, start_date, creation date, compared in UTC), no viewer',
  (SELECT count(*) = 1 AND bool_and(viewer_id IS NULL AND scope->>'user_id' = '00000000-0000-0000-0000-0000000e5001'
          AND scope->>'start_date' = '2025-09-14' AND scope->>'created_at_date' = '2025-09-14' AND scope->>'compared_in' = 'UTC')
     FROM access_audit_log WHERE action = 'start_date_untrusted'));
ROLLBACK;

-- ============ v1.6.6 O40. work_date range: today − 14 … today + 1 (employee-local) → else 422 ============
-- v1.6.17 run-date fix: the CHRO week-start change (R) above is scheduled from the run date, so on a Saturday
-- run today + 1 is the 1-day bridge before the new week → 422 bridge_period is then the correct answer.
CREATE TEMP TABLE t_o40 AS
  SELECT EXISTS (SELECT 1 FROM fn_company_bridge_at('00000000-0000-0000-0000-0000000000c3',
                                                     (SELECT d + 1 FROM t_today WHERE email = 'rng1@c3'))) AS bridge_next;
GRANT SELECT ON t_o40 TO authenticated;
SELECT t_as(t_x('rng1@c3'));
SET ROLE authenticated;
DO $$
BEGIN
  IF (SELECT bridge_next FROM t_o40) THEN
    PERFORM t_expect_http('O40 boundary today + 1 is a bridge day on this run date → 422 bridge_period',
      format($q$SELECT * FROM rpc_submit_workload_self_report(40, 40, 0, 1, 1, 1, %L)$q$, (SELECT d + 1 FROM t_today WHERE email = 'rng1@c3')),
      'bridge_period', 422);
  ELSE
    PERFORM t_assert('O40 boundary today + 1 accepted',
      (SELECT report_id IS NOT NULL FROM rpc_submit_workload_self_report(40, 40, 0, 1, 1, 1, (SELECT d + 1 FROM t_today WHERE email = 'rng1@c3'))));
  END IF;
END $$;
SELECT t_assert('O40 boundary today − 14 accepted',
  (SELECT report_id IS NOT NULL FROM rpc_submit_workload_self_report(40, 40, 0, 1, 1, 1, (SELECT d - 14 FROM t_today WHERE email = 'rng1@c3'))));
RESET ROLE;
SELECT t_as(t_x('rng2@c3'));
SET ROLE authenticated;
SELECT t_expect_http('O40 today + 2 rejected → 422 work_date_out_of_range',
  format($$SELECT * FROM rpc_submit_workload_self_report(40, 40, 0, 1, 1, 1, %L)$$, (SELECT d + 2 FROM t_today WHERE email = 'rng2@c3')), 'work_date_out_of_range', 422);
SELECT t_expect_http('O40 today − 15 rejected → 422 work_date_out_of_range',
  format($$SELECT * FROM rpc_submit_workload_self_report(40, 40, 0, 1, 1, 1, %L)$$, (SELECT d - 15 FROM t_today WHERE email = 'rng2@c3')), 'work_date_out_of_range', 422);
SELECT t_expect_err('O40 422 uses SQLSTATE PT422 (PostgREST status 422)',
  format($$SELECT * FROM rpc_submit_workload_self_report(40, 40, 0, 1, 1, 1, %L)$$, (SELECT d + 30 FROM t_today WHERE email = 'rng2@c3')), 'PT422');
SELECT t_assert('O40 rejected dates stored nothing', (SELECT count(*) = 0 FROM workload_self_report));
SELECT t_assert('O40 omitted work date = her local today (in range)',
  (SELECT report_id IS NOT NULL FROM rpc_submit_workload_self_report(40, 40, 0, 1)));
RESET ROLE;
SELECT t_assert('O40 range measured from the employee-local today (her timezone)',
  (SELECT work_date = fn_user_local_day(t_x('rng2@c3')) FROM workload_self_report WHERE user_id = t_x('rng2@c3')));

-- ============ v1.6.11 (Karin 24.10 + Chief of Drive 24.10): all 11 locked items ============

-- 1. (O-8) TPS-12 / IHS fractional score rounding: nearest int first, then last-digit rounding (0 or 5), then /10
-- v1.6.16: O-8 applied to the score/10 reward, which v3 §3.6 cancels → the last-digit helper stays, the reward is gone.
SELECT t_assert('v1.6.16 (supersedes O-8 reward): last-digit helper intact (67→70, 63→65, 62→60), no score/10 reward function',
  fn_round_score_last_digit(67) = 70 AND fn_round_score_last_digit(63) = 65 AND fn_round_score_last_digit(62) = 60
  AND to_regprocedure('fn_reward_score_div10(numeric)') IS NULL);

-- 2. (O-6) IHS score source & submission: 1–5 scale → (mean − 1)/4×100, reward = score/10, N>=5 team average
SELECT t_assert('v1.6.11 O-6: fn_ihs_score linear 1–5 → 0–100 (all 1→0, all 3→50, all 5→100, {4,4,5}→83.33)',
  fn_ihs_score('{1,1,1}') = 0.00
  AND fn_ihs_score('{3,3,3,3,3,3,3,3,3}') = 50.00
  AND fn_ihs_score('{5,5,5}') = 100.00
  AND fn_ihs_score('{4,4,5}') = 83.33
  AND fn_ihs_score('{0,3,3}') IS NULL
  AND fn_ihs_score('{6,3,3}') IS NULL);
SELECT t_assert('v1.6.11 O-6: IHS definition locked with scoring_method = ihs and 1–5 answer range',
  (SELECT scoring_method = 'ihs' AND answer_min = 1 AND answer_max = 5 AND all_required AND is_locked
     FROM questionnaire_definition WHERE code = 'IHS'));
SELECT t_as(t_emp('D9', 4));
SET ROLE authenticated;
SELECT t_expect_err('v1.6.11 O-6: IHS rejects answer < 1 (0)', $$SELECT rpc_submit_questionnaire('IHS', '{0,3,3}')$$, 'questionnaire_invalid_answers');
SELECT t_expect_err('v1.6.11 O-6: IHS rejects answer > 5 (6)', $$SELECT rpc_submit_questionnaire('IHS', '{3,6,3}')$$, 'questionnaire_invalid_answers');
SELECT t_expect_err('v1.6.11 O-6: IHS rejects NULL answer', $$SELECT rpc_submit_questionnaire('IHS', '{3,NULL,3}')$$, 'questionnaire_invalid_answers');
SELECT t_assert('v1.6.17: IHS submission — {4,4,5} → score 83.33, ihs_score 83.33; reward = quarterly participation 10 (Karin 31.10)',
  (SELECT score = 83.33 AND ihs_score = 83.33 AND tps_12_score IS NULL AND reward_golden_spoons = 10 AND reward_status = 'set'
     FROM rpc_submit_questionnaire('IHS', '{4,4,5}')));
SELECT t_expect_err('v1.6.11 O-6: IHS once per quarter → 409 questionnaire_already_submitted',
  $$SELECT rpc_submit_questionnaire('IHS', '{3,3,3}')$$, 'questionnaire_already_submitted');
RESET ROLE;
-- IHS team average in rpc_team_aggregate_refresh: <5 respondents → NULL; >=5 respondents → average shown
SELECT t_as('00000000-0000-0000-0000-00000000aaaa');
SET ROLE authenticated;
SELECT t_assert('v1.6.11 O-6: IHS team average suppressed (<5 respondents: 1 in D9)',
  (SELECT ihs_team_avg IS NULL AND ihs_respondent_count = 1
     FROM rpc_team_aggregate_refresh('00000000-0000-0000-0000-0000000000c1', 'D9')));
RESET ROLE;
DO $$
DECLARE i int;
BEGIN
  FOR i IN 5..8 LOOP
    PERFORM t_as(t_emp('D9', i));
    SET LOCAL ROLE authenticated;
    PERFORM rpc_submit_questionnaire('IHS', '{5,5,5}');   -- score 100
    RESET ROLE;
  END LOOP;
END $$;
SELECT t_as('00000000-0000-0000-0000-00000000aaaa');
SET ROLE authenticated;
SELECT t_assert('v1.6.11 O-6: IHS team average shown at N=5 respondents ((83.33 + 4×100)/5 = 96.67)',
  (SELECT ihs_respondent_count = 5 AND ihs_team_avg = 96.67
     FROM rpc_team_aggregate_refresh('00000000-0000-0000-0000-0000000000c1', 'D9')));
RESET ROLE;

-- 3. (O-1) Turnover replacement cost point estimate: midpoint junior 40% (0.40), mid 125% (1.25), senior 300% (3.00)
SELECT t_assert('v1.6.11 O-1: turnover_tier_config midpoints junior=40, mid=125, senior=300; helpers return 0.40 / 1.25 / 3.00',
  (SELECT string_agg(tier || ':' || midpoint_pct::int, ',' ORDER BY min_pct) FROM turnover_tier_config)
    = 'junior:40,mid:125,senior:300'
  AND fn_turnover_tier_midpoint_factor('junior') = 0.40
  AND fn_turnover_tier_midpoint_factor('mid') = 1.25
  AND fn_turnover_tier_midpoint_factor('senior') = 3.00);
SELECT t_assert('v1.6.11 O-1: employee_turnover_cost_range_v exposes midpoint_pct and turnover_cost_midpoint (D5-1 junior 40k, D5-3 mid 125k, D5-5 senior 300k)',
  (SELECT turnover_cost_midpoint = 40000 AND midpoint_pct = 40 FROM employee_turnover_cost_range_v WHERE user_id = t_emp('D5', 1))
  AND (SELECT turnover_cost_midpoint = 125000 AND midpoint_pct = 125 FROM employee_turnover_cost_range_v WHERE user_id = t_emp('D5', 3))
  AND (SELECT turnover_cost_midpoint = 300000 AND midpoint_pct = 300 FROM employee_turnover_cost_range_v WHERE user_id = t_emp('D5', 5)));
SELECT t_assert('v1.6.11 O-1: team_aggregate.turnover_cost_midpoint_sum for D5 = 2×40k + 2×125k + 300k = 630000',
  (SELECT turnover_cost_midpoint_sum = 630000 FROM team_aggregate WHERE department = 'D5' ORDER BY calculated_at DESC LIMIT 1));

-- 4. (O-2) Turnover tier assignment: automatic default from org_role.tier (1→junior, 2–3→mid, 4→senior, 5/NULL→excluded), CHRO override
SELECT t_assert('v1.6.11 O-2: fn_default_turnover_tier_for_org_tier maps 1→junior, 2→mid, 3→mid, 4→senior, 5→NULL, NULL→NULL',
  fn_default_turnover_tier_for_org_tier(1) = 'junior'
  AND fn_default_turnover_tier_for_org_tier(2) = 'mid'
  AND fn_default_turnover_tier_for_org_tier(3) = 'mid'
  AND fn_default_turnover_tier_for_org_tier(4) = 'senior'
  AND fn_default_turnover_tier_for_org_tier(5) IS NULL
  AND fn_default_turnover_tier_for_org_tier(NULL) IS NULL);
SELECT t_assert('v1.6.11 O-2: D9/D10 employees inserted without explicit turnover_tier defaulted to junior (tier 1)',
  (SELECT bool_and(turnover_tier = 'junior' AND NOT turnover_tier_override)
     FROM employee_value_asset WHERE user_id IN (t_emp('D9', 1), t_emp('D10', 1))));
-- Promoting D9-9 from employee (tier 1) → department_manager (tier 3) auto-updates non-overridden turnover_tier to mid
UPDATE users SET org_role_code = 'department_manager' WHERE user_id = t_emp('D9', 9);
SELECT t_assert('v1.6.11 O-2: role change (tier 1 → tier 3) auto-updates non-overridden turnover_tier to mid',
  (SELECT turnover_tier = 'mid' AND NOT turnover_tier_override FROM employee_value_asset WHERE user_id = t_emp('D9', 9)));
-- CHRO override on D9-9 to senior sticks even when org_role_code changes back to employee
SELECT t_as('00000000-0000-0000-0000-00000000bbbb');
SET ROLE authenticated;
SELECT rpc_upsert_employee_value_asset(t_emp('D9', 9), NULL, NULL, NULL, 'senior') IS NOT NULL AS chro_override_ok;
RESET ROLE;
UPDATE users SET org_role_code = 'employee' WHERE user_id = t_emp('D9', 9);
SELECT t_assert('v1.6.11 O-2: CHRO override (senior) is preserved across org_role_code changes',
  (SELECT turnover_tier = 'senior' AND turnover_tier_override FROM employee_value_asset WHERE user_id = t_emp('D9', 9)));
UPDATE employee_value_asset SET turnover_tier = 'junior', turnover_tier_override = false WHERE user_id = t_emp('D9', 9);
SELECT t_assert('v1.6.11 O-2: tier 5 (board_chair) and outside-tier (safety_emergency_manager) default to NULL (excluded)',
  fn_effective_turnover_tier(t_u('chair')) IS NULL
  AND fn_effective_turnover_tier(t_u('safe')) IS NULL);

-- 5 & 6. (O-3, O-4, O-18) Deprived employee rule (weekly avg spoons < 5 OR weekly B_t >= 0.65),
-- company-wide tier group avg_annual_salary, and full Shadow Balance / Happiness Debt / 12% tax / CHR Real EBITDA at N>=10
DO $$
DECLARE
  v_comp uuid := '00000000-0000-0000-0000-0000000000cb';
  v_mgr  uuid := '00000000-0000-0000-0000-00000000cb00';
  v_chro uuid := '00000000-0000-0000-0000-00000000cb01';
  v_uid  uuid;
  i      int;
BEGIN
  INSERT INTO companies (company_id, company_name, country, week_start_dow, last_workday_dow, timezone)
  VALUES (v_comp, 'ShadowCo', 'IL', 0, 4, 'Asia/Jerusalem');
  INSERT INTO auth.users (id) VALUES (v_mgr), (v_chro);
  INSERT INTO users (user_id, company_id, email, full_name, department, app_role, org_role_code, timezone, hire_date) VALUES
    (v_mgr,  v_comp, 'mgr@sb',  'SB Mgr',  'Exec', 'manager', 'direct_manager', 'Asia/Jerusalem', CURRENT_DATE - 200),
    (v_chro, v_comp, 'chro@sb', 'SB CHRO', 'Exec', 'vp_hr',   'vp',             'Asia/Jerusalem', CURRENT_DATE - 200);
  -- Create 10 employees in dept 'SB10':
  --   1..6: employee (tier 1 → junior). Only 1..4 have individual salaries (80k, 100k, 100k, 120k → company junior avg = 100,000); 5..6 have NO individual salary row!
  --   7..9: department_manager (tier 3 → mid), salaries 180k, 200k, 220k → company mid avg = 200,000
  --   10:   vp (tier 4 → senior), salary 300,000 → company senior avg = 300,000
  FOR i IN 1..10 LOOP
    v_uid := ('00000000-0000-0000-0000-00000000cb' || lpad((i + 10)::text, 2, '0'))::uuid;
    INSERT INTO auth.users (id) VALUES (v_uid);
    INSERT INTO users (user_id, company_id, reports_to, email, full_name, department, app_role, org_role_code, timezone, hire_date)
    VALUES (v_uid, v_comp, v_mgr, 'sb' || i || '@sb', 'SB ' || i, 'SB10',
            CASE WHEN i <= 6 THEN 'employee' ELSE 'manager' END,
            CASE WHEN i <= 6 THEN 'employee' WHEN i <= 9 THEN 'department_manager' ELSE 'vp' END,
            'Asia/Jerusalem', CURRENT_DATE - 100);
  END LOOP;
  INSERT INTO employee_value_asset (user_id, company_id, annual_salary) VALUES
    ('00000000-0000-0000-0000-00000000cb11', v_comp, 80000),
    ('00000000-0000-0000-0000-00000000cb12', v_comp, 100000),
    ('00000000-0000-0000-0000-00000000cb13', v_comp, 100000),
    ('00000000-0000-0000-0000-00000000cb14', v_comp, 120000),
    -- cb15 and cb16 have NO salary record (tests missing individual salary handling via company tier average!)
    ('00000000-0000-0000-0000-00000000cb17', v_comp, 180000),
    ('00000000-0000-0000-0000-00000000cb18', v_comp, 200000),
    ('00000000-0000-0000-0000-00000000cb19', v_comp, 220000),
    ('00000000-0000-0000-0000-00000000cb20', v_comp, 300000);
END $$;

SELECT t_assert('v1.6.11 O-4: fn_company_tier_avg_salary returns company-wide tier averages (junior 100k, mid 200k, senior 300k)',
  fn_company_tier_avg_salary('00000000-0000-0000-0000-0000000000cb', 'junior') = 100000.00
  AND fn_company_tier_avg_salary('00000000-0000-0000-0000-0000000000cb', 'mid') = 200000.00
  AND fn_company_tier_avg_salary('00000000-0000-0000-0000-0000000000cb', 'senior') = 300000.00);

-- With only 8 salary contributors and 0 spoon/workload reports in SB10, N=8 < 10 → 403
SELECT t_as('00000000-0000-0000-0000-00000000cb00');
SET ROLE authenticated;
SELECT t_expect_err('v1.6.11 O-18: Shadow Balance with 8 contributors (<10) → 403',
  $$SELECT rpc_shadow_balance_refresh('00000000-0000-0000-0000-0000000000cb', 'SB10', 10000000)$$, 'aggregation_privacy_threshold');
RESET ROLE;

-- v1.6.16 (v3 §6.2): deprived needs TWO consecutive weeks → previous-week data for cb15 (spoons 4) and cb18 (B_t 1.00).
INSERT INTO spoon_budget (user_id, budget_date, current_spoon_count, reported_at)
VALUES ('00000000-0000-0000-0000-00000000cb15',
        fn_local_week_start('00000000-0000-0000-0000-00000000cb15') - 7, 4, clock_timestamp() - interval '7 days');
SELECT t_as('00000000-0000-0000-0000-00000000cb18');
SET ROLE authenticated;
SELECT rpc_submit_workload_self_report(40, 50, 10, 2, 5, 5, CURRENT_DATE - 7) IS NOT NULL AS cb18_prev_week_ok;
RESET ROLE;
SELECT t_assert('v1.6.16: one deprived week alone is not enough (cb15 has only last week so far → not deprived)',
  NOT fn_is_employee_deprived('00000000-0000-0000-0000-00000000cb15'));
-- Now cb15 (junior, no salary row) reports morning check-in with high distress → 8 spoons, then midday or task brings avg spoons to 4 (<5) → deprived!
SELECT fn_ensure_local_spoon_budget('00000000-0000-0000-0000-00000000cb15');
UPDATE spoon_budget SET current_spoon_count = 4, reported_at = clock_timestamp()
 WHERE user_id = '00000000-0000-0000-0000-00000000cb15' AND budget_date = fn_user_local_date('00000000-0000-0000-0000-00000000cb15');
-- cb16 (junior, no salary row) reports healthy spoons = 9 (>=5) and low B_t → NOT deprived, but is the 10th contributor!
SELECT t_as('00000000-0000-0000-0000-00000000cb16');
SET ROLE authenticated;
SELECT rpc_morning_checkin('{2, 2, 2}') IS NOT NULL AS cb16_morning_ok;
SELECT rpc_submit_workload_self_report(40, 40, 0, 1, 1, 1) IS NOT NULL AS cb16_wl_ok;
RESET ROLE;
-- cb18 (mid, tier avg 200k) reports healthy spoons = 10, but submits workload self-report with B_t >= 0.65 (stress 5, overtime 10, drop 5 → B_t = 1.00) → deprived!
SELECT t_as('00000000-0000-0000-0000-00000000cb18');
SET ROLE authenticated;
SELECT rpc_morning_checkin('{1, 1, 1}') IS NOT NULL AS cb18_morning_ok;
SELECT rpc_submit_workload_self_report(40, 50, 10, 2, 5, 5) IS NOT NULL AS cb18_wl_ok;
RESET ROLE;

SELECT t_assert('v1.6.16 O-3 + v3: cb15 (avg spoons 4 < 5) and cb18 (B_t 1.00 >= 0.65) deprived two consecutive weeks; cb16 (spoons 12, B_t 0) is not deprived',
  fn_is_employee_deprived('00000000-0000-0000-0000-00000000cb15')
  AND fn_is_employee_deprived('00000000-0000-0000-0000-00000000cb18')
  AND NOT fn_is_employee_deprived('00000000-0000-0000-0000-00000000cb16')
  AND (SELECT is_deprived AND happiness_debt_liability = 250000 FROM employee_value_asset WHERE user_id = '00000000-0000-0000-0000-00000000cb18'));

-- Now SB10 has N=10 contributors (8 salary + cb15 spoon report + cb16 spoon/workload report).
-- Deprived in SB10:
--   * cb15 (junior, no individual salary → uses company junior avg 100,000):
--       tax = 100,000 × 0.12 = 12,000; happiness_debt = 100,000 × 0.40 = 40,000
--   * cb18 (mid, individual salary 200k, uses company mid avg 200,000):
--       tax = 200,000 × 0.12 = 24,000; happiness_debt = 200,000 × 1.25 = 250,000
-- Total: deprived_count = 2; deprivation_tax_amount = 36,000; happiness_debt_sum = happiness_debt_balance = 290,000;
--        shadow_balance_sum = 326,000; with GAAP EBITDA = 10,000,000 → chr_real_ebitda = 10,000,000 − 290,000 − 36,000 = 9,674,000!
SELECT t_as('00000000-0000-0000-0000-00000000cb00');
SET ROLE authenticated;
SELECT t_assert('v1.6.11 O-4 & O-18: rpc_shadow_balance_refresh at N=10 computes Happiness Debt (290k), 12% tax (36k), Shadow Balance (326k), CHR Real EBITDA (9,674,000)',
  (SELECT contributor_count = 10
          AND deprived_count = 2
          AND deprivation_tax_amount = 36000.00
          AND happiness_debt_sum = 290000.00
          AND happiness_debt_balance = 290000.00
          AND shadow_balance_sum = 326000.00
          AND gaap_reported_ebitda = 10000000.00
          AND chr_real_ebitda = 9674000.00
     FROM rpc_shadow_balance_refresh('00000000-0000-0000-0000-0000000000cb', 'SB10', 10000000)));
RESET ROLE;

-- ============ v1.6.20-r2 (J-102 = A): a REAL team named 'General' never grows by default-department employees ============
-- Company J102S: a small real 'General' team (4 employees, department given explicitly → marker false) and 6
-- employees with NO department (marker true). All have salary rows and report spoons today.
-- Company J102T: a real 'General' team of 10 (2 flagged deprived) and 5 defaulted employees (all flagged deprived).
DO $$
DECLARE
  v_s uuid := md5('j102-small')::uuid;
  v_t uuid := md5('j102-tax')::uuid;
  v_uid uuid;
  i int;
BEGIN
  INSERT INTO companies (company_id, company_name, country, week_start_dow, last_workday_dow, timezone) VALUES
    (v_s, 'J102 Small', 'IL', 0, 4, 'Asia/Jerusalem'), (v_t, 'J102 Tax', 'IL', 0, 4, 'Asia/Jerusalem');
  INSERT INTO auth.users (id) VALUES (md5('j102-mgr-s')::uuid), (md5('j102-mgr-t')::uuid);
  INSERT INTO users (user_id, company_id, email, full_name, department, app_role, org_role_code, timezone, hire_date) VALUES
    (md5('j102-mgr-s')::uuid, v_s, 'mgr@j102s', 'J102 S Mgr', 'Exec', 'manager', 'direct_manager', 'Asia/Jerusalem', CURRENT_DATE - 200),
    (md5('j102-mgr-t')::uuid, v_t, 'mgr@j102t', 'J102 T Mgr', 'Exec', 'manager', 'direct_manager', 'Asia/Jerusalem', CURRENT_DATE - 200);
  FOR i IN 1..10 LOOP
    v_uid := md5('j102-s-' || i)::uuid;
    INSERT INTO auth.users (id) VALUES (v_uid);
    INSERT INTO users (user_id, company_id, reports_to, email, full_name, department, app_role, org_role_code, timezone, hire_date)
    VALUES (v_uid, v_s, md5('j102-mgr-s')::uuid, 's' || i || '@j102s', 'J102 S ' || i,
            CASE WHEN i <= 4 THEN 'General' END,  -- 1..4 real 'General'; 5..10 no department → default marker
            'employee', 'employee', 'Asia/Jerusalem', CURRENT_DATE - 100);
    INSERT INTO employee_value_asset (user_id, company_id, annual_salary) VALUES (v_uid, v_s, 100000);
  END LOOP;
  FOR i IN 1..15 LOOP
    v_uid := md5('j102-t-' || i)::uuid;
    INSERT INTO auth.users (id) VALUES (v_uid);
    INSERT INTO users (user_id, company_id, reports_to, email, full_name, department, app_role, org_role_code, timezone, hire_date)
    VALUES (v_uid, v_t, md5('j102-mgr-t')::uuid, 't' || i || '@j102t', 'J102 T ' || i,
            CASE WHEN i <= 10 THEN 'General' END, -- 1..10 real 'General'; 11..15 defaulted
            'employee', 'employee', 'Asia/Jerusalem', CURRENT_DATE - 100);
    INSERT INTO employee_value_asset (user_id, company_id, annual_salary, is_deprived)
    VALUES (v_uid, v_t, 100000, i IN (1, 2) OR i > 10);
  END LOOP;
END $$;
SELECT fn_ensure_local_spoon_budget(md5('j102-s-' || i)::uuid) IS NOT NULL FROM generate_series(1, 10) i;
UPDATE spoon_budget sb SET current_spoon_count = 2, reported_at = clock_timestamp()
  FROM users u WHERE u.user_id = sb.user_id AND u.company_id = md5('j102-small')::uuid;

SELECT t_assert('J-102 setup: 4 real General (marker false) + 6 defaulted (label General, marker true) in J102 Small',
  (SELECT count(*) FILTER (WHERE NOT department_is_default) = 4 AND count(*) FILTER (WHERE department_is_default) = 6
          AND bool_and(department = 'General')
     FROM users WHERE company_id = md5('j102-small')::uuid AND app_role = 'employee'));
SELECT t_assert('J-102: contributors / spoon reporters of the real General = 4 (defaulted employees not counted)',
  fn_team_aggregate_contributors(md5('j102-small')::uuid, 'General') = 4
  AND (SELECT reporters FROM fn_team_spoon_reports(md5('j102-small')::uuid, 'General')) = 4
  AND fn_shadow_balance_contributors(md5('j102-small')::uuid, 'General') = 4);
SELECT t_as(md5('j102-mgr-s')::uuid);
SET ROLE authenticated;
SELECT t_expect_err('J-102: spoon alert, real General with 4 reporters + 6 defaulted reporters → stays suppressed (403, N<5)',
  $$SELECT * FROM rpc_team_spoon_alert(md5('j102-small')::uuid, 'General')$$, 'aggregation_privacy_threshold');
SELECT t_expect_err('J-102: team מס קיפוח refresh, real General 4 + 6 defaulted → stays suppressed (403, N<5)',
  $$SELECT * FROM rpc_team_aggregate_refresh(md5('j102-small')::uuid, 'General')$$, 'aggregation_privacy_threshold');
SELECT t_expect_err('J-102: Shadow Balance / Happiness Debt (N≥10), real General 4 + 6 defaulted → stays suppressed (403)',
  $$SELECT * FROM rpc_shadow_balance_refresh(md5('j102-small')::uuid, 'General', NULL)$$, 'aggregation_privacy_threshold');
SELECT t_expect_err('J-102: the default group has no team view either ("ללא מחלקה" → 403)',
  $$SELECT * FROM rpc_team_spoon_alert(md5('j102-small')::uuid, 'ללא מחלקה')$$, 'aggregation_privacy_threshold');
RESET ROLE;
SELECT t_assert('J-102: the three team RPCs have no default department input any more (p_department required)',
  (SELECT bool_and(pronargdefaults = CASE WHEN proname = 'rpc_shadow_balance_refresh' THEN 1 ELSE 0 END)
     FROM pg_proc WHERE proname IN ('rpc_team_spoon_alert', 'rpc_team_aggregate_refresh', 'rpc_shadow_balance_refresh'))
  AND NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname IN ('rpc_team_spoon_alert', 'rpc_team_aggregate_refresh', 'rpc_shadow_balance_refresh')
                     AND pg_get_function_arguments(oid) ILIKE '%General%'));

-- Burnout tax / Happiness Debt of a real General team (10) exclude the 5 defaulted (all flagged deprived).
SELECT t_as(md5('j102-mgr-t')::uuid);
SET ROLE authenticated;
SELECT t_assert('J-102: team מס קיפוח refresh of the real General — 10 contributors, 2 deprived (5 defaulted deprived excluded)',
  (SELECT contributor_count = 10 AND deprived_count = 2 FROM rpc_team_aggregate_refresh(md5('j102-tax')::uuid, 'General')));
SELECT t_assert('J-102: Happiness Debt refresh of the real General — N=10, 2 deprived (5 defaulted deprived excluded)',
  (SELECT contributor_count = 10 AND deprived_count = 2 FROM rpc_shadow_balance_refresh(md5('j102-tax')::uuid, 'General', NULL)));
RESET ROLE;
SELECT t_assert('J-102: stored tax = 2 × tier salary × factor and debt = 2 × tier salary × midpoint (defaulted excluded)',
  (SELECT t.deprivation_tax_amount = round(2 * fn_company_tier_avg_salary(md5('j102-tax')::uuid, 'junior') * fn_chr_productivity_factor(), 2)
     FROM team_aggregate t WHERE t.org_id = md5('j102-tax')::uuid AND t.department = 'General' ORDER BY t.calculated_at DESC LIMIT 1)
  AND (SELECT s.happiness_debt_balance = round(2 * fn_company_tier_avg_salary(md5('j102-tax')::uuid, 'junior')
                                              * fn_turnover_tier_midpoint_factor('junior'), 2)
     FROM shadow_balance_aggregate s WHERE s.org_id = md5('j102-tax')::uuid AND s.department = 'General' ORDER BY s.calculated_at DESC LIMIT 1));
SELECT t_assert('J-102: the burnout-agent tax/debt terms read the same team rows (defaulted excluded)',
  (SELECT d.deprivation_tax = round(2 * fn_company_tier_avg_salary(md5('j102-tax')::uuid, 'junior') * fn_chr_productivity_factor(), 2)
          AND d.happiness_debt = round(2 * fn_company_tier_avg_salary(md5('j102-tax')::uuid, 'junior')
                                       * fn_turnover_tier_midpoint_factor('junior'), 2)
     FROM fn_team_month_tax_debt(md5('j102-tax')::uuid, 'General', date_trunc('month', (clock_timestamp() AT TIME ZONE 'Asia/Jerusalem'))::date) d));

-- ============ v1.6.21 J-115 = A (Karin 31.10): employees without a department ARE in the company מס קיפוח /
-- Happiness Debt total and in CHR Real EBITDA (same total); never a row of their own; differencing guard N ≥ 10 ============
-- J115A: real team 'Ops' (10, 1 flagged deprived) + 3 defaulted (2 flagged deprived) → remainder 3 → suppressed.
-- J115B: real team 'Ops' (10, 1 flagged deprived) + 12 defaulted (2 flagged deprived) → included and shown.
DO $$
DECLARE
  v_c uuid; v_uid uuid; i int; k text; v_nd int;
BEGIN
  FOREACH k IN ARRAY ARRAY['a', 'b'] LOOP
    v_c := md5('j115-' || k)::uuid;
    v_nd := CASE k WHEN 'a' THEN 3 ELSE 12 END;
    INSERT INTO companies (company_id, company_name, country, week_start_dow, last_workday_dow, timezone)
    VALUES (v_c, 'J115 ' || k, 'IL', 0, 4, 'Asia/Jerusalem');
    INSERT INTO auth.users (id) VALUES (md5('j115-mgr-' || k)::uuid), (md5('j115-chair-' || k)::uuid);
    INSERT INTO users (user_id, company_id, email, full_name, department, app_role, org_role_code, timezone, hire_date, has_employee_profile) VALUES
      (md5('j115-mgr-' || k)::uuid, v_c, 'mgr@j115' || k, 'J115 Mgr ' || k, 'Exec', 'manager', 'direct_manager', 'Asia/Jerusalem', CURRENT_DATE - 200, true),
      (md5('j115-chair-' || k)::uuid, v_c, 'chair@j115' || k, 'J115 Chair ' || k, 'Board', 'board_chair', 'board_chair', 'Asia/Jerusalem', CURRENT_DATE - 200, false);
    FOR i IN 1..(10 + v_nd) LOOP
      v_uid := md5('j115-' || k || '-' || i)::uuid;
      INSERT INTO auth.users (id) VALUES (v_uid);
      INSERT INTO users (user_id, company_id, reports_to, email, full_name, department, app_role, org_role_code, timezone, hire_date)
      VALUES (v_uid, v_c, md5('j115-mgr-' || k)::uuid, k || i || '@j115', 'J115 ' || k || ' ' || i,
              CASE WHEN i <= 10 THEN 'Ops' END, 'employee', 'employee', 'Asia/Jerusalem', CURRENT_DATE - 100);
      INSERT INTO employee_value_asset (user_id, company_id, annual_salary, is_deprived)
      VALUES (v_uid, v_c, 100000, i IN (1, 11, 12));   -- Ops: 1 deprived; no-department group: 2 deprived
    END LOOP;
  END LOOP;
END $$;
SELECT t_as(md5('j115-mgr-a')::uuid);
SET ROLE authenticated;
SELECT (rpc_shadow_balance_refresh(md5('j115-a')::uuid, 'Ops', NULL)).contributor_count AS j115a_ops_n;
RESET ROLE;
SELECT t_as(md5('j115-mgr-b')::uuid);
SET ROLE authenticated;
SELECT (rpc_shadow_balance_refresh(md5('j115-b')::uuid, 'Ops', NULL)).contributor_count AS j115b_ops_n;
RESET ROLE;
CREATE TEMP TABLE t_j115 AS
SELECT k, md5('j115-' || k)::uuid AS c, date_trunc('month', (clock_timestamp() AT TIME ZONE 'Asia/Jerusalem'))::date AS m,
       fn_company_tier_avg_salary(md5('j115-' || k)::uuid, 'junior') AS sal
  FROM unnest(ARRAY['a', 'b']) k;
SELECT t_assert('J-115 = A: the team refresh also takes the no-department share (A: 3 employees, B: 12), stored outside any team row',
  (SELECT employee_count = 3 AND deprived_count = 2 FROM shadow_balance_no_department WHERE company_id = md5('j115-a')::uuid)
  AND (SELECT employee_count = 12 AND deprived_count = 2 FROM shadow_balance_no_department WHERE company_id = md5('j115-b')::uuid)
  AND NOT EXISTS (SELECT 1 FROM shadow_balance_aggregate WHERE org_id IN (md5('j115-a')::uuid, md5('j115-b')::uuid) AND department <> 'Ops'));
SELECT t_assert('J-115 = A (2): group of 12 — the company total = the Ops row + the no-department share (3 deprived in all), shown',
  (SELECT d.happiness_debt_balance = round(3 * x.sal * fn_turnover_tier_midpoint_factor('junior'), 2)
          AND d.deprivation_tax = round(3 * x.sal * fn_chr_productivity_factor(), 2)
          AND NOT fn_company_shadow_suppressed(x.c, x.m)
     FROM t_j115 x, fn_company_month_shadow(x.c, x.m) d WHERE x.k = 'b'));
SELECT t_assert('J-115 = A (1): group of 3 — total − the Ops row would reveal them → the company total is suppressed',
  (SELECT fn_company_month_shadow_remainder(x.c, x.m) = 3 AND fn_company_shadow_suppressed(x.c, x.m) FROM t_j115 x WHERE x.k = 'a'));
-- Finance inputs (first period), with the 4-line split equal to each company's system total.
SELECT period_month FROM t_j115 x, rpc_put_board_reconciliation(x.c, x.m, 1000000, 400000, true);
SELECT jsonb_array_length(rpc_put_happiness_debt_split(x.c, x.m, d.happiness_debt_balance - 3 * round(d.happiness_debt_balance / 4, 2),
         round(d.happiness_debt_balance / 4, 2), round(d.happiness_debt_balance / 4, 2), round(d.happiness_debt_balance / 4, 2))) AS split_lines
  FROM t_j115 x, fn_company_month_shadow(x.c, x.m) d;
CREATE TEMP TABLE t_j115_rep AS SELECT x.k, rpc_build_board_report(x.c, x.m) AS j FROM t_j115 x;
SELECT t_assert('J-115 = A (1): group of 3 — the board report shows "אין מספיק נתונים להצגה בתקופה זו" instead of the company total, CHR Real EBITDA, the debt lines and מס קיפוח',
  (SELECT j->>'company_total_display_he' = 'אין מספיק נתונים להצגה בתקופה זו'
          AND j->'chr_real_ebitda'->>'value' IS NULL
          AND j->'chr_real_ebitda'->>'display_he' = 'אין מספיק נתונים להצגה בתקופה זו'
          AND j->'happiness_debt_balance' = 'null'::jsonb AND j->'shadow_balance' = 'null'::jsonb
          AND j->'deprivation_tax'->>'stored_amount' IS NULL
          AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(j->'reconciliation') r
                           WHERE r->>'line' <> 'gaap_ebitda' AND r->'current' <> 'null'::jsonb)
     FROM t_j115_rep WHERE k = 'a'));
SELECT t_assert('J-115 = A (3): group of 12 — CHR Real EBITDA uses the SAME total: GAAP − company Happiness Debt − company מס קיפוח',
  (SELECT (r.j->'chr_real_ebitda'->>'value')::numeric = fn_chr_real_ebitda(1000000, d.happiness_debt_balance, d.deprivation_tax)
          AND (r.j->>'happiness_debt_balance')::numeric = d.happiness_debt_balance
          AND (r.j->'deprivation_tax'->>'stored_amount')::numeric = d.deprivation_tax
          AND NOT r.j ? 'company_total_display_he'
     FROM t_j115_rep r, t_j115 x, fn_company_month_shadow(x.c, x.m) d WHERE r.k = 'b' AND x.k = 'b'));
SELECT t_as(md5('j115-chair-a')::uuid);
SET ROLE authenticated;
CREATE TEMP TABLE t_j115_macro_a AS SELECT * FROM rpc_get_board_macro_metrics(1000000);
RESET ROLE;
SELECT t_as(md5('j115-chair-b')::uuid);
SET ROLE authenticated;
CREATE TEMP TABLE t_j115_macro_b AS SELECT * FROM rpc_get_board_macro_metrics(1000000);
RESET ROLE;
SELECT t_assert('J-115 = A (1): group of 3 — the governance macro figures give no Happiness Debt, מס קיפוח, Shadow Balance or CHR Real EBITDA',
  (SELECT shadow_contributor_count >= 10 AND happiness_debt_balance IS NULL AND deprivation_tax_amount IS NULL
          AND shadow_balance_sum IS NULL AND chr_real_ebitda IS NULL FROM t_j115_macro_a));
SELECT t_assert('J-115 = A (3): group of 12 — the governance macro figures carry the same company total and the same CHR Real EBITDA as the board report',
  (SELECT m.happiness_debt_balance = d.happiness_debt_balance AND m.deprivation_tax_amount = d.deprivation_tax
          AND m.chr_real_ebitda = (r.j->'chr_real_ebitda'->>'value')::numeric
     FROM t_j115_macro_b m, t_j115_rep r, t_j115 x, fn_company_month_shadow(x.c, x.m) d WHERE r.k = 'b' AND x.k = 'b'));
SELECT t_assert('J-115 = A: no "ללא מחלקה" row ever appears — not in the board reports, not in the team rows, not in the macro figures; the share table is closed to clients',
  NOT EXISTS (SELECT 1 FROM t_j115_rep WHERE j::text LIKE '%ללא מחלקה%')
  AND NOT EXISTS (SELECT 1 FROM shadow_balance_aggregate WHERE fn_is_no_department(department))
  AND NOT EXISTS (SELECT 1 FROM t_j115_macro_a m WHERE row_to_json(m)::text LIKE '%ללא מחלקה%')
  AND NOT has_table_privilege('authenticated', 'shadow_balance_no_department', 'SELECT')
  AND (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid = 'shadow_balance_no_department'::regclass)
  AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'shadow_balance_no_department'
                     AND column_name ~* '(person|user|employee_id|pseudonym|department$)'));

-- ============ v1.6.21 J-112 = A (Karin 31.10): Cuckoo for employees without a department — company level, N ≥ 10 ============
DO $$
DECLARE v_c uuid := md5('j112')::uuid; v_uid uuid; i int;
BEGIN
  INSERT INTO companies (company_id, company_name, country, week_start_dow, last_workday_dow, timezone)
  VALUES (v_c, 'J112 Co', 'IL', 0, 4, 'Asia/Jerusalem');
  INSERT INTO auth.users (id) VALUES (md5('j112-mgr')::uuid);
  INSERT INTO users (user_id, company_id, email, full_name, department, app_role, org_role_code, timezone, hire_date)
  VALUES (md5('j112-mgr')::uuid, v_c, 'mgr@j112', 'J112 Mgr', 'Exec', 'manager', 'direct_manager', 'Asia/Jerusalem', CURRENT_DATE - 200);
  FOR i IN 1..13 LOOP   -- 1..10 no department (marker); 11..13 real team 'Ops'
    v_uid := md5('j112-' || i)::uuid;
    INSERT INTO auth.users (id) VALUES (v_uid);
    INSERT INTO users (user_id, company_id, reports_to, email, full_name, department, app_role, org_role_code, timezone, hire_date)
    VALUES (v_uid, v_c, md5('j112-mgr')::uuid, 'e' || i || '@j112', 'J112 ' || i, CASE WHEN i > 10 THEN 'Ops' END,
            'employee', 'employee', 'Asia/Jerusalem', CURRENT_DATE - 100);
  END LOOP;
END $$;
SELECT fn_ensure_local_spoon_budget(md5('j112-' || i)::uuid) IS NOT NULL FROM generate_series(1, 13) i;
UPDATE spoon_budget sb SET reported_at = clock_timestamp()
  FROM users u WHERE u.user_id = sb.user_id AND u.company_id = md5('j112')::uuid AND u.email <> 'e10@j112';
SELECT t_assert('J-112 = A: 9 no-department reporters at company level; they count in no team ("General" / "ללא מחלקה" = 0)',
  fn_cuckoo_no_department_reporters(md5('j112')::uuid) = 9
  AND fn_cuckoo_recent_reporters(md5('j112')::uuid, 'General') = 0
  AND fn_cuckoo_recent_reporters(md5('j112')::uuid, 'ללא מחלקה') = 0);
SELECT t_expect_err('J-112 = A: group of 9 → no company-level Cuckoo (403)',
  format($$SELECT fn_cuckoo_raise(%L, 'nlp_distress')$$, md5('j112-1')::uuid), 'aggregation_privacy_threshold');
UPDATE spoon_budget sb SET reported_at = clock_timestamp()
  FROM users u WHERE u.user_id = sb.user_id AND u.email = 'e10@j112';
CREATE TEMP TABLE t_j112 AS SELECT * FROM fn_cuckoo_raise(md5('j112-1')::uuid, 'nlp_distress');
SELECT t_assert('J-112 = A: group of 10 reporters → the company-level Cuckoo signal is raised, with no team on it (department empty)',
  (SELECT count(*) = 1 AND bool_and(department IS NULL AND status = 'VETO_WINDOW_ACTIVE') FROM t_j112));
SELECT t_expect_err('J-112 = A: differencing safe — a real team of 3 reporters is still refused (the company group never lifts a team)',
  format($$SELECT fn_cuckoo_raise(%L, 'nlp_distress')$$, md5('j112-11')::uuid), 'aggregation_privacy_threshold');
UPDATE cuckoo_alert SET sovereign_veto_window_expiry = clock_timestamp() - interval '1 second' WHERE alert_id = (SELECT alert_id FROM t_j112);
SELECT t_as(md5('j112-mgr')::uuid);
SET ROLE authenticated;
SELECT t_assert('J-112 = A: the manager sees the pseudonym only — no team, no count, no "ללא מחלקה", no user id',
  (SELECT count(*) = 1 AND bool_and(row_to_json(v)::text NOT LIKE '%ללא מחלקה%' AND row_to_json(v)::text NOT LIKE '%' || md5('j112-1')::uuid::text || '%')
     FROM cuckoo_alert_manager_v v));
RESET ROLE;

-- 7. (O-5) Morning & midday check-in RPCs
SELECT t_assert('v1.6.11 O-5: morning half-point scores floored in employee favor (4.5→0 deducted, 5.0→2, 5.5→2, 6.0→3, 7.5→3, 8.0→4)',
  fn_morning_spoon_deduction(fn_morning_checkin_score('{4, 5}')) = 0
  AND fn_morning_spoon_deduction(fn_morning_checkin_score('{5, 5}')) = 2
  AND fn_morning_spoon_deduction(fn_morning_checkin_score('{5, 6}')) = 2
  AND fn_morning_spoon_deduction(fn_morning_checkin_score('{6, 6}')) = 3
  AND fn_morning_spoon_deduction(fn_morning_checkin_score('{7, 8}')) = 3
  AND fn_morning_spoon_deduction(fn_morning_checkin_score('{8, 8}')) = 4);
SELECT t_expect_err('v1.6.11 O-5: morning check-in rejects out-of-range scale (11)',
  $$SELECT fn_morning_checkin_score('{4, 11}')$$, 'checkin_invalid_scales');
SELECT t_expect_err('v1.6.11 O-5: morning check-in rejects empty scales',
  $$SELECT fn_morning_checkin_score('{}')$$, 'checkin_invalid_scales');
-- Test morning check-in RPC on cb11: {4, 5} → avg 4.5 → 0 deducted → 12 spoons, reported_at set, +2.0 shift golden spoons
SELECT t_as('00000000-0000-0000-0000-00000000cb11');
SET ROLE authenticated;
SELECT t_assert('v1.6.11 O-5: rpc_morning_checkin({4, 5}) → 12 spoons (4.5 rounded in employee favor), reported_at set, shift_golden_awarded true',
  (SELECT current_spoon_count = 12 AND reported_at IS NOT NULL AND shift_golden_awarded
     FROM rpc_morning_checkin('{4, 5}')));
SELECT t_assert('v1.6.11 O-5: rpc_morning_checkin({6, 7, 8}) → avg 7.0 → 9 spoons (3 deducted)',
  (SELECT current_spoon_count = 9 FROM rpc_morning_checkin('{6, 7, 8}')));
SELECT t_assert('v1.6.11 O-16: shift golden spoons (+2.0) credited once and not double-credited on same day',
  (SELECT golden_spoons = 2.0 AND chr_coins = 0 FROM avatar_state WHERE user_id = '00000000-0000-0000-0000-00000000cb11'));
RESET ROLE;

-- Midday check-in window & delta tests
SELECT t_assert('v1.6.11 O-5: fn_is_midday_window true in 12:00..15:00 inclusive, false at 11:59:59 and 15:00:01',
  fn_is_midday_window(TIME '12:00:00')
  AND fn_is_midday_window(TIME '13:30:00')
  AND fn_is_midday_window(TIME '15:00:00')
  AND NOT fn_is_midday_window(TIME '11:59:59')
  AND NOT fn_is_midday_window(TIME '15:00:01'));
-- Set cb11's timezone to an IANA zone currently outside 12:00–15:00 → 403 midday_checkin_outside_window
UPDATE users SET timezone = (
  SELECT name FROM pg_timezone_names
   WHERE name LIKE 'Etc/GMT%'
     AND NOT ((clock_timestamp() AT TIME ZONE name)::time BETWEEN TIME '11:50' AND TIME '15:10')
   ORDER BY name LIMIT 1
) WHERE user_id = '00000000-0000-0000-0000-00000000cb11';
SELECT t_as('00000000-0000-0000-0000-00000000cb11');
SET ROLE authenticated;
SELECT t_expect_err('v1.6.11 O-5: rpc_midday_checkin outside 12:00–15:00 employee-local → 403 midday_checkin_outside_window',
  $$SELECT rpc_midday_checkin(2)$$, 'midday_checkin_outside_window');
RESET ROLE;
-- Set cb11's timezone to an IANA zone currently inside 12:00–15:00 and ensure local day row with 9 spoons
UPDATE users SET timezone = (
  SELECT name FROM pg_timezone_names
   WHERE name LIKE 'Etc/GMT%'
     AND ((clock_timestamp() AT TIME ZONE name)::time BETWEEN TIME '12:05' AND TIME '14:55')
   ORDER BY name LIMIT 1
) WHERE user_id = '00000000-0000-0000-0000-00000000cb11';
SELECT fn_ensure_local_spoon_budget('00000000-0000-0000-0000-00000000cb11');
UPDATE spoon_budget SET current_spoon_count = 9, reported_at = clock_timestamp()
 WHERE user_id = '00000000-0000-0000-0000-00000000cb11'
   AND budget_date = fn_user_local_date('00000000-0000-0000-0000-00000000cb11');
SELECT t_as('00000000-0000-0000-0000-00000000cb11');
SET ROLE authenticated;
SELECT t_expect_err('v1.6.11 O-5: rpc_midday_checkin rejects delta > +4 (+5)', $$SELECT rpc_midday_checkin(5)$$, 'checkin_invalid_delta');
SELECT t_expect_err('v1.6.11 O-5: rpc_midday_checkin rejects delta < -4 (-5)', $$SELECT rpc_midday_checkin(-5)$$, 'checkin_invalid_delta');
SELECT t_assert('v1.6.11 O-5: rpc_midday_checkin(+4) from 9 caps at 12 daily max without recalculating morning score',
  (SELECT current_spoon_count = 12 AND day_status = 'OPEN' FROM rpc_midday_checkin(4)));
SELECT t_assert('v1.6.11 O-5: rpc_midday_checkin(-4) from 12 → 8 spoons',
  (SELECT current_spoon_count = 8 FROM rpc_midday_checkin(-4)));
SELECT t_assert('v1.6.11 O-5: rpc_midday_checkin(-4) from 8 → 4 spoons (FIGHTING_BLOCKED)',
  (SELECT current_spoon_count = 4 AND day_status = 'FIGHTING_BLOCKED' FROM rpc_midday_checkin(-4)));
SELECT t_assert('v1.6.11 O-5: rpc_midday_checkin(-4) from 4 floors at 0 (GO_HOME)',
  (SELECT current_spoon_count = 0 AND day_status = 'GO_HOME' FROM rpc_midday_checkin(-4)));
SELECT t_assert('v1.6.11 O-5: …and logs early leave automatically when midday check-in reaches <= 3',
  EXISTS (SELECT 1 FROM early_leave_log WHERE user_id = '00000000-0000-0000-0000-00000000cb11'));
RESET ROLE;
UPDATE users SET timezone = 'Asia/Jerusalem' WHERE user_id = '00000000-0000-0000-0000-00000000cb11';

-- 8 & 9. (Q5 & O-16 / Q11) Task costs (0, 1, 2) and golden spoon rewards visible; 10 golden spoons at signup, 2 per shift, 0.5 daily; CHR Coins v2
INSERT INTO auth.users (id) VALUES ('00000000-0000-0000-0000-00000000cb99');
SELECT t_as('00000000-0000-0000-0000-00000000cb99');
SET ROLE authenticated;
SELECT user_id IS NOT NULL AS signup_1_ok
  FROM rpc_signup_profile('new@sb', 'New Signup', 'Asia/Jerusalem', 'IL', '00000000-0000-0000-0000-0000000000cb', 'SB10', 'employee');
SELECT t_assert('v1.6.11 O-16: rpc_signup_profile grants 10.0 golden spoons at initial signup and 0 CHR Coins',
  (SELECT golden_spoons = 10.0 AND chr_coins = 0 FROM avatar_state WHERE user_id = '00000000-0000-0000-0000-00000000cb99'));
SELECT user_id IS NOT NULL AS signup_2_ok
  FROM rpc_signup_profile('new@sb', 'New Signup', 'Asia/Jerusalem', 'IL', '00000000-0000-0000-0000-0000000000cb', 'SB10', 'employee');
SELECT t_assert('v1.6.11 O-16: re-calling rpc_signup_profile does not double-grant the 10 signup golden spoons',
  (SELECT golden_spoons = 10.0 AND chr_coins = 0 FROM avatar_state WHERE user_id = '00000000-0000-0000-0000-00000000cb99'));
SELECT current_spoon_count = 12 AS morning_ok FROM rpc_morning_checkin('{2, 3}');
SELECT reward_golden_spoons = 2 AS mood_ok FROM rpc_submit_questionnaire('MOOD', '{4}');
SELECT t_assert('v1.6.16: morning check-in adds golden_spoons_per_shift 2.0 (10 + 2 = 12.0) and the daily MOOD questionnaire adds golden_spoons_per_short_questionnaire 2 (14.0); CHR Coins stay 0',
  (SELECT golden_spoons = 14.0 AND chr_coins = 0 FROM avatar_state WHERE user_id = '00000000-0000-0000-0000-00000000cb99'));
SELECT t_assert('v1.6.11 Q5: task spoon costs (0/1/2) and golden spoon rewards remain visible to the employee via RLS',
  has_column_privilege('authenticated', 'task', 's_base', 'SELECT')
  AND has_column_privilege('authenticated', 'task', 's_final', 'SELECT')
  AND has_column_privilege('authenticated', 'questionnaire_submission', 'reward_golden_spoons', 'SELECT')
  AND has_column_privilege('authenticated', 'avatar_state', 'golden_spoons', 'SELECT'));
RESET ROLE;

-- 10 & 11. (C-1, C-2, O-30, O-31) Confirmed soft WIP, Weinberg L(P), EPWI_cognitive bands, population SD σ for AIDB
SELECT t_assert('v1.6.11 C-2 & O-30 & O-31: Weinberg L(1..6) = 0/0.20/0.40/0.60/0.75/0.75; EPWI_cognitive bands <=1.10 target, <=1.50 above_target, >1.50 overload; AIDB pop SD',
  fn_context_switch_loss(1) = 0.00 AND fn_context_switch_loss(2) = 0.20 AND fn_context_switch_loss(3) = 0.40
  AND fn_context_switch_loss(4) = 0.60 AND fn_context_switch_loss(5) = 0.75 AND fn_context_switch_loss(6) = 0.75
  AND fn_epwi_cognitive_band(1.10) = 'target' AND fn_epwi_cognitive_band(1.11) = 'above_target'
  AND fn_epwi_cognitive_band(1.50) = 'above_target' AND fn_epwi_cognitive_band(1.51) = 'overload'
  AND round(fn_aidb_of(ARRAY[30, 40, 50]::numeric[]), 2) = 79.59);

-- ============ v1.6.12 (Karin 24.10 + Chief of Drive 24.10): O-7, O-25, O-14, O-13, O-19, O-20 ============

-- 1. (O-7) PCQ-12 answer scale: 1–6 (Luthans, 12 items, all required), converted linearly to 0–100 ((mean - 1) / 5.0 * 100)
SELECT t_assert('v1.6.12 O-7: PCQ-12 definition locked with item_count=12, answer_min=1, answer_max=6, all_required=true, scoring_method=pcq12',
  (SELECT item_count = 12 AND answer_min = 1 AND answer_max = 6 AND all_required AND scoring_method = 'pcq12' AND is_locked
     FROM questionnaire_definition WHERE code = 'PCQ-12'));
SELECT t_assert('v1.6.12 O-7: fn_pcq12_score linear 1–6 → 0–100 (all 1→0, all 6→100, {1..6,1..6} mean 3.5→50.00)',
  fn_pcq12_score('{1,1,1,1,1,1,1,1,1,1,1,1}') = 0.00
  AND fn_pcq12_score('{6,6,6,6,6,6,6,6,6,6,6,6}') = 100.00
  AND fn_pcq12_score('{1,2,3,4,5,6,1,2,3,4,5,6}') = 50.00
  AND fn_pcq12_score('{0,2,3,4,5,6,1,2,3,4,5,6}') IS NULL
  AND fn_pcq12_score('{7,2,3,4,5,6,1,2,3,4,5,6}') IS NULL
  AND fn_pcq12_score('{1,2,3,4,5,6,1,2,3,4,5}') IS NULL);
SELECT t_as(t_emp('D9', 5));
SET ROLE authenticated;
SELECT t_expect_err('v1.6.12 O-7: PCQ-12 rejects answer 0 (< 1) → 400 questionnaire_invalid_answers',
  $$SELECT rpc_submit_questionnaire('PCQ-12', '{0,2,3,4,5,6,1,2,3,4,5,6}')$$, 'questionnaire_invalid_answers');
SELECT t_expect_err('v1.6.12 O-7: PCQ-12 rejects answer 7 (> 6) → 400 questionnaire_invalid_answers',
  $$SELECT rpc_submit_questionnaire('PCQ-12', '{1,2,3,4,5,7,1,2,3,4,5,6}')$$, 'questionnaire_invalid_answers');
SELECT t_expect_err('v1.6.12 O-7: PCQ-12 rejects 11 items (all 12 required) → 400 questionnaire_invalid_answers',
  $$SELECT rpc_submit_questionnaire('PCQ-12', '{1,2,3,4,5,6,1,2,3,4,5}')$$, 'questionnaire_invalid_answers');
SELECT t_expect_err('v1.6.12 O-7: PCQ-12 rejects NULL item → 400 questionnaire_invalid_answers',
  $$SELECT rpc_submit_questionnaire('PCQ-12', '{1,2,3,4,5,NULL,1,2,3,4,5,6}')$$, 'questionnaire_invalid_answers');
SELECT t_assert('v1.6.12 O-7: PCQ-12 submission {1..6,1..6} → score 50.00, pcq12_score 50.00, reward 10.0 golden spoons',
  (SELECT score = 50.00 AND pcq12_score = 50.00 AND tps_12_score IS NULL AND ihs_score IS NULL AND reward_golden_spoons = 10.0
     FROM rpc_submit_questionnaire('PCQ-12', '{1,2,3,4,5,6,1,2,3,4,5,6}')));
RESET ROLE;

-- 2. (O-20 & O-25) Governance-only user provisioning (CHRO) & Board / Tier 5 whole-company macro metrics
SELECT t_as('00000000-0000-0000-0000-00000000cb00');   -- manager (not CHRO) in ShadowCo
SET ROLE authenticated;
SELECT t_expect_err('v1.6.12 O-20: non-CHRO cannot provision governance user → 403 access_denied',
  $$SELECT rpc_provision_governance_user('00000000-0000-0000-0000-00000000cb80', 'bchair@sb', 'SB Chair', 'board_chair', 'Asia/Jerusalem')$$, 'access_denied');
RESET ROLE;

SELECT t_as('00000000-0000-0000-0000-00000000cb01');   -- CHRO in ShadowCo
SET ROLE authenticated;
SELECT t_expect_err('v1.6.12 O-20: rpc_provision_governance_user rejects non-tier-5 role (vp) → 400 invalid_governance_role',
  $$SELECT rpc_provision_governance_user('00000000-0000-0000-0000-00000000cb80', 'bchair@sb', 'SB Chair', 'vp', 'Asia/Jerusalem')$$, 'invalid_governance_role');
SELECT user_id IS NOT NULL AS chair_prov_ok
  FROM rpc_provision_governance_user('00000000-0000-0000-0000-00000000cb80', 'bchair@sb', 'SB Chair', 'board_chair', 'Asia/Jerusalem');
SELECT user_id IS NOT NULL AS member_prov_ok
  FROM rpc_provision_governance_user('00000000-0000-0000-0000-00000000cb81', 'bmem@sb', 'SB Member', 'board_member', 'Asia/Jerusalem');
SELECT user_id IS NOT NULL AS owner_emp_prov_ok
  FROM rpc_provision_governance_user('00000000-0000-0000-0000-00000000cb82', 'owner@sb', 'SB Owner-Employee', 'owner_shareholder', 'Asia/Jerusalem', true);
RESET ROLE;

SELECT t_assert('v1.6.12 O-20: CHRO-provisioned tier 5 users default to has_employee_profile = false unless p_also_employee = true',
  (SELECT NOT has_employee_profile AND app_role = 'board_chair' AND org_role_code = 'board_chair' FROM users WHERE user_id = '00000000-0000-0000-0000-00000000cb80')
  AND (SELECT NOT has_employee_profile AND app_role = 'board_member' AND org_role_code = 'board_member' FROM users WHERE user_id = '00000000-0000-0000-0000-00000000cb81')
  AND (SELECT has_employee_profile AND app_role = 'owner_shareholder' AND org_role_code = 'owner_shareholder' FROM users WHERE user_id = '00000000-0000-0000-0000-00000000cb82')
  AND fn_effective_turnover_tier('00000000-0000-0000-0000-00000000cb80') IS NULL);

-- Add 3 more spoon/workload/TPS/IHS reports in ShadowCo so regular metrics reach N>=5 (while keeping some below 5 first to test N>=5 gating!)
-- Currently in ShadowCo (00000000-0000-0000-0000-0000000000cb):
--   shadow_contributor_count = 10 (N>=10 met: happiness_debt_balance = 290,000, deprivation_tax_amount = 36,000, shadow_balance_sum = 326,000)
--   spoon_reporter_count today = 4 (cb15, cb16, cb18, cb99) -> <5 so spoons_company_avg is NULL!
--   workload_respondent_count this week = 2 (cb16, cb18) -> <5 so epwi/pewi is NULL!
SELECT t_as('00000000-0000-0000-0000-00000000cb80');   -- board_chair of ShadowCo
SET ROLE authenticated;
SELECT t_assert('v1.6.12 O-25 (v1.6.16 two-week deprivation): board_chair sees N>=5 spoons avg and N>=10 Shadow Balance metrics while TPS/IHS/EPWI/PEWI (<5 respondents) stay NULL',
  (SELECT contributor_count >= 10
          AND spoon_reporter_count = 5 AND spoons_company_avg = 8.00
          AND workload_respondent_count = 2 AND epwi_time_company_avg IS NULL AND pewi_company_avg IS NULL
          AND tps_respondent_count = 0 AND tps12_company_avg IS NULL
          AND ihs_respondent_count = 0 AND ihs_company_avg IS NULL
          AND shadow_contributor_count >= 10
          -- v1.6.16 (v3 two-consecutive-weeks rule): the third employee is deprived in THIS week only → not counted
          AND deprived_count = 2
          AND happiness_debt_balance = 290000.00
          AND deprivation_tax_amount = 36000.00
          AND shadow_balance_sum = 326000.00
          AND chr_real_ebitda = 9674000.00
     FROM rpc_get_board_macro_metrics(10000000)));
SELECT t_expect_err('v1.6.12 O-25: board_chair is strictly blocked from team aggregate breakdown → 403',
  $$SELECT rpc_team_aggregate_refresh('00000000-0000-0000-0000-0000000000cb', 'SB10')$$, 'aggregation_privacy_threshold');
SELECT t_expect_err('v1.6.12 O-25: board_chair is strictly blocked from Shadow Balance department breakdown → 403',
  $$SELECT rpc_shadow_balance_refresh('00000000-0000-0000-0000-0000000000cb', 'SB10')$$, 'aggregation_privacy_threshold');
SELECT t_expect_err('v1.6.12 O-25: board_chair is strictly blocked from subtree drill-down → 403',
  $$SELECT * FROM rpc_subtree_summary('00000000-0000-0000-0000-00000000cb00')$$, 'access_denied');
SELECT t_expect_err('v1.6.12 O-25: board_chair is strictly blocked from individual named view → 403',
  $$SELECT * FROM rpc_chro_named_view('00000000-0000-0000-0000-00000000cb11', 'audit')$$, 'access_denied');
RESET ROLE;

-- Now add respondents in ShadowCo so spoons, TPS-12, IHS, and workload/EPWI/PEWI all have >= 5 respondents!
DO $$
DECLARE
  u uuid;
BEGIN
  FOREACH u IN ARRAY ARRAY[
    '00000000-0000-0000-0000-00000000cb11'::uuid,
    '00000000-0000-0000-0000-00000000cb12'::uuid,
    '00000000-0000-0000-0000-00000000cb13'::uuid,
    '00000000-0000-0000-0000-00000000cb14'::uuid,
    '00000000-0000-0000-0000-00000000cb15'::uuid
  ] LOOP
    PERFORM t_as(u);
    SET LOCAL ROLE authenticated;
    PERFORM rpc_morning_checkin('{2, 2, 2}');   -- 12 spoons
    PERFORM rpc_submit_questionnaire('TPS-12', '{5,5,5,5,5,5,5,5,5,5,5,5}');   -- 66.67
    PERFORM rpc_submit_questionnaire('IHS', '{4,4,4}');                        -- 75.00
    IF NOT EXISTS (SELECT 1 FROM workload_self_report WHERE user_id = u) THEN
      PERFORM rpc_submit_workload_self_report(40, 40, 0, 2, 1, 1);             -- EPWI_time 1.00, EPWI_cog 1.25
    END IF;
    RESET ROLE;
  END LOOP;
END $$;

SELECT t_as('00000000-0000-0000-0000-00000000cb81');   -- board_member
SET ROLE authenticated;
SELECT t_assert('v1.6.12 O-25: board_member sees all whole-company averages once N>=5 (spoons, TPS-12, IHS, EPWI/PEWI) and N>=10 (Happiness Debt, tax, CHR Real EBITDA)',
  (SELECT spoon_reporter_count >= 5 AND spoons_company_avg IS NOT NULL
          AND tps_respondent_count = 5 AND tps12_company_avg = 66.67
          AND ihs_respondent_count = 5 AND ihs_company_avg = 75.00
          AND workload_respondent_count >= 5 AND epwi_time_company_avg IS NOT NULL
          AND epwi_cognitive_company_avg IS NOT NULL AND pewi_company_avg = epwi_time_company_avg
          AND shadow_contributor_count >= 10 AND chr_real_ebitda IS NOT NULL
     FROM rpc_get_board_macro_metrics(10000000)));
RESET ROLE;

SELECT t_as('00000000-0000-0000-0000-00000000cb82');   -- owner_shareholder
SET ROLE authenticated;
SELECT t_assert('v1.6.12 O-25: owner_shareholder sees all whole-company macro metrics via rpc_get_board_macro_metrics',
  (SELECT tps12_company_avg = 66.67 AND ihs_company_avg = 75.00 AND chr_real_ebitda IS NOT NULL
     FROM rpc_get_board_macro_metrics(10000000)));
RESET ROLE;

-- Also test that when Shadow Balance contributors < 10 (e.g. a small company with 6 contributors), regular metrics show at N>=5 while Shadow Balance metrics are NULL
DO $$
DECLARE
  v_sc uuid := '00000000-0000-0000-0000-0000000000cc';
  v_bc uuid := '00000000-0000-0000-0000-00000000cc00';
  v_u  uuid;
  i    int;
BEGIN
  INSERT INTO companies (company_id, company_name, country, week_start_dow, last_workday_dow, timezone)
  VALUES (v_sc, 'SmallBoardCo', 'IL', 0, 4, 'Asia/Jerusalem');
  INSERT INTO auth.users (id) VALUES (v_bc);
  INSERT INTO users (user_id, company_id, email, full_name, department, app_role, org_role_code, timezone, has_employee_profile)
  VALUES (v_bc, v_sc, 'chair@sc', 'SC Chair', 'Board', 'board_chair', 'board_chair', 'Asia/Jerusalem', false);
  FOR i IN 1..6 LOOP
    v_u := ('00000000-0000-0000-0000-00000000cc0' || i)::uuid;
    INSERT INTO auth.users (id) VALUES (v_u);
    INSERT INTO users (user_id, company_id, email, full_name, department, app_role, org_role_code, timezone, hire_date)
    VALUES (v_u, v_sc, 'e' || i || '@sc', 'SC ' || i, 'Ops', 'employee', 'employee', 'Asia/Jerusalem', CURRENT_DATE - 100);
    PERFORM t_as(v_u);
    SET LOCAL ROLE authenticated;
    PERFORM rpc_morning_checkin('{1, 1, 1}');
    RESET ROLE;
  END LOOP;
END $$;
SELECT t_as('00000000-0000-0000-0000-00000000cc00');
SET ROLE authenticated;
SELECT t_assert('v1.6.12 O-25: in a 6-contributor company (N>=5 but <10), board sees regular company averages (spoons=12) while Shadow Balance metrics stay NULL',
  (SELECT contributor_count = 6 AND spoons_company_avg = 12.00
          AND shadow_contributor_count = 6
          AND happiness_debt_balance IS NULL AND deprivation_tax_amount IS NULL AND chr_real_ebitda IS NULL
     FROM rpc_get_board_macro_metrics(5000000)));
RESET ROLE;

-- 3. (O-13) Per-company ledger chain: genesis record seeded on company creation, broken chain alert + write block
SELECT t_assert('v1.6.12 O-13: every company has a GENESIS ledger record with previous_hash NULL and valid current_hash',
  (SELECT count(*) = (SELECT count(*) FROM companies)
     FROM manager_ledger WHERE event_type = 'GENESIS' AND previous_hash IS NULL AND manager_id IS NULL)
  AND fn_ledger_verify_chain('00000000-0000-0000-0000-0000000000cb')
  AND fn_ledger_verify_chain('00000000-0000-0000-0000-0000000000cc'));

-- Simulate a tampered/broken chain in SmallBoardCo (bypass WORM trigger as superuser in a transaction, verify audit + write block, then restore)
ALTER TABLE manager_ledger DISABLE TRIGGER trg_manager_ledger_worm;
UPDATE manager_ledger SET canonical_payload = '{"tampered":true}' WHERE org_id = '00000000-0000-0000-0000-0000000000cc' AND event_type = 'GENESIS';
ALTER TABLE manager_ledger ENABLE TRIGGER trg_manager_ledger_worm;
SELECT t_assert('v1.6.12 O-13: fn_ledger_verify_chain returns false on a broken chain',
  NOT fn_ledger_verify_chain('00000000-0000-0000-0000-0000000000cc'));
SELECT t_assert('v1.6.12 O-13: …and writes audit alert ledger_chain_broken',
  EXISTS (SELECT 1 FROM access_audit_log WHERE company_id = '00000000-0000-0000-0000-0000000000cc'
             AND action = 'ledger_chain_broken' AND scope->>'reason' = 'current_hash_mismatch'));
SELECT t_as('00000000-0000-0000-0000-00000000cb00');
SET ROLE authenticated;
SELECT t_expect_err('v1.6.12 O-13: rpc_ledger_append blocks writes to a broken company chain → 403 ledger_chain_broken',
  $$SELECT rpc_ledger_append('note', 1, 1, NULL, '00000000-0000-0000-0000-0000000000cc', 'Ops')$$, 'ledger_chain_broken');
RESET ROLE;
-- Restore SmallBoardCo genesis hash
ALTER TABLE manager_ledger DISABLE TRIGGER trg_manager_ledger_worm;
UPDATE manager_ledger
   SET canonical_payload = jsonb_build_object(
         'ledger_id', ledger_id, 'manager_id', manager_id, 'org_id', org_id, 'department', department,
         'event_type', event_type, 'amount_a', amount_a, 'amount_b', amount_b,
         'deprivation_tax_cost', deprivation_tax_cost, 'subject_pseudonym', subject_pseudonym,
         'restoration_status', restoration_status, 'created_at', created_at)::text
 WHERE org_id = '00000000-0000-0000-0000-0000000000cc' AND event_type = 'GENESIS';
ALTER TABLE manager_ledger ENABLE TRIGGER trg_manager_ledger_worm;
SELECT t_assert('v1.6.12 O-13: restored chain verifies again', fn_ledger_verify_chain('00000000-0000-0000-0000-0000000000cc'));

-- 4. (O-19) Manager vault rules: direct manager only, office network + company device required, inactivity timeout, wipe on transfer/dismissal
SELECT t_as(t_u('ceo'));   -- averages-only manager
SET ROLE authenticated;
SELECT t_expect_err('v1.6.12 O-19: CEO (averages-only) cannot open manager vault → 403 access_denied',
  $$SELECT rpc_manager_vault_open(true, true, 15)$$, 'access_denied');
RESET ROLE;

SELECT t_as(t_u('dm1'));   -- direct manager of e1..e6
SET ROLE authenticated;
SELECT t_expect_err('v1.6.12 O-19: direct manager outside office network rejected → 403 manager_vault_environment_denied',
  $$SELECT rpc_manager_vault_open(false, true, 15)$$, 'manager_vault_environment_denied');
SELECT t_expect_err('v1.6.12 O-19: direct manager on personal device rejected → 403 manager_vault_environment_denied',
  $$SELECT rpc_manager_vault_open(true, false, 15)$$, 'manager_vault_environment_denied');
SELECT manager_id IS NOT NULL AS vault_open_ok FROM rpc_manager_vault_open(true, true, 15);
SELECT entry_id IS NOT NULL AS vault_put_e1 FROM rpc_manager_vault_put(t_u('e1'), E'\\x0102'::bytea);
SELECT entry_id IS NOT NULL AS vault_put_e2 FROM rpc_manager_vault_put(t_u('e2'), E'\\x0304'::bytea);
SELECT t_expect_err('v1.6.12 O-19: direct manager cannot put non-direct report (e7 reports to dm2) into vault → 403 access_denied',
  format($$SELECT rpc_manager_vault_put(%L, E'\\\\x05'::bytea)$$, t_u('e7')), 'access_denied');
SELECT t_assert('v1.6.12 O-19: direct manager reads her 2 vault entries while session is active',
  (SELECT count(*) = 2 FROM rpc_manager_vault_entries()));
RESET ROLE;

-- Simulate inactivity timeout (> 15 minutes idle)
UPDATE manager_vault_session SET last_active_at = clock_timestamp() - interval '16 minutes' WHERE manager_id = t_u('dm1');
SELECT t_as(t_u('dm1'));
SET ROLE authenticated;
SELECT t_expect_err('v1.6.12 O-19: reading vault after inactivity timeout → 403 manager_vault_session_expired',
  $$SELECT * FROM rpc_manager_vault_entries()$$, 'manager_vault_session_expired');
-- Re-open session on office network + company device
SELECT manager_id IS NOT NULL AS vault_reopen_ok FROM rpc_manager_vault_open(true, true, 15);
RESET ROLE;

-- Transferring direct report e1 to another department removes e1 from dm1's vault immediately
UPDATE users SET department = 'MovedDept' WHERE user_id = t_u('e1');
SELECT t_as(t_u('dm1'));
SET ROLE authenticated;
SELECT t_assert('v1.6.12 O-19: transferring employee e1 immediately removes her entry from dm1 vault (only e2 remains)',
  (SELECT count(*) = 1 AND bool_and(subject_user_id = t_u('e2')) FROM rpc_manager_vault_entries()));
RESET ROLE;

-- Transferring manager dm1 herself to another department wipes her entire vault and closes her session immediately
UPDATE users SET department = 'NewMgrDept' WHERE user_id = t_u('dm1');
SELECT t_assert('v1.6.12 O-19: transferring manager dm1 wipes all her vault entries and marks session wiped',
  (SELECT count(*) = 0 FROM manager_vault_entry WHERE manager_id = t_u('dm1'))
  AND (SELECT wiped_at IS NOT NULL AND wipe_reason = 'department_or_company_transfer' FROM manager_vault_session WHERE manager_id = t_u('dm1')));
SELECT t_as(t_u('dm1'));
SET ROLE authenticated;
SELECT t_expect_err('v1.6.12 O-19: wiped vault session denies access until re-authenticated on office network + company device',
  $$SELECT * FROM rpc_manager_vault_entries()$$, 'manager_vault_environment_denied');
RESET ROLE;

-- ============ 13. Offboarding & crypto-shredding retention (lock #7 + v1.6.12 O-14) ============
-- Self-request (rpc_request_crypto_shred): immediate 0-day crypto-shredding
SELECT fn_subject_pseudonym(t_emp('D5', 3)) IS NOT NULL AS d5_3_key_seeded;
SELECT t_as(t_emp('D5', 3));
SET ROLE authenticated;
SELECT shredded_at IS NOT NULL AS self_shred_ok FROM rpc_request_crypto_shred();
RESET ROLE;
SELECT t_assert('v1.6.12 O-14: self-request rpc_request_crypto_shred shreds key immediately (0-day wait)',
  (SELECT key_material IS NULL AND shredded_at IS NOT NULL AND scheduled_shred_at IS NULL
     FROM pseudonym_key WHERE user_id = t_emp('D5', 3)));

-- Automatic offboarding (rpc_offboard_employee): revokes access & vault immediately, schedules shred at terminated_at + 30 days
UPDATE users SET consent_vault = true WHERE user_id = t_emp('D5', 2);
SELECT t_assert('active employee key exists before offboarding',
  (SELECT key_material IS NOT NULL AND shredded_at IS NULL FROM pseudonym_key WHERE user_id = t_emp('D5', 2)));
SELECT rpc_offboard_employee(t_emp('D5', 2)) IS NOT NULL AS offboarded;
SELECT t_assert('v1.6.12 O-14: offboarding revokes access & consent_vault immediately and schedules shred for terminated_at + 30 days (not shredded at day 0)',
  NOT fn_has_employee_profile(t_emp('D5', 2))
  AND (SELECT NOT consent_vault AND employment_ended_at IS NOT NULL FROM users WHERE user_id = t_emp('D5', 2))
  AND (SELECT key_material IS NOT NULL AND shredded_at IS NULL
              AND scheduled_shred_at BETWEEN clock_timestamp() + interval '29 days 23 hours' AND clock_timestamp() + interval '30 days 1 minute'
         FROM pseudonym_key WHERE user_id = t_emp('D5', 2)));
-- Scheduled job before 30 days have elapsed does not shred D5-2
SELECT t_assert('v1.6.12 O-14: rpc_run_scheduled_crypto_shred before 30 days shreds 0 keys',
  rpc_run_scheduled_crypto_shred() = 0);
SELECT t_assert('v1.6.12 O-14: …and leaves D5-2 key unshredded while within the 30-day window',
  (SELECT key_material IS NOT NULL AND shredded_at IS NULL FROM pseudonym_key WHERE user_id = t_emp('D5', 2)));

-- Reverting offboarding within the 30-day window cancels the scheduled shred and restores access
SELECT user_id IS NOT NULL AS revert_ok FROM rpc_revert_offboarding(t_emp('D5', 2));
SELECT t_assert('v1.6.12 O-14: rpc_revert_offboarding within 30 days restores employment and cancels scheduled shred',
  fn_has_employee_profile(t_emp('D5', 2))
  AND (SELECT employment_ended_at IS NULL FROM users WHERE user_id = t_emp('D5', 2))
  AND (SELECT key_material IS NOT NULL AND shredded_at IS NULL AND scheduled_shred_at IS NULL
         FROM pseudonym_key WHERE user_id = t_emp('D5', 2)));

-- Offboard D5-2 again, advance scheduled_shred_at to the past (30 days elapsed), and run rpc_run_scheduled_crypto_shred()
SELECT rpc_offboard_employee(t_emp('D5', 2)) IS NOT NULL AS offboarded_again;
UPDATE pseudonym_key SET scheduled_shred_at = clock_timestamp() - interval '1 minute' WHERE user_id = t_emp('D5', 2);
SELECT t_assert('v1.6.12 O-14: rpc_run_scheduled_crypto_shred shreds keys whose 30-day wait has elapsed (returns 1)',
  rpc_run_scheduled_crypto_shred() = 1);
SELECT t_assert('offboarding shreds the pseudonym key after 30-day wait',
  (SELECT key_material IS NULL AND shredded_at IS NOT NULL AND scheduled_shred_at IS NULL
     FROM pseudonym_key WHERE user_id = t_emp('D5', 2)));
SELECT t_expect_err('v1.6.12 O-14: rpc_revert_offboarding refused after key is shredded → 403 offboarding_shred_already_executed',
  format($$SELECT rpc_revert_offboarding(%L)$$, t_emp('D5', 2)), 'offboarding_shred_already_executed');
SELECT t_assert('ledger chain intact after offboarding shred', fn_ledger_verify_chain('00000000-0000-0000-0000-0000000000c1'));
SELECT t_assert('offboarded user loses the shop (no employee interface)', NOT fn_has_employee_profile(t_emp('D5', 2)));
SELECT t_assert('offboarding RPC is system-only',
  NOT has_function_privilege('authenticated', 'rpc_offboard_employee(uuid, timestamptz)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'rpc_run_scheduled_crypto_shred()', 'EXECUTE'));

-- ============ v1.6.13 (Karin 25.10 + Chief of Drive 25.10): EverStore expansion, Golden Spoons policy, נעילת הפרגוד ============

-- 1. shop_item_catalog expansion: 8 opening seed items (קטלוג פתיחה), 8 categories, provider, cosmetic_only true/false,
--    real_money_purchase_allowed=false & affects_daily_energy_spoons=false strictly locked, any positive price_golden_spoons > 0
SELECT t_assert('v1.6.13: 8 opening seed items (קטלוג פתיחה) seeded with category=cosmetic, real_money_purchase_allowed=false, affects_daily_energy_spoons=false',
  (SELECT count(*) = 8 AND bool_and(category = 'cosmetic' AND cosmetic_only AND NOT real_money_purchase_allowed AND NOT affects_daily_energy_spoons AND price_golden_spoons IN (10, 20))
     FROM shop_item_catalog WHERE is_active)
  AND obj_description('shop_item_catalog'::regclass) LIKE '%קטלוג פתיחה%');

SELECT t_expect_err('v1.6.13: shop_item_catalog rejects unknown category → 23514',
  $$INSERT INTO shop_item_catalog (item_id, display_name, name_he, category, price_coins) VALUES ('bad_cat', 'Bad', 'רע', 'crypto_lootbox', 15)$$, '23514');
SELECT t_expect_err('v1.6.13: shop_item_catalog strictly rejects real_money_purchase_allowed = true → 23514',
  $$INSERT INTO shop_item_catalog (item_id, display_name, name_he, category, price_coins, real_money_purchase_allowed) VALUES ('bad_rm', 'Bad', 'רע', 'merchandise', 15, true)$$, '23514');
SELECT t_expect_err('v1.6.13: shop_item_catalog strictly rejects affects_daily_energy_spoons = true → 23514',
  $$INSERT INTO shop_item_catalog (item_id, display_name, name_he, category, price_coins, affects_daily_energy_spoons) VALUES ('bad_sp', 'Bad', 'רע', 'health_wellbeing', 15, true)$$, '23514');
SELECT t_expect_err('v1.6.13: shop_item_catalog rejects price <= 0 (0) → 23514',
  $$INSERT INTO shop_item_catalog (item_id, display_name, name_he, category, price_coins) VALUES ('bad_p0', 'Bad', 'רע', 'learning', 0)$$, '23514');
SELECT t_expect_err('v1.6.13: shop_item_catalog rejects negative price (-5) → 23514',
  $$INSERT INTO shop_item_catalog (item_id, display_name, name_he, category, price_coins) VALUES ('bad_pn', 'Bad', 'רע', 'learning', -5)$$, '23514');

-- Non-CHRO cannot upsert catalog items; CHRO (vp_hr) can add items across all 8 categories with cosmetic_only=false, provider, and prices beyond 10/20 (e.g. 5.5, 35, 75, 120)
SELECT t_as('00000000-0000-0000-0000-00000000aaaa');
SET ROLE authenticated;
SELECT t_expect_err('v1.6.13: manager (non-CHRO) cannot upsert EverStore items → 403 access_denied',
  $$SELECT rpc_everstore_upsert_item('v_time_1', 'Half-day Refresh', 'חצי יום התרעננות', 'time_benefit', 35.0, 'premium', false, 'Internal HR')$$, 'access_denied');
RESET ROLE;

SELECT t_as('00000000-0000-0000-0000-00000000bbbb');   -- CHRO (vp_hr)
SET ROLE authenticated;
SELECT item_id IS NOT NULL AS item_time_ok
  FROM rpc_everstore_upsert_item('voucher_refresh_day', 'Refresh Day Voucher', 'שובר יום התרעננות', 'time_benefit', 35.0, 'premium', false, 'Internal HR');
SELECT item_id IS NOT NULL AS item_health_ok
  FROM rpc_everstore_upsert_item('spa_massage', 'Somatic Massage Session', 'טיפול עיסוי סומטי', 'health_wellbeing', 45.0, 'premium', false, 'WellSpa Ltd');
SELECT item_id IS NOT NULL AS item_learn_ok
  FROM rpc_everstore_upsert_item('course_book', 'Learning Book Grant', 'מענק ספר למידה', 'learning', 15.5, 'custom', false, 'AcadPress');
SELECT item_id IS NOT NULL AS item_don_ok
  FROM rpc_everstore_upsert_item('charity_trees', 'Plant 5 Trees Donation', 'תרומת נטיעת 5 עצים', 'donation', 5.0, 'basic', false, 'GreenEarth');
SELECT item_id IS NOT NULL AS item_exp_ok
  FROM rpc_everstore_upsert_item('concert_pass', 'Cultural Experience Pass', 'שובר חוויה תרבותית', 'experience', 60.0, 'premium', false, 'CultureHub');
SELECT item_id IS NOT NULL AS item_gc_ok
  FROM rpc_everstore_upsert_item('coffee_card', 'Coffee & Pastry Card', 'כרטיס קפה ומאפה', 'gift_card', 7.5, 'custom', false, 'CafeNet');
SELECT item_id IS NOT NULL AS item_merch_ok
  FROM rpc_everstore_upsert_item('hoodie_chr', 'CHR Cozy Hoodie', 'קפוצ׳ון CHR', 'merchandise', 25.0, 'advanced', false, 'CHR Studio');
RESET ROLE;

SELECT t_assert('v1.6.13: all 8 categories exist in shop_item_catalog with tangible items (cosmetic_only = false), providers, and arbitrary positive prices (5.0..60.0)',
  (SELECT count(DISTINCT category) = 8 FROM shop_item_catalog WHERE is_active)
  AND (SELECT count(*) = 7 AND bool_and(NOT cosmetic_only AND provider IS NOT NULL AND price_golden_spoons > 0)
         FROM shop_item_catalog WHERE category <> 'cosmetic'));

-- 2. Golden Spoons never expire while the employee is active & rpc_convert_golden_to_chr remains active on server in v1
SELECT t_assert('v1.6.13: avatar_state.golden_spoons_expires_at is NULL for all rows (Golden Spoons never expire)',
  (SELECT bool_and(golden_spoons_expires_at IS NULL) FROM avatar_state)
  AND col_description('avatar_state'::regclass, (SELECT attnum FROM pg_attribute WHERE attrelid = 'avatar_state'::regclass AND attname = 'golden_spoons_expires_at')) LIKE '%NEVER expire%');
SELECT t_expect_err('v1.6.13: setting a non-NULL golden_spoons_expires_at is rejected by CHECK → 23514',
  $$UPDATE avatar_state SET golden_spoons_expires_at = clock_timestamp() + interval '365 days'$$, '23514');
SELECT t_assert('v1.6.13: rpc_convert_golden_to_chr remains active on the server in v1 (executable by authenticated)',
  has_function_privilege('authenticated', 'rpc_convert_golden_to_chr(numeric, varchar)', 'EXECUTE'));

-- 3. Time-benefit voucher redemption privacy (נעילת הפרגוד):
--    Employee D5-4 (reports to manager 0000aaaa) buys 'voucher_refresh_day' (35.0 golden spoons, time_benefit) and 'course_book' (15.5, learning).
INSERT INTO avatar_state (user_id, golden_spoons) VALUES (t_emp('D5', 4), 60.0) ON CONFLICT (user_id) DO UPDATE SET golden_spoons = 60.0;
SELECT t_as(t_emp('D5', 4));
SET ROLE authenticated;
SELECT golden_spoons = 44.5 AS buy_learn_ok FROM rpc_everstore_purchase('course_book', 'idem-learn-1');
SELECT golden_spoons = 9.5 AS buy_time_ok   FROM rpc_everstore_purchase('voucher_refresh_day', 'idem-time-1', CURRENT_DATE + 7);
-- Idempotency: re-submitting 'idem-time-1' does not deduct again and does not create a duplicate absence entry
SELECT golden_spoons = 9.5 AS buy_time_idem FROM rpc_everstore_purchase('voucher_refresh_day', 'idem-time-1', CURRENT_DATE + 7);
SELECT t_assert('v1.6.13: employee sees her own 2 purchases in shop_purchase (15.5 learning + 35.0 time_benefit) and her approved_absence_entry',
  (SELECT count(*) = 2 AND sum(price_golden_spoons) = 50.5 FROM shop_purchase WHERE user_id = t_emp('D5', 4))
  AND (SELECT count(*) = 1 AND bool_and(entry_type = 'approved_absence' AND entry_text = 'זמן התרעננות / היעדרות מאושרת' AND requested_date = CURRENT_DATE + 7)
         FROM approved_absence_entry WHERE user_id = t_emp('D5', 4)));
RESET ROLE;

-- Direct manager (0000aaaa) checks shop_purchase (strictly hidden!) and approved_absence_manager_v (sees ONLY standard 'זמן התרעננות / היעדרות מאושרת' with pseudonym, zero link to EverStore!)
SELECT t_as('00000000-0000-0000-0000-00000000aaaa');
SET ROLE authenticated;
SELECT t_assert('v1.6.13 נעילת הפרגוד: direct manager sees 0 rows of any subordinate in shop_purchase (employee purchase history strictly hidden from managers)',
  (SELECT count(*) = 0 FROM shop_purchase WHERE user_id <> '00000000-0000-0000-0000-00000000aaaa')
  AND (SELECT count(*) = 0 FROM shop_purchase WHERE user_id = t_emp('D5', 4)));
SELECT t_assert('v1.6.13 נעילת הפרגוד: direct manager sees the time_benefit redemption ONLY as a standard approved_absence_manager_v entry (זמן התרעננות / היעדרות מאושרת) with pseudonym',
  (SELECT count(*) = 1
          AND bool_and(display_pseudonym = t_pseudo('D5', 4)
                       AND entry_type = 'approved_absence'
                       AND entry_text = 'זמן התרעננות / היעדרות מאושרת'
                       AND requested_date = CURRENT_DATE + 7
                       AND schedule_status = 'pending_coordination')
     FROM approved_absence_manager_v));
SELECT t_assert('v1.6.13 נעילת הפרגוד: approved_absence_manager_v and approved_absence_entry have no item_id, purchase_id, or golden_spoons columns',
  NOT EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name IN ('approved_absence_entry', 'approved_absence_manager_v')
                 AND column_name ~* '(item|purchase|spoon|voucher|shop|price|coin)'));
-- Direct manager coordinates the schedule via rpc_coordinate_approved_absence
SELECT schedule_status = 'coordinated' AS coord_ok
  FROM rpc_coordinate_approved_absence((SELECT absence_id FROM approved_absence_manager_v LIMIT 1), CURRENT_DATE + 8);
SELECT t_assert('v1.6.13 נעילת הפרגוד: direct manager coordinated schedule_status = coordinated and updated date',
  (SELECT schedule_status = 'coordinated' AND requested_date = CURRENT_DATE + 8 FROM approved_absence_manager_v LIMIT 1));
RESET ROLE;

-- 4. Verify checkin aliases rpc_submit_morning_checkin / rpc_submit_midday_checkin exist and work
SELECT t_as(t_emp('D5', 4));
SET ROLE authenticated;
SELECT t_assert('v1.6.13 O-5 alias: rpc_submit_morning_checkin works identically to rpc_morning_checkin',
  (SELECT current_spoon_count = 12 AND reported_at IS NOT NULL FROM rpc_submit_morning_checkin('{2, 3, 2}')));
RESET ROLE;

SELECT 'ALL TESTS PASSED' AS result;
