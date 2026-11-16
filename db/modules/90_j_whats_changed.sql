-- =============================================================================
-- CHR-ETRS v1.7.0 · modules/90_j_whats_changed.sql — J-205, J-217 / J-218, action updates (Karin 16.11)
--   * J-205: a NEW manager RPC (rpc_subtree_summary is untouched) with two views — (1) her solid subtree, (2) her whole
--     department. Difference rule in both: the department is shown only when (department − her team) is 0 or ≥ 5.
--   * J-218: vp_hr's monthly "what changed" — metric changes and settings changes in two separate sections, each sorted
--     by size; the privacy thresholds apply to the metric section.
--   * action updates linked to a metric: text 3–300 characters, no author id (WORM).
-- =============================================================================

-- PCQ-12 average + distinct reporters of a set of users in a month.
CREATE OR REPLACE FUNCTION fn_j_group_pcq(p_users uuid[], p_month date)
RETURNS TABLE (avg_score numeric, reporters int)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT round(avg(q.pcq12_score), 2), count(DISTINCT q.user_id)::int
    FROM questionnaire_submission q
   WHERE q.user_id = ANY (p_users) AND q.questionnaire_code = 'PCQ-12'
     AND q.local_date >= p_month AND q.local_date < fn_month_shift(p_month, 1)
$$;

-- Members (employee profile) of the manager's solid subtree, the manager excluded.
CREATE OR REPLACE FUNCTION fn_j_subtree_members(p_manager uuid)
RETURNS uuid[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT COALESCE(array_agg(s.user_id), '{}') FROM fn_solid_subtree(p_manager) s JOIN users u ON u.user_id = s.user_id
   WHERE s.user_id <> p_manager AND u.has_employee_profile
$$;

-- Members (employee profile) of a department of a company — marker-aware (J-96 / J-102: the default department and
-- 'ללא מחלקה' are never a team).
CREATE OR REPLACE FUNCTION fn_j_department_members(p_company uuid, p_department text)
RETURNS uuid[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT COALESCE(array_agg(u.user_id), '{}') FROM users u
   WHERE u.company_id = p_company AND u.has_employee_profile
     AND fn_user_in_team(u.department, u.department_is_default, p_department)
$$;

-- J-205 (Karin 16.11) manager view. p_view 'subtree': her solid subtree; when it is under the regular threshold the
-- department is shown instead. p_view 'department': her whole department. The department figure is shown only when it
-- passes the regular threshold AND (department reporters − subtree reporters) is 0 or ≥ 5; otherwise the standard text.
CREATE OR REPLACE FUNCTION rpc_manager_team_view(p_view text, p_month date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_me   users;
  v_min  int := fn_privacy_min_n('regular');
  v_m    date;
  t      record;
  d      record;
  v_diff int;
BEGIN
  SELECT * INTO v_me FROM users u WHERE u.user_id = v_uid AND u.employment_ended_at IS NULL;
  IF v_me.user_id IS NULL OR NOT EXISTS (SELECT 1 FROM org_role r WHERE r.role_code = v_me.org_role_code AND r.is_management)
     OR p_view IS NULL OR p_view NOT IN ('subtree', 'department') THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  v_m := COALESCE(fn_month_of(p_month), fn_agent_month_start(v_me.company_id, clock_timestamp()));
  SELECT * INTO t FROM fn_j_group_pcq(fn_j_subtree_members(v_uid), v_m);
  -- marker-aware: a manager without a department (default / 'ללא מחלקה') has no department group
  SELECT * INTO d FROM fn_j_group_pcq(fn_j_department_members(v_me.company_id,
                                      fn_user_group_key(v_me.department, v_me.department_is_default)), v_m);
  PERFORM fn_audit_view('manager_team_view', jsonb_build_object('view', p_view, 'month', v_m));
  IF p_view = 'subtree' AND COALESCE(t.reporters, 0) >= v_min THEN
    RETURN jsonb_build_object('view', p_view, 'month', v_m, 'shown', 'subtree', 'pcq12_average', t.avg_score,
                              'reporters', t.reporters);
  END IF;
  v_diff := COALESCE(d.reporters, 0) - COALESCE(t.reporters, 0);
  IF COALESCE(d.reporters, 0) >= v_min AND (v_diff = 0 OR v_diff >= v_min) THEN
    RETURN jsonb_build_object('view', p_view, 'month', v_m, 'shown', 'department', 'pcq12_average', d.avg_score,
                              'reporters', d.reporters);
  END IF;
  RETURN jsonb_build_object('view', p_view, 'month', v_m, 'shown', 'none', 'display_he', fn_insufficient_data_period_he());
END;
$$;

-- J-218 metric section: per department, PCQ-12 this month vs the previous month — only departments with ≥ the regular
-- threshold of reporters in BOTH months; sorted by the size of the change.
CREATE OR REPLACE FUNCTION fn_j218_metric_changes(p_company uuid, p_month date)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('department', x.department, 'metric', 'PCQ-12',
                                               'previous', x.prev_avg, 'current', x.cur_avg,
                                               'change', x.cur_avg - x.prev_avg)
                            ORDER BY abs(x.cur_avg - x.prev_avg) DESC, x.department), '[]'::jsonb)
    FROM (SELECT dep.department, c.avg_score AS cur_avg, p.avg_score AS prev_avg
            FROM (SELECT DISTINCT fn_user_group_key(u.department, u.department_is_default) AS department FROM users u
                   WHERE u.company_id = p_company AND u.has_employee_profile
                     AND NOT fn_user_is_no_department(u.department, u.department_is_default)) dep
            CROSS JOIN LATERAL fn_j_group_pcq(fn_j_department_members(p_company, dep.department), p_month) c
            CROSS JOIN LATERAL fn_j_group_pcq(fn_j_department_members(p_company, dep.department), fn_month_shift(p_month, -1)) p
           WHERE c.reporters >= fn_privacy_min_n('regular') AND p.reporters >= fn_privacy_min_n('regular')) x
$$;

-- J-218 settings section: reward amount changes that take effect in the month, sorted by the size of the change.
CREATE OR REPLACE FUNCTION fn_j218_settings_changes(p_company uuid, p_month date)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('setting_key', h.setting_key, 'value_before', h.value_before,
                                               'value_after', h.value_after,
                                               'effective_from', fn_agent_local_ts(p_company, h.effective_from)::date)
                            ORDER BY abs(h.value_after - COALESCE(h.value_before, h.value_after)) DESC, h.setting_key),
                  '[]'::jsonb)
    FROM questionnaire_reward_history h
   WHERE h.company_id = p_company
     AND date_trunc('month', fn_agent_local_ts(p_company, h.effective_from))::date = p_month
