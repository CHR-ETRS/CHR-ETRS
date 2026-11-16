-- =============================================================================
-- CHR-ETRS v1.7.0 · tests/test_j_spoons.sql — golden spoons per questionnaire (Karin 16.11)
--   TPS-12 / IHS = 10 for participation only; Cantril = 2 through its own key, monthly;
--   A-14: vp_hr changes 1–20 for her company, from the NEXT period only; each change logged; one amount per company.
-- Ends by re-applying schema.sql (the upgrade path keeps Cantril = 2).
-- =============================================================================
\ir j_helpers.sql

SELECT t_company('S') IS NOT NULL AS s, t_company('T') IS NOT NULL AS t;
DO $$
BEGIN
  PERFORM t_mk('hrS', 'S', 'vp_hr', 'vp', 'Mgmt'); PERFORM t_mk('cfoS', 'S', 'cfo', 'vp', 'Mgmt');
  PERFORM t_mk('hrT', 'T', 'vp_hr', 'vp', 'Mgmt');
  PERFORM t_mk('low', 'S'); PERFORM t_mk('high', 'S');
END $$;

SELECT t_assert('pack defaults: PCQ-12 10, TPS-12 / IHS 10 (quarterly key), Cantril 2 (own key golden_spoons_per_cantril)',
  fn_agent_setting_num(NULL, 'golden_spoons_per_questionnaire') = 10
  AND fn_agent_setting_num(NULL, 'golden_spoons_per_quarterly_questionnaire') = 10
  AND fn_agent_setting_num(NULL, 'golden_spoons_per_cantril') = 2
  AND (SELECT reward_setting_key = 'golden_spoons_per_cantril' AND frequency = 'monthly' FROM questionnaire_definition WHERE code = 'Cantril')
  AND (SELECT bool_and(reward_setting_key = 'golden_spoons_per_quarterly_questionnaire' AND frequency = 'quarterly')
         FROM questionnaire_definition WHERE code IN ('TPS-12', 'IHS')));
SELECT t_assert('participation only: reward_type participation on every questionnaire',
  (SELECT bool_and(reward_type = 'participation') FROM questionnaire_definition));

-- two opposite answer sets → the same reward
CREATE TEMP TABLE t_sub AS
  SELECT 'low' AS who, t_json_as('low', $$rpc_submit_questionnaire('TPS-12', array_fill(1, ARRAY[12]))$$) AS j
  UNION ALL SELECT 'high', t_json_as('high', $$rpc_submit_questionnaire('TPS-12', array_fill(5, ARRAY[12]))$$);
INSERT INTO t_sub SELECT 'low', t_json_as('low', $$rpc_submit_questionnaire('IHS', array_fill(1, ARRAY[9]))$$);
INSERT INTO t_sub SELECT 'high', t_json_as('high', $$rpc_submit_questionnaire('IHS', array_fill(5, ARRAY[9]))$$);
INSERT INTO t_sub SELECT 'low', t_json_as('low', $$rpc_submit_questionnaire('Cantril', ARRAY[0])$$);
INSERT INTO t_sub SELECT 'high', t_json_as('high', $$rpc_submit_questionnaire('Cantril', ARRAY[10])$$);
SELECT t_assert('TPS-12: all-1 and all-5 answers both earn 10 golden spoons (score differs, reward does not)',
  (SELECT count(*) = 2 AND bool_and((j->>'reward_golden_spoons')::numeric = 10) AND count(DISTINCT j->>'score') = 2
     FROM t_sub WHERE j->>'questionnaire_code' = 'TPS-12'));
SELECT t_assert('IHS: all-1 and all-5 answers both earn 10',
  (SELECT count(*) = 2 AND bool_and((j->>'reward_golden_spoons')::numeric = 10) FROM t_sub WHERE j->>'questionnaire_code' = 'IHS'));
SELECT t_assert('Cantril: 0 and 10 both earn 2 golden spoons',
  (SELECT count(*) = 2 AND bool_and((j->>'reward_golden_spoons')::numeric = 2) FROM t_sub WHERE j->>'questionnaire_code' = 'Cantril'));
SELECT t_assert('balances: 10 + 10 + 2 = 22 each', (SELECT bool_and(golden_spoons = 22) FROM avatar_state WHERE user_id IN (t_u('low'), t_u('high'))));
SELECT t_err_as('Cantril is monthly: a second Cantril in the same month → 409', 'low',
  $$SELECT rpc_submit_questionnaire('Cantril', ARRAY[5])$$, 'questionnaire_already_submitted', 409);

-- ---------- A-14 ----------
SELECT t_err_as('A-14: a cfo cannot change the amount → 403', 'cfoS',
  format($$SELECT * FROM rpc_put_agent_setting('%s', 'golden_spoons_per_cantril', 3)$$, t_u('S')), 'insufficient_privilege', 403);
SELECT t_err_as('A-14: vp_hr of another company → 403', 'hrT',
  format($$SELECT * FROM rpc_put_agent_setting('%s', 'golden_spoons_per_cantril', 3)$$, t_u('S')), 'insufficient_privilege', 403);
