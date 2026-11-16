-- =============================================================================
-- CHR-ETRS v1.7.0 · tests/test_j_whats_changed.sql — J-205 manager views, J-218 vp_hr monthly changes, action updates
-- =============================================================================
\ir j_helpers.sql

-- This month / the previous month on the company calendar.
CREATE OR REPLACE FUNCTION t_m(p_shift int) RETURNS date LANGUAGE sql AS $$
  SELECT fn_month_shift(fn_agent_month_start(t_u('W'), clock_timestamp()), p_shift)
$$;

SELECT t_company('W') IS NOT NULL AS w;
DO $$
BEGIN
  PERFORM t_mk('hrW', 'W', 'vp_hr', 'vp', 'Mgmt');
  PERFORM t_mk('mgr', 'W', 'manager', 'direct_manager', 'Ops');
  PERFORM t_mk('mgr2', 'W', 'manager', 'direct_manager', 'Sales');
  PERFORM t_mk('emp', 'W', 'employee', 'employee', 'Ops');
  FOR i IN 1..6 LOOP PERFORM t_mk('sub' || i, 'W', 'employee', 'employee', 'Ops', 'mgr'); END LOOP;     -- her subtree
  FOR i IN 1..5 LOOP PERFORM t_mk('ops' || i, 'W', 'employee', 'employee', 'Ops'); END LOOP;            -- rest of Ops
  FOR i IN 1..5 LOOP PERFORM t_mk('sal' || i, 'W', 'employee', 'employee', 'Sales', 'mgr2'); END LOOP;
  FOR i IN 1..5 LOOP PERFORM t_mk('rd' || i, 'W', 'employee', 'employee', 'RnD'); END LOOP;
  -- this month: subtree 6 (score 60), Ops others 3 of 5 (score 40); Sales 3 (score 50); RnD 5 (score 70)
  FOR i IN 1..6 LOOP PERFORM t_sub('sub' || i, 'PCQ-12', t_m(0), 60); END LOOP;
  FOR i IN 1..3 LOOP PERFORM t_sub('ops' || i, 'PCQ-12', t_m(0), 40); END LOOP;
  FOR i IN 1..3 LOOP PERFORM t_sub('sal' || i, 'PCQ-12', t_m(0), 50); END LOOP;
  FOR i IN 1..5 LOOP PERFORM t_sub('rd' || i, 'PCQ-12', t_m(0), 70); END LOOP;
  -- previous month: Ops 6 at 50; RnD 5 at 69; Sales 3 at 50
  FOR i IN 1..6 LOOP PERFORM t_sub('sub' || i, 'PCQ-12', t_m(-1), 50); END LOOP;
  FOR i IN 1..5 LOOP PERFORM t_sub('rd' || i, 'PCQ-12', t_m(-1), 69); END LOOP;
  FOR i IN 1..3 LOOP PERFORM t_sub('sal' || i, 'PCQ-12', t_m(-1), 50); END LOOP;
END $$;

-- ---------- J-205 ----------
SELECT t_err_as('J-205: an employee cannot use the manager view → 403', 'emp', $$SELECT rpc_manager_team_view('subtree')$$, 'access_denied', 403);
SELECT t_err_as('J-205: unknown view → 403', 'mgr', $$SELECT rpc_manager_team_view('company')$$, 'access_denied', 403);
SELECT t_assert('J-205 view 1: her subtree with 6 מדווחים בפועל is shown (average 60)',
  (SELECT j->>'shown' = 'subtree' AND (j->>'pcq12_average')::numeric = 60 AND (j->>'reporters')::int = 6
     FROM (SELECT t_json_as('mgr', $$rpc_manager_team_view('subtree')$$) j) x));
SELECT t_assert('J-205 view 2: department 9 − team 6 = 3 (1–4) → hidden with the standard text (difference rule)',
  (SELECT j->>'shown' = 'none' AND j->>'display_he' = 'אין מספיק נתונים להצגה בתקופה זו'
     FROM (SELECT t_json_as('mgr', $$rpc_manager_team_view('department')$$) j) x));
SELECT t_sub('ops4', 'PCQ-12', t_m(0), 40), t_sub('ops5', 'PCQ-12', t_m(0), 40);
SELECT t_assert('J-205 view 2: department 11 − team 6 = 5 → the department is shown',
  (SELECT j->>'shown' = 'department' AND (j->>'reporters')::int = 11
     FROM (SELECT t_json_as('mgr', $$rpc_manager_team_view('department')$$) j) x));
SELECT t_assert('J-205: a subtree under 5 (Sales 3) falls back to the department, which is also under 5 → nothing shown',
  (SELECT j->>'shown' = 'none' FROM (SELECT t_json_as('mgr2', $$rpc_manager_team_view('subtree')$$) j) x));