$$;

-- vp_hr: the month's changes in two sections (metrics / settings), each sorted by size.
CREATE OR REPLACE FUNCTION rpc_hr_monthly_changes(p_month date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_comp uuid := fn_my_company();
  v_m    date;
BEGIN
  PERFORM fn_assert_vp_hr(v_comp);
  v_m := COALESCE(fn_month_of(p_month), fn_agent_month_start(v_comp, clock_timestamp()));
  PERFORM fn_audit_view('hr_monthly_changes', jsonb_build_object('month', v_m));
  RETURN jsonb_build_object('month', v_m, 'metric_changes', fn_j218_metric_changes(v_comp, v_m),
                            'settings_changes', fn_j218_settings_changes(v_comp, v_m));
END;
$$;

-- ---------- action updates ----------
CREATE TABLE IF NOT EXISTS action_update (
    update_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id  uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    metric_key  text NOT NULL,
    body_he     text NOT NULL CHECK (length(btrim(body_he)) BETWEEN 3 AND 300),   -- Karin 16.11: 3–300
    created_at  timestamptz NOT NULL DEFAULT clock_timestamp()
);
DROP TRIGGER IF EXISTS trg_action_update_worm ON action_update;
CREATE TRIGGER trg_action_update_worm BEFORE UPDATE OR DELETE ON action_update
    FOR EACH ROW EXECUTE FUNCTION fn_worm_immutable('ledger_immutable');
ALTER TABLE action_update ENABLE ROW LEVEL SECURITY;
ALTER TABLE action_update FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE action_update FROM PUBLIC, anon, authenticated;

-- A manager / vp_hr posts an action update linked to a board metric (3–300 characters; no author id is stored).
CREATE OR REPLACE FUNCTION rpc_post_action_update(p_metric_key text, p_body text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_comp uuid := fn_my_company();
BEGIN
  IF NOT (fn_caller_active_role_in(v_comp, ARRAY['manager', 'vp_hr'])) THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  IF p_metric_key IS NULL OR NOT (p_metric_key = ANY (fn_board_metric_keys())) OR NOT fn_j_text_ok(p_body, 3, 300) THEN
    PERFORM fn_raise_bad_request('invalid_action_update');
  END IF;
  INSERT INTO action_update (company_id, metric_key, body_he) VALUES (v_comp, p_metric_key, btrim(p_body));
  PERFORM fn_audit_view('action_update_put', jsonb_build_object('metric_key', p_metric_key));
  RETURN jsonb_build_object('metric_key', p_metric_key, 'stored', true);
END;
$$;

-- Everyone in the company reads its action updates (metric, text, date; no author).
CREATE OR REPLACE FUNCTION rpc_list_action_updates()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('metric_key', a.metric_key, 'body_he', a.body_he,
                                               'date', fn_agent_local_ts(a.company_id, a.created_at)::date)
                            ORDER BY a.created_at DESC), '[]'::jsonb)
    FROM action_update a WHERE a.company_id = fn_my_company()
$$;

REVOKE ALL ON FUNCTION rpc_manager_team_view(text, date), rpc_hr_monthly_changes(date), rpc_post_action_update(text, text),
  rpc_list_action_updates() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_manager_team_view(text, date), rpc_hr_monthly_changes(date), rpc_post_action_update(text, text),
  rpc_list_action_updates() TO authenticated;
REVOKE ALL ON FUNCTION fn_j_group_pcq(uuid[], date), fn_j_subtree_members(uuid), fn_j_department_members(uuid, text),
  fn_j218_metric_changes(uuid, date), fn_j218_settings_changes(uuid, date) FROM PUBLIC, anon, authenticated;
