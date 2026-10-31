-- =============================================================================
-- CHR-ETRS MVP v1.6.19 · tests/test_board_v1_6_19.sql — v1.6.19 board report, leaver batching, ILS estimate,
-- verification levels, 'תיק אימות', pay linkage, social events, layers + governance, sources (PostgreSQL 17)
-- Version: 1.6.19-mvp (2026-10-31; Karin 31.10 via Chief of Drive). Run on a FRESH database after the pack:
--   psql -v ON_ERROR_STOP=1 -f ref_country_calendar.sql -f schema.sql -f rpc.sql -f tests/test_board_v1_6_19.sql
-- Every check prints "PASS <name>"; any failure aborts. Dates are relative to the run (current company month)
-- because leaver batches are stamped with the real clock.
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
  SELECT md5('board-v1619-' || p_key)::uuid
$$;

-- Create one fixture user (auth + users); returns its uuid.
CREATE OR REPLACE FUNCTION t_mk(p_company uuid, p_key text, p_dept text, p_role text DEFAULT 'employee',
                                p_org_role text DEFAULT 'employee', p_mgr text DEFAULT NULL) RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id) VALUES (t_u(p_key));
  INSERT INTO users (user_id, company_id, reports_to, email, full_name, department, app_role, org_role_code, timezone, hire_date)
  VALUES (t_u(p_key), p_company, CASE WHEN p_mgr IS NOT NULL THEN t_u(p_mgr) END, p_key || '@board.test',
          'Board Person ' || p_key, p_dept, p_role, p_org_role, 'Asia/Jerusalem', DATE '2025-01-01');
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


-- Let a fixture employee leave now with a Happiness Debt share (→ leaver_transfer + internal link + batch trigger).
CREATE OR REPLACE FUNCTION t_leave(p_key text, p_debt numeric) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO employee_value_asset (user_id, company_id, annual_salary)
  SELECT t_u(p_key), u.company_id, 100000 FROM users u WHERE u.user_id = t_u(p_key)
  ON CONFLICT (user_id) DO NOTHING;
  UPDATE employee_value_asset SET happiness_debt_liability = p_debt WHERE user_id = t_u(p_key);
  UPDATE users SET employment_ended_at = clock_timestamp() - interval '1 minute' WHERE user_id = t_u(p_key);
END $$;

-- The published memo amount of a company for the current month.
CREATE OR REPLACE FUNCTION t_memo(p_company uuid) RETURNS numeric LANGUAGE sql AS $$
  SELECT (fn_leaver_memo_published(p_company, fn_agent_month_start(p_company, clock_timestamp()))->>'amount')::numeric
$$;
GRANT EXECUTE ON FUNCTION t_memo(uuid) TO authenticated;

-- ---------- fixtures ----------
-- G: leaver batching + board report (team TA: 12 reporters, 40 leavers). H: complementary rule (upgrade-style
-- batches). J: no 2-transfer rule. S: ILS estimate, layers, governance, social events.
INSERT INTO companies (company_id, company_name, country, week_start_dow, last_workday_dow, timezone) VALUES
  (t_u('cG'), 'Board G', 'IL', 0, 4, 'Asia/Jerusalem'),
  (t_u('cH'), 'Board H', 'IL', 0, 4, 'Asia/Jerusalem'),
  (t_u('cJ'), 'Board J', 'IL', 0, 4, 'Asia/Jerusalem'),
  (t_u('cS'), 'Board S', 'IL', 0, 4, 'Asia/Jerusalem');
DO $$
DECLARE i int; c text;
BEGIN
  FOREACH c IN ARRAY ARRAY['G', 'H', 'J', 'S'] LOOP
    PERFORM t_mk(t_u('c' || c), 'hr' || c, 'Mgmt', 'vp_hr', 'vp');
    PERFORM t_mk(t_u('c' || c), 'cfo' || c, 'Mgmt', 'cfo', 'vp');
    PERFORM t_mk(t_u('c' || c), 'mgr' || c, 'Mgmt', 'manager', 'direct_manager');
    PERFORM t_mk(t_u('c' || c), 'chair' || c, 'Board', 'board_chair', 'board_chair');
  END LOOP;
  FOR i IN 1..12 LOOP PERFORM t_mk(t_u('cG'), 'empG' || i, 'TA', 'employee', 'employee', 'mgrG'); END LOOP;
  FOR i IN 1..40 LOOP PERFORM t_mk(t_u('cG'), 'gL' || i, 'TA'); END LOOP;
  FOR i IN 1..20 LOOP PERFORM t_mk(t_u('cH'), 'hA' || i, 'HA'); END LOOP;
  FOR i IN 1..3  LOOP PERFORM t_mk(t_u('cH'), 'hB' || i, 'HB'); END LOOP;
  FOR i IN 1..10 LOOP PERFORM t_mk(t_u('cH'), 'hC' || i, 'HC'); END LOOP;
  FOR i IN 1..9  LOOP PERFORM t_mk(t_u('cJ'), 'jL' || i, 'JA'); END LOOP;
  FOR i IN 1..12 LOOP PERFORM t_mk(t_u('cS'), 'empS' || i, 'OPS', 'employee', 'employee', 'mgrS'); END LOOP;
END $$;
CREATE TEMP TABLE t_m AS SELECT fn_agent_month_start(t_u('cG'), clock_timestamp()) AS m,
                                fn_agent_local_ts(t_u('cG'), clock_timestamp())::date AS today;
GRANT SELECT ON t_m TO authenticated;
-- Company G month data for a publishable report: 12 PCQ-12 reporters, Shadow Balance 1,000 (+ מס קיפוח 100).
SELECT t_pcq('empG' || i, (SELECT m FROM t_m), 70) FROM generate_series(1, 12) i;
INSERT INTO shadow_balance_aggregate (org_id, department, contributor_count, deprived_count, deprivation_tax_amount,
                                      happiness_debt_sum, shadow_balance_sum, calculated_at)
SELECT t_u('cG'), 'TA', 12, 3, 100, 1000, 1100, fn_agent_day_start(t_u('cG'), (SELECT m FROM t_m)) + interval '2 hours';
SELECT t_as(t_u('cfoG'));
SET ROLE authenticated;
SELECT period_month FROM rpc_put_board_reconciliation(t_u('cG'), (SELECT m FROM t_m), 500000, 200000, true);
SELECT jsonb_array_length(rpc_put_happiness_debt_split(t_u('cG'), (SELECT m FROM t_m), 400, 300, 200, 100)) AS split_lines;
RESET ROLE;

-- ============ 1. J-43 (Karin 31.10): the memo line "יצא עם העוזבים" moves only per 10 NEW leavers ============
SELECT t_leave('gL' || i, 100 * i) FROM generate_series(1, 9) i;
SELECT t_assert('J-43: 9 new leavers → no batch; memo line not published ("עדיין לא הצטברו מספיק עוזבים לעדכון ראשון")',
  NOT EXISTS (SELECT 1 FROM leaver_memo_snapshot WHERE company_id = t_u('cG'))
  AND t_memo(t_u('cG')) IS NULL
  AND fn_leaver_memo_published(t_u('cG'), (SELECT m FROM t_m))->>'display_he' = 'עדיין לא הצטברו מספיק עוזבים לעדכון ראשון');
SELECT t_as(t_u('cfoG'));
SET ROLE authenticated;
INSERT INTO t_outputs SELECT 'list_9', jsonb_agg(to_jsonb(x)) FROM rpc_list_leaver_transfers(t_u('cG')) x;
RESET ROLE;
SELECT t_assert('J-43: with 9 leavers the leaver list is one company_total row with no amount',
  (SELECT jsonb_array_length(j) = 1 AND j->0->>'row_kind' = 'company_total' AND j->0->'transferred' = 'null'::jsonb
          AND j->0->'open_balance' = 'null'::jsonb AND j->0->'leavers_count' = '0'::jsonb FROM t_outputs WHERE label = 'list_9'));
SELECT t_leave('gL10', 1000);
SELECT t_assert('J-43: the 10th leaver → batch 1 (10 leavers); memo line = 5,500 (Σ 100..1,000)',
  (SELECT count(*) = 1 AND min(new_leavers) = 10 AND min(memo_amount) = 5500 FROM leaver_memo_snapshot WHERE company_id = t_u('cG'))
  AND t_memo(t_u('cG')) = 5500
  AND fn_leaver_memo_published(t_u('cG'), (SELECT m FROM t_m))->'waiting_note_he' = 'null'::jsonb);
SELECT t_as(t_u('cfoG'));
SET ROLE authenticated;
INSERT INTO t_outputs SELECT 'board_r1', rpc_build_board_report(t_u('cG'), (SELECT m FROM t_m));
RESET ROLE;
SELECT t_leave('gL11', 1100);
SELECT t_as(t_u('cfoG'));
SET ROLE authenticated;
INSERT INTO t_outputs SELECT 'board_r2', rpc_build_board_report(t_u('cG'), (SELECT m FROM t_m));
RESET ROLE;
SELECT t_assert('J-43: one more leaver → the report keeps the previous value (5,500) with the waiting note (טיוטה)',
  (SELECT (j->'exported_on_exit'->>'amount')::numeric = 5500 AND (j->'exported_on_exit'->>'batch_no')::int = 1
          AND j->'exported_on_exit'->>'waiting_note_he' = 'מוצג הערך מהעדכון הקודם; העדכון הבא ממתין להצטברות של מספיק עוזבים חדשים (10 לפחות).'
          AND j->'exported_on_exit'->>'text_status' = 'טיוטה' AND j->'exported_on_exit'->>'evidence_he' = 'בינוני'
     FROM t_outputs WHERE label = 'board_r2'));
SELECT t_assert('J-43 privacy: a single leaver''s debt cannot be computed from two board reports (difference = 0, not 1,100)',
  (SELECT (b.j->'exported_on_exit'->>'amount')::numeric - (a.j->'exported_on_exit'->>'amount')::numeric = 0
     FROM t_outputs a, t_outputs b WHERE a.label = 'board_r1' AND b.label = 'board_r2'));
SELECT t_leave('gL' || i, 100 * i) FROM generate_series(12, 19) i;
SELECT t_assert('J-43: 19 leavers (9 new since batch 1) → still 5,500, still waiting',
  t_memo(t_u('cG')) = 5500 AND (SELECT count(*) = 1 FROM leaver_memo_snapshot WHERE company_id = t_u('cG'))
  AND fn_leaver_memo_published(t_u('cG'), (SELECT m FROM t_m))->>'waiting_note_he' IS NOT NULL);