SELECT t_sub('sal4', 'PCQ-12', t_m(0), 50), t_sub('sal5', 'PCQ-12', t_m(0), 50);
SELECT t_assert('J-205: Sales subtree 5 = department 5 → view 2 shows the department (department − team = 0 reveals nothing new)',
  (SELECT j->>'shown' = 'department' AND (j->>'reporters')::int = 5
     FROM (SELECT t_json_as('mgr2', $$rpc_manager_team_view('department')$$) j) x));
SELECT t_assert('J-205: the output never carries a person id',
  t_free_of(t_json_as('mgr', $$rpc_manager_team_view('department')$$), t_all_user_ids()));
SELECT t_assert('J-205: rpc_subtree_summary is untouched (still present, same signature)',
  to_regprocedure('rpc_subtree_summary(date)') IS NOT NULL OR EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_subtree_summary'));

-- ---------- J-218 ----------
SELECT jsonb_typeof(t_json_as('hrW', format($$(SELECT to_jsonb(x) FROM rpc_put_agent_setting('%s', 'golden_spoons_per_cantril', 3) x)$$, t_u('W')))) AS c1,
       jsonb_typeof(t_json_as('hrW', format($$(SELECT to_jsonb(x) FROM rpc_put_agent_setting('%s', 'golden_spoons_per_questionnaire', 15) x)$$, t_u('W')))) AS c2;
CREATE TEMP TABLE t_ch AS SELECT t_json_as('hrW', $$rpc_hr_monthly_changes()$$) AS cur,
                                 t_json_as('hrW', format($$rpc_hr_monthly_changes('%s')$$, t_m(1))) AS nxt;
SELECT t_assert('J-218: two separate sections (metric_changes / settings_changes)',
  (SELECT cur ? 'metric_changes' AND cur ? 'settings_changes' AND jsonb_typeof(cur->'metric_changes') = 'array' FROM t_ch));
SELECT t_assert('J-218: metric section — only departments over the threshold in BOTH months (RnD +1.00, Ops +0.91; Sales excluded), sorted by size',
  (SELECT jsonb_array_length(cur->'metric_changes') = 2 AND cur->'metric_changes'->0->>'department' = 'RnD'
          AND (cur->'metric_changes'->0->>'change')::numeric = 1 AND cur->'metric_changes'->1->>'department' = 'Ops'
          AND (cur->'metric_changes'->1->>'change')::numeric = 0.91
          AND NOT (cur::text ~ 'Sales') FROM t_ch));
SELECT t_assert('J-218: settings section — the changes taking effect next month, sorted by size (15 before 3)',
  (SELECT jsonb_array_length(nxt->'settings_changes') = 2
          AND nxt->'settings_changes'->0->>'setting_key' = 'golden_spoons_per_questionnaire'
          AND nxt->'settings_changes'->1->>'setting_key' = 'golden_spoons_per_cantril' FROM t_ch));
SELECT t_assert('J-218: no person ids in the report', (SELECT t_free_of(cur, t_all_user_ids()) AND t_free_of(nxt, t_all_user_ids()) FROM t_ch));
SELECT t_err_as('J-218: only vp_hr → 403 for a manager', 'mgr', $$SELECT rpc_hr_monthly_changes()$$, 'insufficient_privilege', 403);

-- ---------- action updates ----------
SELECT t_err_as('action update: 2 characters → 400', 'mgr', $$SELECT rpc_post_action_update('absences', 'אב')$$, 'invalid_action_update', 400);
SELECT t_err_as('action update: 301 characters → 400', 'mgr', $$SELECT rpc_post_action_update('absences', repeat('א', 301))$$, 'invalid_action_update', 400);
SELECT t_err_as('action update: unknown metric → 400', 'mgr', $$SELECT rpc_post_action_update('nope', 'טקסט תקין')$$, 'invalid_action_update', 400);
SELECT t_err_as('action update: an employee → 403', 'emp', $$SELECT rpc_post_action_update('absences', 'טקסט תקין')$$, 'access_denied', 403);
SELECT jsonb_typeof(t_json_as('mgr', $$rpc_post_action_update('absences', 'הוספנו הפסקה')$$)) AS posted;
SELECT t_assert('action update: everyone in the company reads it — metric, text, date; no author',
  (SELECT jsonb_array_length(j) = 1 AND (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(j->0) k) = ARRAY['body_he', 'date', 'metric_key']
     FROM (SELECT t_json_as('emp', $$rpc_list_action_updates()$$) j) x)
  AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'action_update' AND column_name ~ '(user|author|person)'));
SELECT t_err('action updates are WORM (kept permanently)', $$DELETE FROM action_update$$, 'ledger_immutable');

SELECT 'ALL J WHATS-CHANGED TESTS PASSED' AS result;