SELECT t_err_as('A-14: 21 → 422 out of range', 'hrS',
  format($$SELECT * FROM rpc_put_agent_setting('%s', 'golden_spoons_per_cantril', 21)$$, t_u('S')), 'questionnaire_reward_out_of_range', 422);
SELECT t_err_as('A-14: 0 → 422 out of range', 'hrS',
  format($$SELECT * FROM rpc_put_agent_setting('%s', 'golden_spoons_per_quarterly_questionnaire', 0)$$, t_u('S')), 'questionnaire_reward_out_of_range', 422);
CREATE TEMP TABLE t_put AS SELECT t_json_as('hrS', format($$(SELECT to_jsonb(x) FROM rpc_put_agent_setting('%s', 'golden_spoons_per_cantril', 3) x)$$, t_u('S'))) AS j;
INSERT INTO t_put SELECT t_json_as('hrS', format($$(SELECT to_jsonb(x) FROM rpc_put_agent_setting('%s', 'golden_spoons_per_quarterly_questionnaire', 20) x)$$, t_u('S')));
SELECT t_assert('A-14: the change applies from the NEXT period only — today Cantril is still 2, TPS / IHS still 10',
  fn_questionnaire_reward_at('golden_spoons_per_cantril', t_u('S'), clock_timestamp()) = 2
  AND fn_questionnaire_reward_at('golden_spoons_per_quarterly_questionnaire', t_u('S'), clock_timestamp()) = 10);
SELECT t_assert('A-14: next period = next company month for Cantril, next company quarter for TPS-12 / IHS',
  (SELECT effective_from = (date_trunc('month', clock_timestamp() AT TIME ZONE 'Asia/Jerusalem') + interval '1 month') AT TIME ZONE 'Asia/Jerusalem'
     FROM questionnaire_reward_history WHERE company_id = t_u('S') AND setting_key = 'golden_spoons_per_cantril')
  AND (SELECT effective_from = (date_trunc('quarter', clock_timestamp() AT TIME ZONE 'Asia/Jerusalem') + interval '3 months') AT TIME ZONE 'Asia/Jerusalem'
     FROM questionnaire_reward_history WHERE company_id = t_u('S') AND setting_key = 'golden_spoons_per_quarterly_questionnaire'));
SELECT t_assert('A-14: from the next period the new amounts apply (3 / 20)',
  fn_questionnaire_reward_at('golden_spoons_per_cantril', t_u('S'), clock_timestamp() + interval '32 days') = 3
  AND fn_questionnaire_reward_at('golden_spoons_per_quarterly_questionnaire', t_u('S'), clock_timestamp() + interval '93 days') = 20);
SELECT t_assert('A-14: each change logged — who (vp_hr), when, from → to, effective from',
  (SELECT count(*) = 2 FROM access_audit_log WHERE action = 'questionnaire_reward_setting_put' AND viewer_id = t_u('hrS')
     AND scope ? 'value_before' AND scope ? 'value_after' AND scope ? 'effective_from' AND created_at IS NOT NULL)
  AND (SELECT value_before = 2 AND value_after = 3 FROM questionnaire_reward_history WHERE setting_key = 'golden_spoons_per_cantril'));
SELECT t_assert('A-14: the settings screen shows the current amount and the next one ("2 כפיות זהב (מהתקופה הבאה: 3 כפיות זהב)")',
  (SELECT j->>'display_he' = '2 כפיות זהב (מהתקופה הבאה: 3 כפיות זהב)' FROM t_put WHERE j->>'setting_key' = 'golden_spoons_per_cantril'));
SELECT t_assert('A-14: company T is untouched (one amount per company; no per-team amount exists)',
  fn_questionnaire_reward_at('golden_spoons_per_cantril', t_u('T'), clock_timestamp() + interval '32 days') = 2
  AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'questionnaire_reward_history' AND column_name ~ '(team|department)'));
SELECT t_err('A-14: the history is WORM', $$UPDATE questionnaire_reward_history SET value_after = 5$$, 'ledger_immutable');
SELECT t_assert('A-14: a submission keeps its own amount (snapshot) — rows already earned stay 2 / 10',
  (SELECT bool_and(reward_golden_spoons = CASE questionnaire_code WHEN 'Cantril' THEN 2 ELSE 10 END) FROM questionnaire_submission));

-- ---------- re-apply schema.sql: Cantril stays 2 ----------
\ir ../schema.sql
SET client_min_messages = warning;
SELECT t_assert('re-applying schema.sql keeps Cantril = 2 on its own key (upgrade path)',
  fn_agent_setting_num(NULL, 'golden_spoons_per_cantril') = 2
  AND (SELECT reward_setting_key = 'golden_spoons_per_cantril' FROM questionnaire_definition WHERE code = 'Cantril')
  AND (SELECT count(*) = 2 FROM questionnaire_reward_history WHERE company_id = t_u('S')));

SELECT 'ALL J SPOONS TESTS PASSED' AS result;