SELECT t_leave('gL20', 2000);
SELECT t_as(t_u('cfoG'));
SET ROLE authenticated;
INSERT INTO t_outputs SELECT 'board_r3', rpc_build_board_report(t_u('cG'), (SELECT m FROM t_m));
RESET ROLE;
SELECT t_assert('J-43: the 10th new leaver → batch 2; memo = 21,000; the change between reports is a sum of 10 leavers (15,500)',
  t_memo(t_u('cG')) = 21000
  AND (SELECT (b.j->'exported_on_exit'->>'amount')::numeric - (a.j->'exported_on_exit'->>'amount')::numeric = 15500
         FROM t_outputs a, t_outputs b WHERE a.label = 'board_r2' AND b.label = 'board_r3'));

-- ---- remediations and reversals move the memo only as a batch touching ≥ 10 distinct transfers ----
SELECT t_as(t_u('cfoG'));
SET ROLE authenticated;
SELECT t_assert('batching: a documented remediation of 50 for TA is recorded (attributed to the oldest open transfer)',
  rpc_record_remediation(t_u('cG'), 'TA', (SELECT today FROM t_m), 'הפחתת עומס', 50) = fn_remediation_response());
SELECT t_expect_http('v1.6.19: naming a transfer → 400 transfer_selection_not_allowed',
  $$SELECT rpc_record_remediation(t_u('cG'), 'TA', (SELECT today FROM t_m), 'x', 1, gen_random_uuid())$$, 'transfer_selection_not_allowed', 400);
SELECT t_assert('v1.6.19-r2 G-3: no 422 any more — the error code remediation_not_attributable is gone from every function',
  NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
               WHERE n.nspname = 'public' AND p.prosrc ~ 'remediation_not_attributable'));
RESET ROLE;
ALTER TABLE users DISABLE TRIGGER trg_users_leaver_debt_reversal;   -- test only: call the reversal directly to capture its output
UPDATE users SET employment_ended_at = NULL WHERE user_id = t_u('gL2');
ALTER TABLE users ENABLE TRIGGER trg_users_leaver_debt_reversal;
INSERT INTO t_outputs SELECT 'reversal_gl2', fn_reverse_leaver_transfer(t_u('gL2'));
SELECT t_assert('batching: the reversal output is status only (no amount, team, id or memo value)',
  (SELECT j = jsonb_build_object('status', 'reversed', 'label_he', 'יצא עם העוזבים') FROM t_outputs WHERE label = 'reversal_gl2'));
SELECT t_assert('batching: after 1 remediation + 1 reversal (2 transfers) the published memo stays 21,000 with the waiting note; the internal balance is 20,750',
  t_memo(t_u('cG')) = 21000 AND fn_leaver_memo(t_u('cG'), DATE '2100-01-01') = 20750
  AND fn_leaver_memo_published(t_u('cG'), (SELECT m FROM t_m))->>'waiting_note_he' IS NOT NULL);
SELECT t_leave('gL' || i, 100 * i) FROM generate_series(21, 30) i;
SELECT t_assert('batching: batch 3 (10 new leavers) leaves the 2-transfer adjustments out → memo 46,500 (21,000 + 25,500), adjusted_transfers 0',
  t_memo(t_u('cG')) = 46500
  AND (SELECT adjusted_transfers = 0 AND new_leavers = 10 FROM leaver_memo_snapshot WHERE company_id = t_u('cG') AND batch_no = 3));
-- 9 more remediations: gL1 (rest 50) and gL3..gL10 in full → 10 distinct transfers adjusted (with gL2's reversal)
SELECT t_as(t_u('cfoG'));
SET ROLE authenticated;
SELECT rpc_record_remediation(t_u('cG'), 'TA', (SELECT today FROM t_m), 'שינוי סידור עבודה', a) = fn_remediation_response() AS rem
  FROM unnest(ARRAY[50, 300, 400, 500, 600, 700, 800, 900, 1000]) a;
RESET ROLE;
SELECT t_assert('batching: 10 distinct transfers adjusted but no new leaver batch → the memo still shows 46,500',
  t_memo(t_u('cG')) = 46500 AND (SELECT count(*) = 3 FROM leaver_memo_snapshot WHERE company_id = t_u('cG')));
SELECT t_leave('gL' || i, 100 * i) FROM generate_series(31, 40) i;
SELECT t_assert('batching: batch 4 includes the adjustments (10 transfers) → memo = internal balance 76,500 (82,000 − 5,300 − 200)',
  t_memo(t_u('cG')) = 76500 AND fn_leaver_memo(t_u('cG'), DATE '2100-01-01') = 76500
  AND (SELECT adjusted_transfers = 10 AND remediated_total = 5300 AND reversed_total = 200
         FROM leaver_memo_snapshot WHERE company_id = t_u('cG') AND batch_no = 4));
SELECT t_expect_err('leaver_memo_snapshot is WORM', $$UPDATE leaver_memo_snapshot SET memo_amount = 0$$, 'ledger_immutable');
SELECT t_expect_err('leaver_memo_inclusion is WORM', $$DELETE FROM leaver_memo_inclusion$$, 'ledger_immutable');

-- ============ 2. the aggregate leaver list (mandatory) ============
SELECT t_as(t_u('hrG'));
SET ROLE authenticated;
INSERT INTO t_outputs SELECT 'list_g', jsonb_agg(to_jsonb(x) ORDER BY x.batch_no, x.row_kind) FROM rpc_list_leaver_transfers(t_u('cG')) x;
INSERT INTO t_outputs SELECT 'board_r4', rpc_build_board_report(t_u('cG'), (SELECT m FROM t_m));
RESET ROLE;
SELECT t_assert('list: exact output shape (row_kind, batch_no, team, period_from, period_to, leavers_count, transferred, remediated, reversed, open_balance, label_he, note_he, text_status)',
  (SELECT array_to_string(proargnames[2:], ',') FROM pg_proc WHERE proname = 'rpc_list_leaver_transfers')
      = 'row_kind,batch_no,team,period_from,period_to,leavers_count,transferred,remediated,reversed,open_balance,label_he,note_he,text_status');
SELECT t_assert('list: 4 batch rows, 4 batch_team rows (TA = the whole batch), 1 adjustment_batch, 1 company_total; no person or transfer id',
  (SELECT count(*) FILTER (WHERE e->>'row_kind' = 'batch') = 4 AND count(*) FILTER (WHERE e->>'row_kind' = 'batch_team') = 4
          AND count(*) FILTER (WHERE e->>'row_kind' = 'adjustment_batch') = 1 AND count(*) FILTER (WHERE e->>'row_kind' = 'company_total') = 1
     FROM t_outputs, jsonb_array_elements(j) e WHERE label = 'list_g')
  AND (SELECT t_ids_free(j) AND j::text !~* '(event_id|transfer_event)' FROM t_outputs WHERE label = 'list_g'));
SELECT t_assert('list: every batch / team / adjustment row covers ≥ 10 leavers or transfers',
  (SELECT bool_and((e->>'leavers_count')::int >= 10) FROM t_outputs, jsonb_array_elements(j) e WHERE label = 'list_g'));
SELECT t_assert('list: adjustment_batch of batch 4 = 10 transfers, remediated 5,300, reversed 200',
  (SELECT (e->>'batch_no')::int = 4 AND (e->>'leavers_count')::int = 10 AND (e->>'remediated')::numeric = 5300 AND (e->>'reversed')::numeric = 200
     FROM t_outputs, jsonb_array_elements(j) e WHERE label = 'list_g' AND e->>'row_kind' = 'adjustment_batch'));
SELECT t_assert('list ↔ memo: company_total open_balance = the published memo in the board report (76,500); Σ batch transferred = company transferred (82,000); 40 leavers',
  (SELECT (e->>'open_balance')::numeric = 76500 AND (e->>'transferred')::numeric = 82000 AND (e->>'leavers_count')::int = 40
     FROM t_outputs, jsonb_array_elements(j) e WHERE label = 'list_g' AND e->>'row_kind' = 'company_total')
  AND (SELECT sum((e->>'transferred')::numeric) = 82000 FROM t_outputs, jsonb_array_elements(j) e WHERE label = 'list_g' AND e->>'row_kind' = 'batch')
  AND (SELECT (j->'exported_on_exit'->>'amount')::numeric = 76500 FROM t_outputs WHERE label = 'board_r4'));
SELECT t_assert('list ↔ memo differencing: list total − memo = 0, and every list amount is a sum over ≥ 10 leavers — no single leaver is isolated',
  (SELECT (e->>'open_balance')::numeric - (SELECT (j->'exported_on_exit'->>'amount')::numeric FROM t_outputs WHERE label = 'board_r4') = 0
     FROM t_outputs, jsonb_array_elements(j) e WHERE label = 'list_g' AND e->>'row_kind' = 'company_total')
  AND NOT EXISTS (SELECT 1 FROM t_outputs, jsonb_array_elements(j) e WHERE label = 'list_g' AND (e->>'leavers_count')::int BETWEEN 1 AND 9));
SELECT t_assert('list: the view is audited (leaver_transfers_view by the vp_hr)',
  EXISTS (SELECT 1 FROM access_audit_log WHERE action = 'leaver_transfers_view' AND viewer_id = t_u('hrG')));
SELECT t_as(t_u('cfoG'));
SET ROLE authenticated;
SELECT t_assert('list access: cfo of the company → allowed', (SELECT count(*) > 0 FROM rpc_list_leaver_transfers(t_u('cG'))));
SELECT t_expect_http('list access: cfo of another company → 403', $$SELECT * FROM rpc_list_leaver_transfers(t_u('cS'))$$, 'insufficient_privilege', 403);
RESET ROLE;
SELECT t_as(t_u('empG1'));
SET ROLE authenticated;
SELECT t_expect_http('list access: employee → 403', $$SELECT * FROM rpc_list_leaver_transfers(t_u('cG'))$$, 'insufficient_privilege', 403);
RESET ROLE;
SELECT t_as(t_u('mgrG'));
SET ROLE authenticated;
SELECT t_expect_http('list access: manager → 403', $$SELECT * FROM rpc_list_leaver_transfers(t_u('cG'))$$, 'insufficient_privilege', 403);
RESET ROLE;
SELECT t_as(t_u('chairG'));
SET ROLE authenticated;
SELECT t_expect_http('list access: board chair → 403', $$SELECT * FROM rpc_list_leaver_transfers(t_u('cG'))$$, 'insufficient_privilege', 403);
RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', false) AS no_caller;
SELECT t_expect_http('list access: service call (no caller) → 403', $$SELECT * FROM rpc_list_leaver_transfers(t_u('cG'))$$, 'insufficient_privilege', 403);
SET ROLE anon;
SELECT t_expect_err('list access: anon → no EXECUTE (42501)', $$SELECT * FROM rpc_list_leaver_transfers(t_u('cG'))$$, '42501');
RESET ROLE;
SELECT t_assert('list access: no EXECUTE for service_role / anon (authenticated only)',
  NOT has_function_privilege('service_role', 'rpc_list_leaver_transfers(uuid)', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'rpc_list_leaver_transfers(uuid)', 'EXECUTE'));

-- ---- complementary rule (Karin 31.10, 10 per cell): upgrade-style batches larger than 10 in company H ----
ALTER TABLE happiness_debt_leaver_link DISABLE TRIGGER trg_leaver_memo_on_link;   -- test only: let 13 accumulate
SELECT t_leave('hA' || i, 10) FROM generate_series(1, 10) i;
SELECT t_leave('hB' || i, 10) FROM generate_series(1, 3) i;
ALTER TABLE happiness_debt_leaver_link ENABLE TRIGGER trg_leaver_memo_on_link;
SELECT fn_leaver_memo_try_snapshot(t_u('cH')) IS NOT NULL AS h_batch1;
SELECT t_assert('complement: batch of 13 = HA 10 + HB 3 → HA is NOT shown (the rest, 3, would be computable); only the batch row',
  (SELECT count(*) = 0 FROM fn_leaver_batch_teams((SELECT snapshot_id FROM leaver_memo_snapshot WHERE company_id = t_u('cH') AND batch_no = 1))));
ALTER TABLE happiness_debt_leaver_link DISABLE TRIGGER trg_leaver_memo_on_link;
SELECT t_leave('hA' || i, 10) FROM generate_series(11, 20) i;
SELECT t_leave('hC' || i, 10) FROM generate_series(1, 10) i;
ALTER TABLE happiness_debt_leaver_link ENABLE TRIGGER trg_leaver_memo_on_link;
SELECT fn_leaver_memo_try_snapshot(t_u('cH')) IS NOT NULL AS h_batch2;
SELECT t_assert('complement: batch of 20 = HA 10 + HC 10 → both teams shown (rest 0)',
  (SELECT string_agg(team || '=' || leavers, ',' ORDER BY team) = 'HA=10,HC=10'
     FROM fn_leaver_batch_teams((SELECT snapshot_id FROM leaver_memo_snapshot WHERE company_id = t_u('cH') AND batch_no = 2))));
SELECT t_assert('complement (unit): rows {a 12, b 10, c 2}, min 10 → only a shown (rest 12); {a 5, b 5, c 1}, min 5 → only a shown (rest 6)',
  fn_complement_safe_keys('[{"key":"a","n":12},{"key":"b","n":10},{"key":"c","n":2}]', 24, 10) = ARRAY['a']
  AND fn_complement_safe_keys('[{"key":"a","n":5},{"key":"b","n":5},{"key":"c","n":1}]', 11, 5) = ARRAY['a']
  AND fn_complement_safe_keys('[{"key":"a","n":5},{"key":"b","n":5}]', 10, 5) = ARRAY['a', 'b']);

-- ---- no 2-transfer rule: leavers are DISTINCT departed employees (company J) ----
SELECT t_leave('jL' || i, 10) FROM generate_series(1, 9) i;
UPDATE users SET employment_ended_at = NULL WHERE user_id = t_u('jL1');
UPDATE users SET employment_ended_at = clock_timestamp() WHERE user_id = t_u('jL1');
SELECT t_assert('no 2-transfer rule: 10 transfers from 9 people (one left twice) → no batch',
  (SELECT count(*) = 10 FROM happiness_debt_events WHERE company_id = t_u('cJ') AND event_type = 'leaver_transfer')
  AND NOT EXISTS (SELECT 1 FROM leaver_memo_snapshot WHERE company_id = t_u('cJ')));
SELECT t_assert('no 2-transfer rule: no "2" threshold in the batching code (only fn_leaver_batch_min = 10)',
  fn_leaver_batch_min() = 10
  AND NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname IN ('fn_leaver_memo_try_snapshot', 'fn_leaver_batch_teams', 'rpc_list_leaver_transfers')
                   AND prosrc ~ '>=\s*2\M'));

INSERT INTO shop_item_catalog (item_id, display_name, name_he, category, provider, tier, price_coins, cosmetic_only) VALUES
  ('concert_pass', 'Concert pass', 'כרטיס להופעה', 'experience', 'CultureHub', 'premium', 60.0, false),
  ('coffee_card', 'Coffee card', 'כרטיס קפה', 'gift_card', 'CafeNet', 'custom', 7.5, false),
  ('spa_massage', 'Spa massage', 'עיסוי', 'health_wellbeing', 'WellSpa Ltd', 'premium', 45.0, false),
  ('course_book', 'Course book', 'ספר קורס', 'learning', 'AcadPress', 'custom', 15.5, false)
ON CONFLICT (item_id) DO NOTHING;
-- ============ 3. A-3 (Karin 31.10): ILS estimate = average cost of a redeemed spoon, 3-month MA, ≥ 10 purchases ============
INSERT INTO everstore_item_cost (item_id, internal_cost_ils) VALUES ('coffee_card', 30), ('course_book', 62)
  ON CONFLICT (item_id) DO UPDATE SET internal_cost_ils = EXCLUDED.internal_cost_ils;
SELECT t_buy('empS' || i, 'coffee_card', clock_timestamp() - interval '5 minutes') FROM generate_series(1, 5) i;
SELECT t_buy('empS' || i, 'course_book', clock_timestamp() - interval '5 minutes') FROM generate_series(6, 9) i;
SELECT t_buy('empS12', 'spa_massage', clock_timestamp() - interval '4 months');   -- outside the window, no cost
SELECT t_as(t_u('cfoS'));
SET ROLE authenticated;
INSERT INTO t_outputs SELECT 'spoon_est_9', rpc_get_redeemed_spoon_cost_estimate(t_u('cS'));
SELECT t_assert('A-3: 9 purchases in the window → no value, exactly "אין עדיין מספיק מימושים לאומדן"',
  (SELECT j->'ils_per_redeemed_spoon' = 'null'::jsonb AND j->>'display_he' = 'אין עדיין מספיק מימושים לאומדן'
          AND (j->>'purchases_count')::int = 9 FROM t_outputs WHERE label = 'spoon_est_9'));
SELECT t_assert('A-3: …and the liability shows no ILS estimate with the same message',
  (SELECT j->'ils_estimate' = 'null'::jsonb AND j->>'display_he' = 'אין עדיין מספיק מימושים לאומדן'
     FROM (SELECT rpc_get_open_golden_spoons_liability(t_u('cS')) j) x));
RESET ROLE;
SELECT t_buy('empS10', 'course_book', clock_timestamp() - interval '5 minutes');
SELECT t_as(t_u('hrS'));
SET ROLE authenticated;
INSERT INTO t_outputs SELECT 'spoon_est_10', rpc_get_redeemed_spoon_cost_estimate(t_u('cS'));
SELECT t_assert('A-3: the 10th purchase → value = Σ cost ÷ Σ spoons = (5×30 + 5×62) ÷ (5×7.5 + 5×15.5) = 4 (vp_hr reads it)',
  (SELECT (j->>'ils_per_redeemed_spoon')::numeric = 4 AND j->>'status' = 'ok' AND j->'display_he' = 'null'::jsonb
          AND (j->>'purchases_count')::int = 10 FROM t_outputs WHERE label = 'spoon_est_10'));
RESET ROLE;
SELECT t_assert('A-3: the window is the current month + the 2 previous ones (a 4-month-old purchase is not counted)',
  fn_spoon_estimate_window_from(t_u('cS'), DATE '2026-10-31') = DATE '2026-08-01'
  AND (fn_redeemed_spoon_cost_3m(t_u('cS'), fn_agent_local_ts(t_u('cS'), clock_timestamp())::date)->>'purchases_count')::int = 10);
SELECT t_buy('empS11', 'concert_pass', clock_timestamp() - interval '5 minutes');   -- item without an internal cost
SELECT t_assert('A-3: a purchase whose item has no internal cost → "חסר: everstore_item_cost.internal_cost_ils"',
  (SELECT j->>'status' = 'missing' AND j->>'display_he' = 'חסר: everstore_item_cost.internal_cost_ils' AND j->'value' = 'null'::jsonb
     FROM (SELECT fn_redeemed_spoon_cost_3m(t_u('cS'), fn_agent_local_ts(t_u('cS'), clock_timestamp())::date) j) x));
INSERT INTO everstore_item_cost (item_id, internal_cost_ils) VALUES ('concert_pass', 240)
  ON CONFLICT (item_id) DO UPDATE SET internal_cost_ils = EXCLUDED.internal_cost_ils;
SELECT t_assert('A-3: spoon_cost_ils is deprecated, locked and not used by any function (kept, not deleted)',
  (SELECT value_status = 'not_defined' AND is_locked FROM agent_settings WHERE company_id IS NULL AND setting_key = 'spoon_cost_ils')
  AND (SELECT value_text = 'avg_redeemed' AND is_locked FROM agent_settings WHERE company_id IS NULL AND setting_key = 'liability_method')
  AND NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                   WHERE n.nspname = 'public' AND p.proname NOT LIKE 't\_%' AND p.prosrc ~ '''spoon_cost_ils'''));
-- permissions (estimate + liability): cfo / vp_hr only
SELECT t_as(t_u('cfoS'));
SET ROLE authenticated;
SELECT t_assert('A-3 access: cfo → the estimate and the liability', rpc_get_redeemed_spoon_cost_estimate(t_u('cS')) IS NOT NULL
  AND rpc_get_open_golden_spoons_liability(t_u('cS')) IS NOT NULL);
RESET ROLE;
SELECT t_as(t_u('empS1'));
SET ROLE authenticated;
SELECT t_expect_http('A-3 access: employee → 403 (estimate)', $$SELECT rpc_get_redeemed_spoon_cost_estimate(t_u('cS'))$$, 'insufficient_privilege', 403);
SELECT t_expect_http('A-3 access: employee → 403 (liability)', $$SELECT rpc_get_open_golden_spoons_liability(t_u('cS'))$$, 'insufficient_privilege', 403);
RESET ROLE;
SELECT t_as(t_u('mgrS'));
SET ROLE authenticated;
SELECT t_expect_http('A-3 access: manager → 403 (estimate)', $$SELECT rpc_get_redeemed_spoon_cost_estimate(t_u('cS'))$$, 'insufficient_privilege', 403);
SELECT t_expect_http('A-3 access: manager → 403 (liability)', $$SELECT rpc_get_open_golden_spoons_liability(t_u('cS'))$$, 'insufficient_privilege', 403);
RESET ROLE;
SELECT t_as(t_u('chairS'));
SET ROLE authenticated;
SELECT t_expect_http('A-3 access: board chair → 403 (estimate)', $$SELECT rpc_get_redeemed_spoon_cost_estimate(t_u('cS'))$$, 'insufficient_privilege', 403);
SELECT t_expect_http('A-3 access: board chair → 403 (liability)', $$SELECT rpc_get_open_golden_spoons_liability(t_u('cS'))$$, 'insufficient_privilege', 403);
RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', false) AS no_caller;
SELECT t_expect_http('A-3 access: service call (no caller) → 403 (estimate)', $$SELECT rpc_get_redeemed_spoon_cost_estimate(t_u('cS'))$$, 'insufficient_privilege', 403);
SELECT t_expect_http('A-3 access: service call (no caller) → 403 (liability)', $$SELECT rpc_get_open_golden_spoons_liability(t_u('cS'))$$, 'insufficient_privilege', 403);
SET ROLE anon;
SELECT t_expect_err('A-3 access: anon → no EXECUTE (estimate)', $$SELECT rpc_get_redeemed_spoon_cost_estimate(t_u('cS'))$$, '42501');
SELECT t_expect_err('A-3 access: anon → no EXECUTE (liability)', $$SELECT rpc_get_open_golden_spoons_liability(t_u('cS'))$$, '42501');
RESET ROLE;
SELECT t_assert('A-3 access: service_role has no EXECUTE on the estimate or the liability',
  NOT has_function_privilege('service_role', 'rpc_get_redeemed_spoon_cost_estimate(uuid)', 'EXECUTE')
  AND NOT has_function_privilege('service_role', 'rpc_get_open_golden_spoons_liability(uuid)', 'EXECUTE'));
SELECT t_assert('A-3: no employee-facing output carries ILS per spoon — the only client RPCs reaching the per-spoon cost are the two strict cfo / vp_hr ones; the board report holds no per-spoon key',
  (SELECT array_agg(p.proname::text ORDER BY p.proname) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname LIKE 'rpc\_%' AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
      AND p.prosrc ~ '(fn_redeemed_spoon_cost_3m|fn_avg_redeemed_spoon_cost_ils)')
  = ARRAY['rpc_get_open_golden_spoons_liability', 'rpc_get_redeemed_spoon_cost_estimate']
  AND (SELECT bool_and(p.prosrc ~ 'fn_assert_finance_viewer_strict') FROM pg_proc p
        WHERE p.proname IN ('rpc_get_open_golden_spoons_liability', 'rpc_get_redeemed_spoon_cost_estimate'))
  AND (SELECT bool_and(j::text !~* '(ils_per|per_spoon|spoon_cost|cost_per)') FROM t_outputs WHERE label LIKE 'board_%'));

-- ============ 4. verification levels 0–4 (Part A1, computed) ============
SELECT t_as(t_u('cfoG'));
SET ROLE authenticated;
SELECT t_expect_http('A1: manual tier input → 422 verification_level_is_computed',
  $$SELECT rpc_put_metric_assurance(t_u('cG'), 'chr_real_ebitda', 4)$$, 'verification_level_is_computed', 422);
SELECT t_expect_http('A1: unknown metric → 400 invalid_verification_evidence',
  $$SELECT rpc_put_metric_verification_evidence(t_u('cG'), 'nope', (SELECT m FROM t_m), NULL, true, true, true)$$, 'invalid_verification_evidence', 400);
RESET ROLE;
SELECT t_assert('A1: no evidence → level 0', fn_verification_level(t_u('cG'), 'absences', (SELECT m FROM t_m)) = 0);
SET ROLE authenticated;
SELECT t_assert('A1: population / timing / scoring identified, no control → 1',
  (rpc_put_metric_verification_evidence(t_u('cG'), 'absences', (SELECT m FROM t_m), NULL, true, true, true)->>'tier')::int = 1);
SELECT t_assert('A1: an industry comparison never raises the level (still 1)',
  (rpc_put_metric_verification_evidence(t_u('cG'), 'absences', (SELECT m FROM t_m), NULL, true, true, true, false, false, 'none', NULL, false, true)->>'tier')::int = 1);
SELECT t_assert('A1: one control (confidentiality procedure) → 2',
  (rpc_put_metric_verification_evidence(t_u('cG'), 'absences', (SELECT m FROM t_m), NULL, true, true, true, false, true)->>'tier')::int = 2);
SELECT t_assert('A1: limited external audit to an identified standard applying to the metric → 3',
  (rpc_put_metric_verification_evidence(t_u('cG'), 'absences', (SELECT m FROM t_m), NULL, true, true, true, false, false, 'limited', 'ISAE 3000', true)->>'tier')::int = 3);
SELECT t_assert('A1: full external audit (same) → 4',
  (rpc_put_metric_verification_evidence(t_u('cG'), 'absences', (SELECT m FROM t_m), NULL, true, true, true, false, false, 'full', 'ISAE 3000', true)->>'tier')::int = 4);
SELECT t_assert('A1: a full audit without an identified standard, or not applying to the metric itself → not 3 / 4 (1)',
  (rpc_put_metric_verification_evidence(t_u('cG'), 'absences', (SELECT m FROM t_m), NULL, true, true, true, false, false, 'full', NULL, true)->>'tier')::int = 1
  AND (rpc_put_metric_verification_evidence(t_u('cG'), 'absences', (SELECT m FROM t_m), NULL, true, true, true, false, false, 'full', 'ISAE 3000', false)->>'tier')::int = 1);
SELECT t_assert('A1: a questionnaire metric without the questionnaire identified → 0',
  (rpc_put_metric_verification_evidence(t_u('cG'), 'ihs_company', (SELECT m FROM t_m), false, true, true, true)->>'tier')::int = 0);
SELECT t_assert('A1 + B2: PCQ-12 (locked, no company change) → the separate measuring body counts as a control → 2',
  (rpc_put_metric_verification_evidence(t_u('cG'), 'tps12_company', (SELECT m FROM t_m), true, true, true, true)->>'tier')::int = 2);
RESET ROLE;
SELECT t_assert('A1: the label is Karin''s text (טיוטה)',
  (SELECT j->>'label_he' = 'רמה 2 — לפחות בקרה אחת: שיעור דיווח, גוף מודד נפרד או נוהל סודיות' AND j->>'text_status' = 'טיוטה'
     FROM (SELECT fn_verification_json(t_u('cG'), 'tps12_company', (SELECT m FROM t_m)) j) x));
-- B2: a company-side change caps the metric at level 1 for that month (a past month, so later checks are unaffected)
INSERT INTO metric_verification_evidence (company_id, metric_key, period_month, questionnaire_identified, population_identified,
                                          timing_identified, scoring_identified, audit_scope, audit_standard, audit_applies_to_metric)
VALUES (t_u('cG'), 'tps12_company', fn_month_shift((SELECT m FROM t_m), -3), true, true, true, true, 'full', 'ISAE 3000', true);
SELECT t_assert('B2: full audit, no change → 4 in that month', fn_verification_level(t_u('cG'), 'tps12_company', fn_month_shift((SELECT m FROM t_m), -3)) = 4);
INSERT INTO measurement_change_log (company_id, questionnaire_code, change_kind, changed_at)
VALUES (t_u('cG'), 'TPS-12', 'timing', fn_agent_day_start(t_u('cG'), fn_month_shift((SELECT m FROM t_m), -3)) + interval '3 days');
SELECT t_assert('B2: a logged company change of timing in that month caps it at 1, even with a full audit',
  fn_verification_level(t_u('cG'), 'tps12_company', fn_month_shift((SELECT m FROM t_m), -3)) = 1
  AND NOT fn_separate_body_control(t_u('cG'), 'tps12_company', fn_month_shift((SELECT m FROM t_m), -3)));
-- B2: changes made by vp_hr to an unlocked questionnaire are logged
SELECT t_as(t_u('hrG'));
SET ROLE authenticated;
SELECT code FROM rpc_upsert_questionnaire_definition('CUST-G', 'Team pulse', 'דופק צוות', 'weekly', NULL, 3, 1, 5);
SELECT code FROM rpc_upsert_questionnaire_definition('CUST-G', 'Team pulse', 'דופק צוות', 'monthly', NULL, 3, 1, 5);
SELECT code FROM rpc_upsert_questionnaire_definition('CUST-G', 'Team pulse', 'דופק הצוות', 'monthly', NULL, 3, 1, 5);
SELECT (rpc_put_questionnaire_items('CUST-G', ARRAY['שאלה 1', 'שאלה 2', 'שאלה 3']))->>'version' AS cust_version;
SELECT t_expect_http('B2: vp_hr cannot change the wording of a locked instrument (PCQ-12) → 403 questionnaire_locked',
  $$SELECT rpc_put_questionnaire_items('PCQ-12', ARRAY['a','b','c','d','e','f','g','h','i','j','k','l'])$$, 'questionnaire_locked', 403);
RESET ROLE;
SELECT t_assert('B2: creation is not a change; the timing change, the name change and the wording version are logged (timing 1, wording 2)',
  (SELECT count(*) FILTER (WHERE change_kind = 'timing') = 1 AND count(*) FILTER (WHERE change_kind = 'wording') = 2
     FROM measurement_change_log WHERE questionnaire_code = 'CUST-G' AND company_id = t_u('cG')));
SELECT t_assert('B2: the measuring body (service) enters the PCQ-12 wording — not logged as a company change',
  (rpc_put_questionnaire_items('PCQ-12', ARRAY['פריט 1','פריט 2','פריט 3','פריט 4','פריט 5','פריט 6','פריט 7','פריט 8','פריט 9','פריט 10','פריט 11','פריט 12'])->>'version')::int = 1
  AND NOT EXISTS (SELECT 1 FROM measurement_change_log WHERE questionnaire_code = 'PCQ-12'));
SELECT t_expect_err('measurement_change_log is WORM', $$DELETE FROM measurement_change_log$$, 'ledger_immutable');

-- ============ 5. 'תיק אימות' (Part A2) ============
SELECT t_as(t_u('cfoG'));
SET ROLE authenticated;
INSERT INTO t_outputs SELECT 'dossier_pcq_before', rpc_get_verification_dossier(t_u('cG'), 'pcq12_company', (SELECT m FROM t_m));
SELECT jsonb_typeof(rpc_put_payroll_population(t_u('cG'), (SELECT m FROM t_m), 60, '{"leave": 2, "contractors": 3}')) AS payroll;
SELECT jsonb_typeof(rpc_add_org_event(t_u('cG'), (SELECT m FROM t_m) + 2, 'הודעה על ארגון מחדש')) AS org_event;
SELECT t_expect_http('A2: an org event without a description → 400', $$SELECT rpc_add_org_event(t_u('cG'), (SELECT m FROM t_m), ' ')$$, 'invalid_org_event', 400);
INSERT INTO t_outputs SELECT 'dossier_pcq', rpc_get_verification_dossier(t_u('cG'), 'pcq12_company', (SELECT m FROM t_m));
INSERT INTO t_outputs SELECT 'dossier_chr', rpc_get_verification_dossier(t_u('cG'), 'chr_real_ebitda', (SELECT m FROM t_m));
RESET ROLE;
SELECT t_assert('A2: before the inputs, missing fields say so (payroll "חסר: payroll_population_input.payroll_headcount")',
  (SELECT j->'population'->>'display_he' = 'חסר: payroll_population_input.payroll_headcount'
          AND j->'timing'->>'display_he' = 'לא תועדו אירועים ארגוניים בתקופה' FROM t_outputs WHERE label = 'dossier_pcq_before'));
SELECT t_assert('A2: the dossier holds the questionnaire wording (version 1, 12 items), the measured population vs payroll, timing vs org events',
  (SELECT (j->'questionnaire'->>'version')::int = 1 AND jsonb_array_length(j->'questionnaire'->'items') = 12
          AND (j->'questionnaire'->>'changed_vs_previous_period')::boolean
          AND (j->'population'->>'payroll_headcount')::int = 60
          AND (j->'population'->>'difference')::int = 60 - (j->'population'->>'measured_population')::int
          AND (j->'population'->'exceptions'->>'contractors')::int = 3
          AND jsonb_array_length(j->'timing'->'org_events') = 1 AND j->'timing'->>'frequency' = 'monthly'
     FROM t_outputs WHERE label = 'dossier_pcq'));
SELECT t_assert('A2: reporting (מדווחים בפועל 12, rate, range; non-reporters not imputed), independence (גוף מודד CHR-ETRS), scoring, Golden Spoons value (10)',
  (SELECT (j->'reporting'->>'reporters_count')::int = 12 AND (j->'reporting'->>'response_rate')::numeric > 0
          AND j->'reporting' ? 'range_low' AND NOT (j->'reporting') ? 'text_status'
          AND j->'independence'->>'measuring_body' = 'CHR-ETRS' AND j->'independence'->>'label_he' = 'גוף מודד'
          AND NOT (j->'independence'->>'company_can_change_timing_or_wording')::boolean
          AND (j->'independence'->>'counts_as_control')::boolean
          AND j->'scoring'->>'scoring_method' = 'pcq12' AND (j->'scoring'->>'consistent')::boolean
          AND (j->'golden_spoons'->>'value_at_period_start')::numeric = 10
     FROM t_outputs WHERE label = 'dossier_pcq'));
SELECT t_assert('A2: a non-questionnaire metric → questionnaire sections "לא רלוונטי: המדד אינו מבוסס שאלון"',
  (SELECT j->'questionnaire'->>'display_he' = 'לא רלוונטי: המדד אינו מבוסס שאלון' FROM t_outputs WHERE label = 'dossier_chr'));
SELECT t_assert('A2: a questionnaire without entered wording → "להשלמה: נוסח השאלות לא הוזן"',
  fn_dossier_wording(t_u('cG'), 'IHS', (SELECT m FROM t_m))->>'display_he' = 'להשלמה: נוסח השאלות לא הוזן');
SELECT t_as(t_u('empG1'));
SET ROLE authenticated;
SELECT t_assert('J-70 (Karin''s exact text 31.10): the dossier''s non-reporting text, with no "טיוטה" marking',
  (SELECT j->'reporting'->>'non_reporting_handling_he'
            = 'מי שלא דיווח לא נספר: אין השלמה או הערכה של נתונים חסרים. הטווח שמוצג ליד הציון מראה כמה הוא יכול להשתנות בגללם.'
          AND NOT (j->'reporting') ? 'text_status' FROM t_outputs WHERE label = 'dossier_pcq'));
SELECT t_expect_http('A2: employee → 403 on the dossier', $$SELECT rpc_get_verification_dossier(t_u('cG'), 'pcq12_company', (SELECT m FROM t_m))$$, 'insufficient_privilege', 403);
RESET ROLE;

-- ============ 6. pay / bonus linkage (Part A3) ============
SELECT t_as(t_u('cfoG'));
SET ROLE authenticated;
SELECT (rpc_put_metric_pay_linkage(t_u('cG'), 'ihs_company', true, false))->>'used_for_pay' AS linked;
SELECT t_expect_http('A3: a metric used for pay at level 0 (IHS) → the report is not published (422 pay_linked_metric_below_level_2)',
  $$SELECT rpc_build_board_report(t_u('cG'), (SELECT m FROM t_m))$$, 'pay_linked_metric_below_level_2', 422);
SELECT (rpc_put_metric_verification_evidence(t_u('cG'), 'ihs_company', (SELECT m FROM t_m), true, true, true, true, true))->>'tier' AS ihs_tier;
SELECT (rpc_put_metric_pay_linkage(t_u('cG'), 'governance', false, true))->>'used_for_manager_bonus' AS bonus;
SELECT t_expect_http('A3: …also a metric used for manager bonuses at level 0 (governance) → 422',
  $$SELECT rpc_build_board_report(t_u('cG'), (SELECT m FROM t_m))$$, 'pay_linked_metric_below_level_2', 422);
SELECT (rpc_put_metric_pay_linkage(t_u('cG'), 'governance', false, false))->>'used_for_manager_bonus' AS unlinked;
INSERT INTO t_outputs SELECT 'board_r5', rpc_build_board_report(t_u('cG'), (SELECT m FROM t_m));
SELECT t_expect_http('A3: invalid linkage → 400', $$SELECT rpc_put_metric_pay_linkage(t_u('cG'), 'ihs_company', NULL, true)$$, 'invalid_pay_linkage', 400);
RESET ROLE;
SELECT t_assert('A3: IHS at level 2 → the report publishes; the pay use is shown per metric',
  (SELECT (j->'verification_levels'->'ihs_company'->>'tier')::int = 2 AND (j->'verification_levels'->'ihs_company'->>'used_for_pay')::boolean
          AND NOT (j->'verification_levels'->'governance'->>'used_for_manager_bonus')::boolean
     FROM t_outputs WHERE label = 'board_r5'));
SELECT t_expect_err('metric_pay_linkage is WORM', $$UPDATE metric_pay_linkage SET used_for_pay = false$$, 'ledger_immutable');

-- ============ 7. the board report v1.6.19 ============
SELECT t_assert('report: computed levels for all 17 board metrics; no manual assurance_tier',
  (SELECT (SELECT count(*) FROM jsonb_object_keys(j->'verification_levels')) = 17 AND NOT j ? 'assurance_tier' FROM t_outputs WHERE label = 'board_r5'));
SELECT t_assert('report: the dossier of each questionnaire metric is kept with the report (3 per build, WORM)',
  (SELECT (SELECT count(*) FROM jsonb_object_keys(j->'verification_dossiers')) = 3 FROM t_outputs WHERE label = 'board_r5')
  AND (SELECT count(*) = 3 * 5 FROM verification_dossier WHERE company_id = t_u('cG')));
SELECT t_expect_err('verification_dossier is WORM', $$UPDATE verification_dossier SET dossier = '{}'$$, 'ledger_immutable');
SELECT t_assert('report: layers investment / adoption / outcomes / governance with labels and levels; source = the World paper; measuring body',
  (SELECT j->'layers'->'investment_activity'->>'label_he' = 'השקעה ופעילות' AND j->'layers'->'adoption_usage'->>'label_he' = 'אימוץ'
          AND j->'layers'->'outcomes'->>'label_he' = 'תוצאות' AND j->'layers'->'governance'->>'label_he' = 'ממשל'
          AND j->'layers'->'outcomes'->'verification_level' ? 'tier'
          AND j->'layers'->>'structure_source_doi' = '10.3390/world7050077'
          AND j->'measuring_body'->>'name' = 'CHR-ETRS' AND j->'measuring_body'->>'label_he' = 'גוף מודד'
     FROM t_outputs WHERE label = 'board_r5'));
SELECT t_assert('J-65 (approved 31.10): the causal note has no "טיוטה" marking; "מדד ניהולי חלופי, לא רווח חשבונאי" kept',
  (SELECT j->'causal_note' = jsonb_build_object('note_he', 'הדוח מציג השקעה, אימוץ ותוצאות זה לצד זה; הוא אינו קובע שההשקעה גרמה לתוצאות.')
          AND NOT (j->'causal_note') ? 'text_status' AND j->'chr_real_ebitda'->>'definition_he' = 'מדד ניהולי חלופי, לא רווח חשבונאי'
     FROM t_outputs WHERE label = 'board_r5'));
SELECT t_assert('report B4: CHR Real EBITDA carries Karin''s text "מדד ניהולי חלופי שמציג קשר, לא השפעה סיבתית מבודדת" (טיוטה)',
  (SELECT j->'chr_real_ebitda'->>'note_he' = 'מדד ניהולי חלופי שמציג קשר, לא השפעה סיבתית מבודדת'
          AND j->'chr_real_ebitda'->>'text_status' = 'טיוטה'
     FROM t_outputs WHERE label = 'board_r5'));
SELECT t_assert('report: adoption is never called success ("הצלחה" nowhere in any report)',
  (SELECT bool_and(strpos(j::text, 'הצלחה') = 0) FROM t_outputs WHERE label LIKE 'board_%'));
SELECT t_as(t_u('chairG'));
SET ROLE authenticated;
SELECT t_assert('report: the board chair reads the published report (with the layers)',
  (SELECT rpc_get_board_report(t_u('cG'), (SELECT m FROM t_m)) ? 'layers'));
RESET ROLE;

-- ---- sources (Karin 31.10: 5 entries, all DOIs checked) ----
SELECT t_assert('sources: exactly 5 entries with these DOIs and statuses',
  (SELECT jsonb_array_length(j->'sources') = 5
          AND (SELECT string_agg(s->>'doi' || '=' || (s->>'status_he'), ' | ' ORDER BY ord) FROM jsonb_array_elements(j->'sources') WITH ORDINALITY x(s, ord))
              = '10.1080/13571516.2025.2599785=פורסם | 10.1086/681096=פורסם | 10.1287/mnsc.2023.4766=פורסם | 10.3390/world7050077=פורסם | 10.13140/rg.2.2.35568.62722=טיוטה'
     FROM t_outputs WHERE label = 'board_r5'));
SELECT t_assert('sources: the exact IJEB citation, year 2026 (one constant), DOI unchanged',
  fn_chr_paper_year() = 2026
  AND (SELECT j->'sources'->0->>'citation' = 'Tsaban, S., & Shavit, T. (2026). Corporate happiness responsibility (CHR) – changing the role of corporations. International Journal of the Economics of Business, 33(1), 123–160. https://doi.org/10.1080/13571516.2025.2599785'
          AND j->'sources'->0->>'source' = 'צבאן ושביט 2026' FROM t_outputs WHERE label = 'board_r5'));
SELECT t_assert('sources: the exact World citation (published, peer reviewed)',
  (SELECT j->'sources'->3->>'citation' = 'Tsaban, S., & Shavit, T. (2026). Unveiling the Value of Happiness: Why Reporting on Corporate Investments in Employee Happiness Matters. World, 7(5), 77. https://doi.org/10.3390/world7050077 — פורסם, עבר ביקורת עמיתים'
     FROM t_outputs WHERE label = 'board_r5'));
SELECT t_assert('sources: Oswald, Proto & Sgroi 2015 (J. Labor Econ. 33(4):789–822) and Bellet, De Neve & Ward 2024 (Management Science 70(3):1656–1679)',
  (SELECT j->'sources'->1->>'citation' LIKE 'Oswald, A. J., Proto, E., & Sgroi, D. (2015). Happiness and productivity. Journal of Labor Economics, 33(4), 789–822.%'
          AND j->'sources'->2->>'citation' LIKE 'Bellet, C. S., De Neve, J.-E., & Ward, G. (2024). Does employee happiness have an impact on productivity? Management Science, 70(3), 1656–1679.%'
     FROM t_outputs WHERE label = 'board_r5'));
SELECT t_assert('sources: no 2025 author-year for the IJEB paper outside the DOI string; no unverified-DOI note',
  (SELECT bool_and(replace(j::text, '13571516.2025.2599785', '') !~ '(Shavit|שביט)[^0-9]{0,40}2025' AND strpos(j::text, 'לא ' || 'אומתו') = 0 AND NOT j ? 'sources_note_he')
     FROM t_outputs WHERE label LIKE 'board_%')
  AND NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public'
                   AND replace(p.prosrc, '13571516.2025.2599785', '') ~ '(Shavit|שביט)[^0-9]{0,40}2025'));
-- A-10 (Karin 31.10): the binding appendix text, EXACT (en dashes, a line break between the two sentences).
CREATE TEMP TABLE t_binding AS SELECT 'מתאם בין רווחת עובדים לביצועים: r = 0.37 (רווח בר-סמך 95%: 0.26–0.48; יציב בין 0.31 ל-0.39 בבדיקות רגישות).
הקשר הישיר לרווחיות חלש יותר: 0.14–0.16. המסלול החזק ביותר עובר דרך הלקוחות. (טיוטה)'::text AS txt;
SELECT t_assert('A-10: the published report carries Karin''s binding text exactly (sources_note.text_he, with the line break)',
  (SELECT j->'sources_note'->>'text_he' = (SELECT txt FROM t_binding) FROM t_outputs WHERE label = 'board_r5')
  AND fn_board_binding_text_he() = (SELECT txt FROM t_binding)
  AND position(chr(10) IN fn_board_binding_text_he()) > 0);
SELECT t_assert('A-10: the binding text is tied to "Does Employee Well-Being Pay?" (doi 10.13140/rg.2.2.35568.62722, טיוטה)',
  (SELECT j->'sources_note'->>'doi' = '10.13140/rg.2.2.35568.62722' AND j->'sources_note'->>'status_he' = 'טיוטה'
          AND j->'sources_note'->>'text_status' = 'טיוטה' AND j->'sources_note'->>'citation' LIKE '%Does Employee Well-Being Pay?%'
          AND (j->'sources'->4->>'doi') = '10.13140/rg.2.2.35568.62722'
     FROM t_outputs WHERE label = 'board_r5'));
-- Count of a pattern in a text (helper for the A-10 checks).
CREATE OR REPLACE FUNCTION t_count(p_text text, p_pat text) RETURNS int LANGUAGE sql IMMUTABLE AS
  $$ SELECT (length(p_text) - length(replace(p_text, p_pat, ''))) / length(p_pat) $$;
SELECT t_assert('A-10: every "r = 0.37" in every published report is inside the full binding text (count r = 0.37 = count full text = 1)',
  (SELECT bool_and(t_count(j::text, 'r = 0.37') = t_count(j::text, (SELECT to_jsonb(txt)::text FROM t_binding) )
                   AND t_count(j::text, 'r = 0.37') = 1)
     FROM t_outputs WHERE label LIKE 'board_r%'));
SELECT t_assert('A-10: 0.37 is never shown alone: without sources_note no report holds 0.37 (no "link to profit" wording)',
  (SELECT bool_and(strpos((j - 'sources_note')::text, '0.37') = 0) FROM t_outputs WHERE label LIKE 'board_%')
  AND (SELECT bool_and(strpos(j::text, '0.37') = 0) FROM t_outputs WHERE label NOT LIKE 'board_r%'));
SELECT t_assert('A-10: 0.37 always next to 0.14–0.16 (same sentence block of the binding text)',
  position('0.14–0.16' IN fn_board_binding_text_he()) > position('r = 0.37' IN fn_board_binding_text_he())
  AND position('r = 0.37' IN fn_board_binding_text_he()) > 0);
SELECT t_assert('A-10: in the code only fn_board_binding_text_he holds "r = 0.37"; only fn_board_sources_note uses it',
  NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public'
               AND p.prosrc ~ 'r\s*=\s*0\.37' AND p.proname <> 'fn_board_binding_text_he')
  AND NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public'
               AND p.prosrc LIKE '%fn_board_binding_text_he%' AND p.proname <> 'fn_board_sources_note'));
SELECT t_assert('A-10: the burnout B_t weight is not linked to the binding text (burnout / B_t functions never use it)',
  NOT EXISTS (SELECT 1 FROM pg_proc WHERE (proname LIKE '%burnout%' OR proname = 'fn_b_t' OR proname LIKE '%_b_t%')
               AND (prosrc LIKE '%fn_board_binding_text_he%' OR prosrc LIKE '%fn_board_sources_note%')));
SELECT t_assert('A-10: the burnout overtime weight 0.37 (Karin 20.10) is unchanged: B_t(S 5, O 10 h, D 1) = 0.41 + 0.37 = 0.78',
  fn_b_t(5, 10, 1) = 0.78 AND fn_b_t(1, 10, 1) = 0.37);

-- ============ 8. burnout recommendation (Part A4) ============
SELECT t_assert('A4: the only recommendation is "לבדוק את תנאי העבודה בצוות" (טיוטה), only when the risk rises',
  fn_burnout_recommendation(true)->>'recommendation_he' = 'לבדוק את תנאי העבודה בצוות'
  AND fn_burnout_recommendation(true)->>'recommendation_text_status' = 'טיוטה'
  AND fn_burnout_recommendation(false)->'recommendation_he' = 'null'::jsonb);
SELECT t_assert('A4: the guard refuses more feedback / documentation / an improvement plan / PIP (Hebrew and English)',
  NOT fn_recommendation_allowed('לתת יותר משוב') AND NOT fn_recommendation_allowed('להגביר תיעוד')
  AND NOT fn_recommendation_allowed('לבנות תוכנית שיפור') AND NOT fn_recommendation_allowed('open a PIP')
  AND NOT fn_recommendation_allowed('more feedback') AND NOT fn_recommendation_allowed('performance improvement plan')
  AND fn_recommendation_allowed(fn_burnout_recommendation_he()));
-- J-52 (approved 31.10): one test per new forbidden phrase; the old phrases stay forbidden (above).
SELECT t_assert('J-52: "שימוע" is refused', NOT fn_recommendation_allowed('לזמן את העובד לשימוע'));
SELECT t_assert('J-52: "שיחת בירור" is refused', NOT fn_recommendation_allowed('לקיים שיחת בירור עם העובדים'));
SELECT t_assert('J-52: "התראה בכתב" is refused', NOT fn_recommendation_allowed('לתת התראה בכתב'));
SELECT t_assert('J-52: "מעקב ביצועים" is refused', NOT fn_recommendation_allowed('להדק מעקב ביצועים'));
SELECT t_assert('J-52: the agent''s own recommendation is still allowed and the guard is the one the agent uses',
  fn_recommendation_allowed('לבדוק את תנאי העבודה בצוות')
  AND (SELECT prosrc ~ 'fn_recommendation_forbidden_pattern' FROM pg_proc WHERE proname = 'fn_recommendation_allowed'));
SELECT t_assert('A4: the burnout trend RPC carries the recommendation block',
  (SELECT prosrc ~ 'fn_burnout_recommendation\(v_rising\)' FROM pg_proc WHERE proname = 'rpc_get_burnout_trend'));

-- ============ 9. social events (Part A5) ============
SELECT count(*) AS ledger_before INTO TEMP t_led FROM golden_spoons_ledger;
SELECT t_as(t_u('hrS'));
SET ROLE authenticated;
INSERT INTO t_outputs SELECT 'social_create', rpc_create_social_event(t_u('cS'), 'ערב גיבוש', (SELECT today FROM t_m) + 7);
RESET ROLE;
SELECT t_assert('A5: a social event is "ללא הערכה מקצועית" and gives 0 Golden Spoons',
  (SELECT j->>'evaluation_label_he' = 'ללא הערכה מקצועית' AND (j->>'golden_spoons')::int = 0 FROM t_outputs WHERE label = 'social_create'));
SELECT t_as(t_u('cfoS'));
SET ROLE authenticated;
SELECT t_expect_http('A5: only vp_hr creates (cfo → 403)', $$SELECT rpc_create_social_event(t_u('cS'), 'x', CURRENT_DATE)$$, 'insufficient_privilege', 403);
RESET ROLE;
SELECT t_as(t_u('mgrS'));
SET ROLE authenticated;
SELECT t_expect_http('A5: manager → 403 on create', $$SELECT rpc_create_social_event(t_u('cS'), 'x', CURRENT_DATE)$$, 'insufficient_privilege', 403);
RESET ROLE;
SELECT t_as(t_u('empS1'));
SET ROLE authenticated;
INSERT INTO t_outputs SELECT 'social_list', jsonb_agg(to_jsonb(x)) FROM rpc_list_social_events(t_u('cS')) x;
RESET ROLE;
SELECT t_assert('A5: employees list the event (title, date, label only)',
  (SELECT jsonb_array_length(j) = 1 AND j->0->>'evaluation_label_he' = 'ללא הערכה מקצועית' AND NOT (j->0) ? 'attendance'
     FROM t_outputs WHERE label = 'social_list'));
SELECT t_assert('A5: no attendance is recorded anywhere (no attendance table / column) and no Golden Spoons moved',
  NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name ~* 'attend')
  AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND column_name ~* 'attend')
  AND (SELECT count(*) FROM golden_spoons_ledger) = (SELECT ledger_before FROM t_led));
SELECT t_expect_err('A5: the label cannot be changed', $$UPDATE social_event SET evaluation_label_he = 'מוערך'$$, '23514');

-- ============ 10. layers (Part B1) + governance (B3) — company S ============
SELECT t_pcq('empS' || i, (SELECT m FROM t_m), 60) FROM generate_series(1, 6) i;
INSERT INTO approved_absence_entry (user_id, company_id, requested_date, schedule_status)
VALUES (t_u('empS1'), t_u('cS'), (SELECT m FROM t_m) + 3, 'coordinated');
INSERT INTO approved_absence_entry (user_id, company_id, requested_date, schedule_status, cancelled_at, cancel_reason)
VALUES (t_u('empS2'), t_u('cS'), (SELECT m FROM t_m) + 4, 'cancelled', clock_timestamp(), 'employment_ended');
CREATE TEMP TABLE t_lay AS SELECT fn_board_layers(t_u('cS'), (SELECT m FROM t_m)) AS j;
SELECT t_assert('B1a: EverStore spend in ILS = month spoons (175) × the 3-month estimate (4) = 700; missing inputs say "חסר: …"; reconciliation "לא הוגדר"',
  (SELECT (j->'investment_activity'->>'everstore_spend_ils')::numeric = 700
          AND j->'investment_activity'->>'other_wellbeing_spend_display_he' = 'חסר: wellbeing_spend_input.other_wellbeing_spend_ils'
          AND j->'investment_activity'->>'audited_expense_display_he' = 'חסר: wellbeing_spend_input.audited_expense_line_ils'
          AND j->'investment_activity'->>'reconciliation_display_he' = 'לא הוגדר' FROM t_lay));
SELECT t_assert('B1a: the layer shows the ILS total only — no per-spoon value or key',
  (SELECT (j->'investment_activity')::text !~* '(per_spoon|ils_per|"value")' FROM t_lay));
SELECT t_assert('B1b: adoption by category — 5+ buyers, complement-safe (gift_card 5 shown; learning 5 folded with the 1-buyer concert so the rest is 6)',
  (SELECT jsonb_array_length(j->'adoption_usage'->'by_category') = 1 AND j->'adoption_usage'->'by_category'->0->>'category' = 'gift_card'
          AND (j->'adoption_usage'->'by_category'->0->>'buyers_count')::int = 5
          AND j->'adoption_usage'->>'categories_note_he' IS NOT NULL
          AND NOT (j->'adoption_usage') ? 'redemption_rate_display_he' FROM t_lay));
SELECT t_assert('J-53 redemption rate: the definition text (טיוטה) replaces "לא הוגדר"',
  (SELECT j->'adoption_usage'->'redemption_rate'->>'definition_he' = 'שיעור מימוש = עובדים שמימשו לפחות פריט אחד בתקופה ÷ עובדים פעילים בתקופה'
          AND j->'adoption_usage'->'redemption_rate'->>'text_status' = 'טיוטה' FROM t_lay));
SELECT t_assert('J-53 redemption rate: 11 active employees redeemed ≥ 1 item this month (empS1–11; empS12''s purchase is 4 months old) ÷ active employees',
  (SELECT (j->'adoption_usage'->'redemption_rate'->>'redeemers_count')::int = 11
          AND (j->'adoption_usage'->'redemption_rate'->>'active_employees_count')::int = fn_team_month_members(t_u('cS'), NULL, (SELECT m FROM t_m))
          AND (j->'adoption_usage'->'redemption_rate'->>'rate')::numeric = round(11::numeric / fn_team_month_members(t_u('cS'), NULL, (SELECT m FROM t_m)), 4)
     FROM t_lay));
SELECT t_assert('J-53 redemption rate: a person with 2 purchases counts once; per category gift_card = 5 redeemers; < 5 redeemers → not shown',
  fn_month_redeemers(t_u('cS'), (SELECT m FROM t_m), 'learning') = 5
  AND (SELECT (j->'adoption_usage'->'by_category'->0->'redemption_rate'->>'redeemers_count')::int = 5 FROM t_lay)
  AND fn_redemption_rate_json(t_u('cS'), (SELECT m FROM t_m), 'experience')->>'display_he' = 'אין מספיק מממשים להצגה'
  AND NOT fn_redemption_rate_json(t_u('cS'), (SELECT m FROM t_m), 'experience') ? 'rate');
SELECT t_assert('B1b: coverage by unit — OPS 6 מדווחים בפועל; company coverage shown',
  (SELECT (SELECT (e->>'reporters_count')::int FROM jsonb_array_elements(j->'adoption_usage'->'coverage_by_unit') e WHERE e->>'unit' = 'OPS') = 6
          AND (j->'adoption_usage'->'coverage_company'->>'reporters_count')::int = 6 FROM t_lay));
SELECT t_assert('B1c: outcomes — PCQ-12, IHS / TPS-12 below 5 reporters say so; missing safety / key-role inputs say "חסר: …"',
  (SELECT j->'outcomes'->'safety_incidents'->>'display_he' = 'חסר: safety_incident_monthly.incident_count'
          AND j->'outcomes'->'key_role_turnover'->>'display_he' = 'חסר: company_key_role_setting'
          AND j->'outcomes'->'ihs'->>'display_he' = 'אין מספיק מדווחים בפועל להצגה' FROM t_lay));
SELECT t_assert('J-54: a cancelled absence is not an absence (team OPS 1 — of 2 rows; team level unchanged)',
  fn_team_month_absences(t_u('cS'), 'OPS', (SELECT m FROM t_m)) = 1
  AND fn_company_month_absences(t_u('cS'), (SELECT m FROM t_m)) = 1);
SELECT t_assert('J-53 absences: no board input → "חסר: board_absence_input" with the definition (טיוטה); the approved refresh entry is NOT counted',
  (SELECT j->'outcomes'->'absences'->>'display_he' = 'חסר: board_absence_input'
          AND j->'outcomes'->'absences'->>'definition_he' = 'היעדרות לדוח = ימי מחלה + היעדרות לא מתוכננת בלבד; חופשה מתוכננת והטבות זמן מ-EverStore אינן נספרות'
          AND j->'outcomes'->'absences'->>'text_status' = 'טיוטה' AND NOT (j->'outcomes'->'absences') ? 'days' FROM t_lay));
SELECT t_assert('B3: governance missing → "חסר: …" / "לא הוגדר"',
  (SELECT j->'governance'->>'accountable_exec_display_he' = 'חסר: company_governance.accountable_exec_role_name'
          AND j->'governance'->>'exec_pay_display_he' = 'לא הוגדר'
          AND j->'governance'->>'complaint_display_he' = 'חסר: company_governance.mean_complaint_handling_days' FROM t_lay));
SELECT t_as(t_u('cfoS'));
SET ROLE authenticated;
SELECT jsonb_typeof(rpc_put_wellbeing_spend(t_u('cS'), (SELECT m FROM t_m), 1000, 2000, 'הוצאות רווחה')) AS spend;
SELECT jsonb_typeof(rpc_put_safety_incidents(t_u('cS'), (SELECT m FROM t_m), 2)) AS safety;
SELECT jsonb_typeof(rpc_put_key_role_turnover(t_u('cS'), (SELECT m FROM t_m), 1, 4)) AS keyrole_small;
SELECT t_expect_http('J-53 key roles: only vp_hr marks key roles (cfo → 403)', $$SELECT rpc_put_key_roles(t_u('cS'), ARRAY['מנהל משמרת'])$$, 'insufficient_privilege', 403);
INSERT INTO t_outputs SELECT 'absences_put', rpc_put_board_absences(t_u('cS'), (SELECT m FROM t_m), 6, 2.5);
SELECT t_expect_http('J-53 absences: negative days → 400 invalid_amount', $$SELECT rpc_put_board_absences(t_u('cS'), (SELECT m FROM t_m), -1, 0)$$, 'invalid_amount', 400);
INSERT INTO t_outputs SELECT 'governance_put', rpc_put_company_governance(t_u('cS'), 'סמנכ"ל משאבי אנוש', true, 4.5);
SELECT t_expect_http('B1c: more exits than key roles → 400', $$SELECT rpc_put_key_role_turnover(t_u('cS'), (SELECT m FROM t_m), 5, 4)$$, 'invalid_amount', 400);
RESET ROLE;
SELECT t_assert('B1: after the inputs — reconciliation difference 2,000 − 700 − 1,000 = 300; safety 2; key roles not marked yet → "חסר: company_key_role_setting"',
  (SELECT (j->'investment_activity'->>'reconciliation_difference_ils')::numeric = 300
          AND (j->'outcomes'->'safety_incidents'->>'count')::int = 2
          AND j->'outcomes'->'key_role_turnover'->>'display_he' = 'חסר: company_key_role_setting'
     FROM (SELECT fn_board_layers(t_u('cS'), (SELECT m FROM t_m)) j) x));
-- J-53 key roles: vp_hr marks ROLES (names), audited; people / ids refused.
SELECT t_as(t_u('hrS'));
SET ROLE authenticated;
INSERT INTO t_outputs SELECT 'key_roles_put', rpc_put_key_roles(t_u('cS'), ARRAY[' מנהל משמרת ', 'מהנדס בטיחות', 'מנהל משמרת']);
SELECT t_expect_http('J-53 key roles: an e-mail is not a role → 400', $$SELECT rpc_put_key_roles(t_u('cS'), ARRAY['empS1@board.test'])$$, 'invalid_key_roles', 400);
SELECT t_expect_http('J-53 key roles: a uuid is not a role → 400', $$SELECT rpc_put_key_roles(t_u('cS'), ARRAY[t_u('empS1')::text])$$, 'invalid_key_roles', 400);
SELECT t_expect_http('J-53 key roles: an empty list → 400', $$SELECT rpc_put_key_roles(t_u('cS'), ARRAY[' '])$$, 'invalid_key_roles', 400);
INSERT INTO t_outputs SELECT 'key_roles_get_hr', rpc_get_key_roles(t_u('cS'));
RESET ROLE;
SELECT t_as(t_u('cfoS'));
SET ROLE authenticated;
INSERT INTO t_outputs SELECT 'key_roles_get_cfo', rpc_get_key_roles(t_u('cS'));
RESET ROLE;
SELECT t_as(t_u('empS1'));
SET ROLE authenticated;
SELECT t_expect_http('J-53 key roles: employee → 403 on put', $$SELECT rpc_put_key_roles(t_u('cS'), ARRAY['x'])$$, 'insufficient_privilege', 403);
SELECT t_expect_http('J-53 key roles: employee → 403 on get', $$SELECT rpc_get_key_roles(t_u('cS'))$$, 'insufficient_privilege', 403);
SELECT t_expect_http('J-53 absences: employee → 403 on the input', $$SELECT rpc_put_board_absences(t_u('cS'), CURRENT_DATE, 1, 1)$$, 'insufficient_privilege', 403);
RESET ROLE;
SELECT t_expect_http('J-53 key roles: a service call (no caller) → 403 (vp_hr only)', $$SELECT rpc_put_key_roles(t_u('cS'), ARRAY['x'])$$, 'insufficient_privilege', 403);
SELECT t_assert('J-53 key roles: stored as 2 distinct trimmed role names (no person id), vp_hr and cfo read the same list',
  (SELECT j = jsonb_build_object('status', 'saved', 'key_roles', jsonb_build_array('מהנדס בטיחות', 'מנהל משמרת')) FROM t_outputs WHERE label = 'key_roles_put')
  AND (SELECT j->'key_roles' = jsonb_build_array('מהנדס בטיחות', 'מנהל משמרת')
          AND j->>'key_role_definition_he' = 'תפקיד מפתח = תפקידים (לא אנשים) שסומנו על ידי vp_hr בהגדרות החברה'
          AND j->>'text_status' = 'טיוטה' FROM t_outputs WHERE label = 'key_roles_get_cfo')
  AND (SELECT a.j = b.j FROM t_outputs a, t_outputs b WHERE a.label = 'key_roles_get_hr' AND b.label = 'key_roles_get_cfo')
  AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'company_key_role_setting'
                   AND column_name ~* '(person|user|employee|pseudonym)'));
SELECT t_assert('J-53 key roles: the change is audited (action key_roles_put, role names only, no person id)',
  (SELECT count(*) = 1 AND bool_and(t_ids_free(a.scope) AND a.subject_user_id IS NULL AND a.viewer_id = t_u('hrS')
                                 AND a.scope->'key_roles' = jsonb_build_array('מהנדס בטיחות', 'מנהל משמרת'))
     FROM access_audit_log a WHERE a.action = 'key_roles_put'));
SELECT t_expect_err('J-53 key roles: the setting history is WORM', $$UPDATE company_key_role_setting SET role_names = '{x}'$$, 'ledger_immutable');
SELECT t_assert('J-53 key roles: the turnover input stays aggregate with the ≥ 5 threshold — headcount 4 < 5 → not shown (with the definition)',
  (SELECT j->'outcomes'->'key_role_turnover'->>'display_he' = 'אין מספיק בעלי תפקידי מפתח להצגה'
          AND j->'outcomes'->'key_role_turnover'->'key_roles' = jsonb_build_array('מהנדס בטיחות', 'מנהל משמרת')
          AND NOT (j->'outcomes'->'key_role_turnover') ? 'rate'
     FROM (SELECT fn_board_layers(t_u('cS'), (SELECT m FROM t_m)) j) x));
SELECT t_as(t_u('cfoS'));
SET ROLE authenticated;
SELECT jsonb_typeof(rpc_put_key_role_turnover(t_u('cS'), (SELECT m FROM t_m), 1, 5)) AS keyrole_five;
RESET ROLE;
SELECT t_assert('J-53 key roles: headcount 5 → the aggregate rate is shown (1 / 5)',
  (SELECT (j->'outcomes'->'key_role_turnover'->>'rate')::numeric = 0.2 FROM (SELECT fn_board_layers(t_u('cS'), (SELECT m FROM t_m)) j) x));
-- J-53 absences: sickness + unplanned only. An EverStore time benefit / approved refresh entry and an early leave do not count.
INSERT INTO approved_absence_entry (user_id, company_id, requested_date, schedule_status)
VALUES (t_u('empS3'), t_u('cS'), (SELECT m FROM t_m) + 5, 'coordinated');
SELECT t_assert('J-53 absences: board days = sickness 6 + unplanned 2.5 = 8.5; the 2 approved refresh / time-benefit entries (incl. a new one) are not added',
  (SELECT (j->'outcomes'->'absences'->>'days')::numeric = 8.5 AND (j->'outcomes'->'absences'->>'sickness_days')::numeric = 6
          AND (j->'outcomes'->'absences'->>'unplanned_absence_days')::numeric = 2.5
     FROM (SELECT fn_board_layers(t_u('cS'), (SELECT m FROM t_m)) j) x)
  AND fn_team_month_absences(t_u('cS'), 'OPS', (SELECT m FROM t_m)) = 2);
SELECT t_assert('J-53 absences: planned vacation and time benefits have no input field at all (only sickness / unplanned columns)',
  (SELECT array_agg(column_name::text ORDER BY column_name::text) FROM information_schema.columns
    WHERE table_name = 'board_absence_input' AND column_name ~ '_days$') = ARRAY['sickness_days', 'unplanned_absence_days']
  AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'board_absence_input' AND column_name ~* '(vacation|benefit|refresh|^planned)'));
SELECT t_assert('J-53 absences: the input output is status only',
  (SELECT j->>'status' = 'saved' AND t_ids_free(j) FROM t_outputs WHERE label = 'absences_put'));
SELECT t_assert('B3: governance = role name only (no person), exec pay tied, complaint time 4.5 days',
  (SELECT j->>'accountable_exec_role_name' = 'סמנכ"ל משאבי אנוש' AND (j->>'exec_pay_tied_to_metrics')::boolean
          AND (j->>'mean_complaint_handling_days')::numeric = 4.5 AND t_ids_free(j) FROM t_outputs WHERE label = 'governance_put'));
SELECT t_as(t_u('empS1'));
SET ROLE authenticated;
SELECT t_expect_http('B3: employee → 403 on governance input', $$SELECT rpc_put_company_governance(t_u('cS'), 'x', true, 1)$$, 'insufficient_privilege', 403);
SELECT t_expect_http('B1: employee → 403 on spend input', $$SELECT rpc_put_wellbeing_spend(t_u('cS'), CURRENT_DATE, 1, 1)$$, 'insufficient_privilege', 403);
RESET ROLE;

-- ============ 11. privacy sweep ============
INSERT INTO t_outputs SELECT 'layers_s', j FROM t_lay;
SELECT t_assert('privacy: no v1.6.19 output holds person_id / user_id / pseudonym / a user''s uuid / name / email',
  (SELECT bool_and(t_ids_free(j)) FROM t_outputs));
SELECT t_assert('privacy: every v1.6.19 table is closed (RLS forced, no client grant) and none has a person column',
  (SELECT bool_and(c.relrowsecurity AND c.relforcerowsecurity AND NOT has_table_privilege('authenticated', c.oid, 'SELECT'))
     FROM pg_class c WHERE c.relname IN ('leaver_memo_snapshot', 'leaver_memo_inclusion', 'metric_verification_evidence',
       'verification_dossier', 'questionnaire_item_version', 'measurement_change_log', 'org_event', 'payroll_population_input',
       'metric_pay_linkage', 'social_event', 'wellbeing_spend_input', 'safety_incident_monthly', 'key_role_turnover_input',
       'company_governance', 'company_key_role_setting', 'board_absence_input'))
  AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public'
                   AND table_name IN ('leaver_memo_snapshot', 'leaver_memo_inclusion', 'metric_verification_evidence',
                     'verification_dossier', 'questionnaire_item_version', 'measurement_change_log', 'org_event',
                     'payroll_population_input', 'metric_pay_linkage', 'social_event', 'wellbeing_spend_input',
                     'safety_incident_monthly', 'key_role_turnover_input', 'company_governance', 'company_key_role_setting',
                     'board_absence_input')
                   AND column_name ~* '(person|user|employee_id|pseudonym)'));
-- The four rejected glossary terms are assembled from pieces so that the pack itself greps clean for them.
SELECT t_assert('forbidden terms: none of the 4 rejected glossary terms (standalone spoon plural included) in any report or function text',
  (SELECT bool_and(j::text !~ ('(מש' || 'יבים|מס הח' || 'סך|צ' || 'בן)') AND j::text !~ ('(^|[^א-ת])כ' || 'פות([^א-ת]|$)')) FROM t_outputs)
  AND NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public'
                   AND (p.prosrc ~ ('(מש' || 'יבים|מס הח' || 'סך|צ' || 'בן)') OR p.prosrc ~ ('(^|[^א-ת])כ' || 'פות([^א-ת]|$)'))));
SELECT 'ALL v1.6.19 BOARD TESTS PASSED' AS result;
