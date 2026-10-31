-- =============================================================================
-- CHR-ETRS MVP v1.6.17 · rpc.sql
-- Version: 1.6.17-mvp (2026-10-31 IL) — supersedes 1.6.16-mvp (2026-10-30 IL), 1.6.13-mvp (2026-10-25 IL; v1.6.14 / v1.6.15 never built), 1.6.12-mvp (2026-10-24 IL), 1.6.11-mvp (2026-10-24 IL), 1.6.10-mvp (2026-10-21 IL), 1.6.9-mvp (2026-10-21 IL), 1.6.8-mvp (2026-10-21 IL), 1.6.7-mvp (2026-10-20 22:05 IL), 1.6.6-mvp (2026-10-20 21:15 IL), 1.6.5-mvp (2026-10-20 21:00 IL), 1.6.4-mvp (2026-10-20 20:45 IL), 1.6.3-mvp (2026-10-20 20:30 IL), 1.6.2-mvp (2026-10-20 11:05 IL), 1.6.1-mvp (2026-10-20 10:58 IL), 1.6.0-mvp (2026-10-20 10:30 IL), 1.5.0-mvp and 1.4.0-mvp (2026-10-06)
-- SoT: ADR index + Karin's approved locks of 2026-10-20. ALL writes via RPC.
-- Paths: POST /rpc/<function_name> with rpc_* names.
-- New in 1.6.0: red team alert (respondent N≥5), shop by employee profile, crypto-shred
-- self/offboarding only, system pseudonyms, TPS 30-day rule from team_joined_at.
-- New in 1.6.1: thresholds count actual contributors (lock #3); ≤3 spoons blocks all tasks
-- (lock #1); role-tree access, CHRO named view + reason, project load index, board macro
-- trends, emergency mode, distress button. Every management view writes access_audit_log.
-- New in 1.6.17 (Karin 31.10 via Chief of Drive — fix round):
--   * A-5 / J-3: TPS-12, IHS and Cantril each pay 10 Golden Spoons for participation (settings, see schema.sql);
--     fn_questionnaire_reward is unchanged (it reads agent_settings, never a code constant).
--   * J-15: fn_block_time_benefit_after_exit — no early leave / approved absence row for an employee whose
--     employment ended (trigger on early_leave_log and approved_absence_entry); rpc_everstore_purchase refuses a
--     time_benefit item after exit; EverStore products stay redeemable in the 30-day window.
--   * A-8: fn_reverse_leaver_transfer + trigger trg_users_leaver_debt_reversal — reversing an offboarding writes a
--     'leaver_reversal' event linked to the original leaver_transfer; the memo line "יצא עם העוזבים" decreases and
--     the debt returns to the team. Idempotent (once per transfer). No person identifier in any output.
-- New in 1.6.16 (Karin 30.10 + Chief of Drive 30.10; agents-bot-instructions-v3 wins over earlier decisions):
--   * rpc_convert_golden_to_chr: DEFINED for v2 readiness, BLOCKED in v1 — every call raises HTTP 422
--     chr_coins_deferred_to_v2 (SQLSTATE PT422) before any read or write (no balance change, no row).
--   * Golden Spoons for participation only, fixed amounts from agent_settings (questionnaires, shift,
--     signup); fn_questionnaire_reward no longer receives a score.
--   * Deprived employee (classify_deprived = fn_is_employee_deprived): same thresholds, now TWO
--     consecutive weeks (v3 §6.2); counted at group level only.
--   * Departed employees may redeem in EverStore for exit_redemption_days (30) after employment ends;
--     day 31 → rpc_expire_departed_golden_spoons resets the balance (golden_spoons_ledger).
--   * Agents section at the end: settings, EverStore budget summary (vp_hr / cfo, small-cell merge),
--     open Golden Spoons liability, daily budget summary, margin / comparison gate, burnout trend
--     (full / partial / none + 5th team-movement signal), Happiness Debt events, board report with
--     reconciliation, Shadow Balance in 4 lines, assurance tiers and the 15-question check.
-- New in 1.6.13 (Karin 25.10 + Chief of Drive 25.10 — EverStore expansion & privacy):
--   * rpc_everstore_purchase: allows any positive price_golden_spoons > 0 across all 8 categories
--     (cosmetic, time_benefit, health_wellbeing, learning, donation, experience, gift_card,
--     merchandise) and tiers (basic, advanced, premium, custom), records private shop_purchase row,
--     and when category = 'time_benefit' automatically creates a standard HR approved absence /
--     refresh time entry (approved_absence_entry: 'זמן התרעננות / היעדרות מאושרת', נעילת הפרגוד)
--     with zero link to EverStore or item_id.
--   * rpc_everstore_upsert_item (CHRO / vp_hr): add or update catalog items across all 8 categories.
--   * rpc_coordinate_approved_absence (direct manager): coordinate schedule on an approved absence
--     entry without ever seeing its source.
--   * (superseded in 1.6.16: rpc_convert_golden_to_chr is blocked with 422 in v1)
--     Golden Spoons never expire while the employee is active.
--   * Aliases rpc_submit_morning_checkin and rpc_submit_midday_checkin added alongside
--     rpc_morning_checkin / rpc_midday_checkin.
-- New in 1.6.12 (Karin 24.10 + Chief of Drive 24.10):
--   * O-7: PCQ-12 answer scale 1–6 (12 items, all required) → fn_pcq12_score ((mean − 1) / 5.0 × 100).
--   * O-25: rpc_get_board_macro_metrics — tier 5 governance roles (board_chair, board_member,
--     owner_shareholder) read all whole-company organizational averages (TPS-12, spoons, workload /
--     EPWI / PEWI, IHS, Happiness Debt, deprivation tax, CHR Real EBITDA), with N≥5 for regular
--     metrics and N≥10 for sensitive/Shadow Balance metrics, and never any team or individual breakdown.
--   * O-14: rpc_request_crypto_shred (immediate self-request, 0-day wait); rpc_offboard_employee
--     (revokes access & vault immediately, schedules crypto-shredding for terminated_at + 30 days);
--     rpc_revert_offboarding (cancels scheduled shred within 30 days); rpc_run_scheduled_crypto_shred.
--   * O-13: rpc_ledger_append scopes to caller's company (org_id); genesis record seeded on company
--     creation; fn_ledger_verify_chain raises an audit alert and blocks writes on broken chain.
--   * O-19 & O-20: rpc_provision_governance_user (CHRO provisions governance-only users with
--     has_employee_profile = false by default for tier 5); manager vault RPCs (rpc_manager_vault_open,
--     rpc_manager_vault_put, rpc_manager_vault_entries, rpc_manager_vault_close) enforcing direct
--     manager only, office network + company device, inactivity timeout, and automatic wipe.
-- New in 1.6.11 (Karin 24.10 + Chief of Drive 24.10):
--   * O-5: rpc_morning_checkin (average of 0–10 scales, half-points floored in employee's favor,
--     sets spoon_budget.reported_at, awards 2.0 shift golden spoons once per local day) and
--     rpc_midday_checkin (open 12:00–15:00 employee-local, integer delta −4..+4, capped 0..12).
--   * O-6: IHS scoring enabled in fn_questionnaire_score ((mean − 1)/4×100); 403 scoring_not_locked
--     block removed; ihs_team_avg / ihs_respondent_count in rpc_team_aggregate_refresh (N≥5).
--   * O-1, O-2, O-3, O-4, O-18: automatic turnover tier default from org_role.tier + CHRO override;
--     weekly deprivation rule (weekly avg spoons < 5 OR weekly B_t ≥ 0.65); company-wide turnover
--     tier average salary fn_company_tier_avg_salary; full Shadow Balance / Happiness Debt / 12 %
--     deprivation tax / CHR Real EBITDA in rpc_shadow_balance_refresh (N≥10).
--   * O-16 / Q11: 10 golden spoons at signup (rpc_signup_profile), 2 per shift (rpc_morning_checkin),
--     0.5 daily; CHR Coins deferred to v2.
--   * O-8, Q5, C-1, C-2, O-30, O-31 confirmed.
-- New in 1.6.9: no RPC change — no RPC reads or writes users.start_date (O-50: deprecated alias of
-- hire_date, see schema.sql); TPS keeps using fn_tps_wait_start (hire_date).
-- New in 1.6.8 (Karin + Chief of Drive 21.10): week-start BRIDGE (a work_date in a bridge → 422
-- bridge_period; no reminder in a bridge); TPS 30-day wait from fn_tps_wait_start (team join → hire
-- date → exempt); an unknown p_country → 422 unknown_country (the hold stays).
-- New in 1.6.7: PEWI = mean EPWI_time of project members who reported in the company week
-- (rpc_project_pewi: null + suppressed below N=5, audited; also filled in rpc_project_workload);
-- week keys resolve against the week-start history (O-41); company settings expose
-- timezone_status / reminders_on_hold / week_start_effective_from; CHRO confirms the timezone
-- (rpc_company_timezone_confirm); reminders held for companies without a country (O-43).
-- New in 1.6.6 (Chief of Drive, O-40): work_date must lie within [employee-local today − 14,
-- today + 1]; outside → HTTP 422 work_date_out_of_range (SQLSTATE PT422 = PostgREST status 422).
-- New in 1.6.5 (Karin 20.10): week key from the company week start (not ISO Monday); company
-- settings RPCs (CHRO only — TODO who); reminder = company last workday at reminder_time
-- (default 14:00, company-local) with a sender stub; legacy projects non-core (migration).
-- New in 1.6.4 (Karin 20.10): B_t linear 0.41·S + 0.37·O + 0.22·D (sigmoid REMOVED); L(P>5) = 0.75;
-- project.is_core set by the PM on create (rpc_project_create / rpc_project_set_core); weekly
-- self-report adds stress + productivity drop (1–5); co-signer = CHRO only (Q7);
-- rpc_emergency_misuse_close REMOVED (the CHRO never closes; closing = safety manager only).
-- New in 1.6.3: project workload module (EPWI / B_t self-only; PEWI / AIDB / TRR / M_SPOF for
-- the PM at N≥5), soft WIP alert, v2 adapter stub; rpc_project_load REMOVED; emergency misuse
-- sequence (Q5); CHRO reason required (Q6); Cuckoo rolling 30-day reporter window (locked 20.10).
-- New in 1.6.2: emergency types named (lock 13.10); rpc_project_load.load_index = NULL
-- (formula not locked — TODO להשלמה); burnout alert kept on the locked red-alert rule (#4).
-- Deprivation tax system-computed (deprived_count × avg_annual_salary × 0.12).
-- Removed in 1.5 (still removed): fn_cb_check_spoons (<3 / <14% rule), rpc_set_role_cost_multiplier,
--                 zero-argument rpc_pcq12_claim_monthly_reward().
-- =============================================================================

DROP FUNCTION IF EXISTS fn_cb_check_spoons(uuid);
DROP FUNCTION IF EXISTS rpc_project_load(uuid);   -- v1.6.3: replaced by rpc_project_workload
-- v1.6.4 removals / signature changes (Karin 20.10).
DROP FUNCTION IF EXISTS fn_sigmoid(numeric);
DROP FUNCTION IF EXISTS fn_b_t(numeric, numeric, numeric);
DROP FUNCTION IF EXISTS fn_workload_validate(numeric, numeric, numeric, int, int);
DROP FUNCTION IF EXISTS rpc_submit_workload_self_report(numeric, numeric, numeric, int, numeric, numeric);
DROP FUNCTION IF EXISTS rpc_project_assign_member(uuid, uuid);
DROP FUNCTION IF EXISTS rpc_emergency_misuse_close(uuid);
-- v1.6.5 signature / column-name changes (week_start → week_start_date; p_work_date).
DROP FUNCTION IF EXISTS rpc_submit_workload_self_report(numeric, numeric, numeric, int, numeric, numeric);
DROP FUNCTION IF EXISTS rpc_my_workload_indices(date);
DROP FUNCTION IF EXISTS rpc_project_workload(uuid, date);
-- v1.6.7 return-type / signature changes.
DROP FUNCTION IF EXISTS rpc_company_settings_update(int, int, text, time);
DROP FUNCTION IF EXISTS rpc_company_settings();
DROP FUNCTION IF EXISTS rpc_set_role_cost_multiplier(text, numeric);
DROP FUNCTION IF EXISTS rpc_pcq12_claim_monthly_reward();
DROP FUNCTION IF EXISTS rpc_ledger_append(varchar, varchar, varchar, numeric, numeric, uuid, uuid);
DROP FUNCTION IF EXISTS rpc_upsert_employee_value_asset(uuid, numeric, numeric, numeric);
-- v1.6.11 signature change (adds optional p_gaap_reported_ebitda).
DROP FUNCTION IF EXISTS rpc_shadow_balance_refresh(uuid, varchar);
-- v1.6.16 signature change: the participation reward never receives a score (v3 §3.6).
DROP FUNCTION IF EXISTS fn_questionnaire_reward(questionnaire_definition, numeric);

-- ---------------------------------------------------------------------------
-- v1.6.16 agent_settings readers (defined first: other functions read amounts from settings).
-- ---------------------------------------------------------------------------
-- Setting row in effect for a company: the company override, else the system default (company_id NULL).
CREATE OR REPLACE FUNCTION fn_agent_setting_row(p_company uuid, p_key text)
RETURNS agent_settings
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT s.* FROM agent_settings s
   WHERE s.setting_key = p_key AND (s.company_id = p_company OR s.company_id IS NULL)
   ORDER BY (s.company_id IS NULL) ASC
   LIMIT 1
$$;

-- Numeric value in effect (NULL = "לא הוגדר" / unknown key).
CREATE OR REPLACE FUNCTION fn_agent_setting_num(p_company uuid, p_key text)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT (fn_agent_setting_row(p_company, p_key)).value_numeric
$$;

-- Text value in effect (NULL = "לא הוגדר" / unknown key).
CREATE OR REPLACE FUNCTION fn_agent_setting_text(p_company uuid, p_key text)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT (fn_agent_setting_row(p_company, p_key)).value_text
$$;

-- 'set' or 'not_defined' for the value in effect (unknown key → 'not_defined').
CREATE OR REPLACE FUNCTION fn_agent_setting_status(p_company uuid, p_key text)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT COALESCE((fn_agent_setting_row(p_company, p_key)).value_status, 'not_defined')
$$;

REVOKE ALL ON FUNCTION fn_agent_setting_row(uuid, text), fn_agent_setting_num(uuid, text),
                       fn_agent_setting_text(uuid, text), fn_agent_setting_status(uuid, text) FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- Internal: ensure today's spoon_budget for employee-local date (N-1 lazy reset)
-- ALWAYS sets to 12 when creating the local-day row; no debt carryover (Q-008).
-- Farming cost 0 does not refill (handled in assign). No refill on reset beyond 12.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_ensure_local_spoon_budget(p_user_id uuid)
RETURNS spoon_budget
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_local_date date;
  v_row spoon_budget;
BEGIN
  v_local_date := fn_user_local_date(p_user_id);
  IF v_local_date IS NULL THEN
    RAISE EXCEPTION 'anti_get_blocked'
      USING ERRCODE = '42501',
            DETAIL = 'http_hint=403;code=anti_get_blocked',
            HINT = 'anti_get_blocked';
  END IF;

  INSERT INTO spoon_budget (user_id, budget_date, current_spoon_count, daily_baseline_capacity, updated_at)
  VALUES (p_user_id, v_local_date, 12, 12, clock_timestamp())
  ON CONFLICT (user_id, budget_date) DO UPDATE
    SET updated_at = spoon_budget.updated_at  -- no-op touch; keep existing count for same local day
  RETURNING * INTO v_row;

  -- Re-select under lock for callers that need FOR UPDATE semantics
  SELECT * INTO v_row
    FROM spoon_budget
   WHERE user_id = p_user_id AND budget_date = v_local_date;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION fn_ensure_local_spoon_budget(uuid) FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- Internal: Circuit Breaker v1.5 — spoons only, NO HRV (locked 15:39 / 16:02)
--   remaining 4–5 → Fighting blocked (403 circuit_breaker_active)
--   remaining ≤3  → employee goes home: no new tasks (403 circuit_breaker_active)
--   Farming at 4–5 stays allowed. The CB never touches questionnaires or the shop.
-- Lock #1 (Karin, 2026-10-20): at ≤3 spoons ALL tasks are blocked, Farming included.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_cb_check_task(p_spoons int, p_task_kind task_kind_enum)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_spoons IS NULL OR p_spoons <= 3 THEN
    PERFORM fn_raise_business('circuit_breaker_active');
  END IF;
  IF p_task_kind = 'fighting' AND p_spoons <= 5 THEN
    PERFORM fn_raise_business('circuit_breaker_active');
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Internal: write the locked go-home entry once per employee-local day.
-- Text only 'יציאה מוקדמת מאושרת' + time; no reason; full workday; no sick day.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_log_early_leave(p_user_id uuid)
RETURNS early_leave_log
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_row early_leave_log;
  v_local_date date := fn_user_local_date(p_user_id);
BEGIN
  INSERT INTO early_leave_log (user_id, local_date)
  VALUES (p_user_id, v_local_date)
  ON CONFLICT (user_id, local_date) DO NOTHING
  RETURNING * INTO v_row;

  IF v_row.log_id IS NULL THEN
    SELECT * INTO v_row FROM early_leave_log WHERE user_id = p_user_id AND local_date = v_local_date;
  END IF;
  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION fn_log_early_leave(uuid) FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- rpc_daily_reset_spoons — ALWAYS set to 12 at employee local midnight day (N-1 / Q-008)
-- No debt carryover. Keyed to (now() AT TIME ZONE u.timezone)::date — not org UTC.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_daily_reset_spoons(p_user_id uuid DEFAULT NULL)
RETURNS spoon_budget
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid uuid := COALESCE(p_user_id, auth.uid());
  v_local_date date;
  v_row spoon_budget;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'consent_required'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=consent_required', HINT = 'consent_required';
  END IF;

  IF auth.uid() IS NOT NULL AND auth.uid() <> v_uid AND fn_app_role() NOT IN ('manager', 'vp_hr') THEN
    RAISE EXCEPTION 'anti_get_blocked'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=anti_get_blocked', HINT = 'anti_get_blocked';
  END IF;

  v_local_date := fn_user_local_date(v_uid);
  IF v_local_date IS NULL THEN
    RAISE EXCEPTION 'anti_get_blocked'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=anti_get_blocked', HINT = 'anti_get_blocked';
  END IF;

  INSERT INTO spoon_budget (user_id, budget_date, current_spoon_count, daily_baseline_capacity, updated_at)
  VALUES (v_uid, v_local_date, 12, 12, clock_timestamp())
  ON CONFLICT (user_id, budget_date) DO UPDATE
    SET current_spoon_count = 12,          -- ALWAYS 12; no carryover
        daily_baseline_capacity = 12,
        updated_at = clock_timestamp()
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION rpc_daily_reset_spoons(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_daily_reset_spoons(uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- rpc_daily_reset_spoons_job — scheduled/internal: reset users whose local date
-- has no budget row yet (crossed local midnight). service_role / cron.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_daily_reset_spoons_job()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid uuid;
  v_local_date date;
  v_count int := 0;
BEGIN
  FOR v_uid, v_local_date IN
    SELECT u.user_id, (clock_timestamp() AT TIME ZONE u.timezone)::date
      FROM users u
     WHERE u.timezone IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM spoon_budget sb
          WHERE sb.user_id = u.user_id
            AND sb.budget_date = (clock_timestamp() AT TIME ZONE u.timezone)::date
       )
  LOOP
    INSERT INTO spoon_budget (user_id, budget_date, current_spoon_count, daily_baseline_capacity, updated_at)
    VALUES (v_uid, v_local_date, 12, 12, clock_timestamp())
    ON CONFLICT (user_id, budget_date) DO NOTHING;
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION rpc_daily_reset_spoons_job() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_daily_reset_spoons_job() TO service_role;

-- ---------------------------------------------------------------------------
-- rpc_assign_task — compute s_final, Circuit Breaker v1.5, debit, insert.
-- Client does NOT send s_base for pricing — RPC computes from task_kind/flags.
-- Farming s_base=0 does NOT refill spoons (debit 0).
-- When the debit brings the day to ≤3 the go-home entry is logged automatically.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_assign_task(
  p_assignee_id     uuid,
  p_task_name       varchar,
  p_task_kind       task_kind_enum DEFAULT 'fighting',
  p_high_friction   boolean DEFAULT false,
  p_chronic_pain    boolean DEFAULT false,  -- TODO ADR-051: numeric pain rules open
  p_modifiers       jsonb DEFAULT '[]'::jsonb,
  p_shadow_work     boolean DEFAULT false,
  p_shadow_work_tag varchar DEFAULT NULL,
  p_external_ref    varchar DEFAULT NULL
)
RETURNS task
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_s_base     smallint;
  v_mod_sum    smallint := 0;
  v_cost       smallint;
  v_budget     spoon_budget;
  v_row        task;
  v_elem       jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    PERFORM fn_raise_business('anti_get_blocked');
  END IF;

  IF p_task_kind = 'farming' THEN
    v_s_base := 0;  -- Farming does NOT refill; cost 0
  ELSIF p_high_friction THEN
    v_s_base := 2;
  ELSE
    v_s_base := 1;
  END IF;

  -- TODO ADR-051 / ADR-004: chronic pain numeric modifiers — open; flag stored only
  IF p_modifiers IS NOT NULL AND jsonb_typeof(p_modifiers) = 'array' THEN
    FOR v_elem IN SELECT * FROM jsonb_array_elements(p_modifiers)
    LOOP
      IF jsonb_typeof(v_elem) = 'number' THEN
        v_mod_sum := v_mod_sum + GREATEST(v_elem::text::int, 0);
      ELSIF v_elem ? 'delta' THEN
        v_mod_sum := v_mod_sum + GREATEST((v_elem->>'delta')::int, 0);
      END IF;
    END LOOP;
  END IF;

  v_cost := LEAST(v_s_base + v_mod_sum, 4)::smallint;

  PERFORM fn_ensure_local_spoon_budget(p_assignee_id);
  SELECT * INTO v_budget
    FROM spoon_budget
   WHERE user_id = p_assignee_id
     AND budget_date = fn_user_local_date(p_assignee_id)
   FOR UPDATE;

  PERFORM fn_cb_check_task(v_budget.current_spoon_count, p_task_kind);

  IF v_cost > v_budget.current_spoon_count THEN
    -- Distinct from CB: anti_get_blocked (Q-001 / N-1–N-3 API v2) → HTTP 403
    PERFORM fn_raise_business('anti_get_blocked');
  END IF;

  IF v_cost > 0 THEN
    UPDATE spoon_budget
       SET current_spoon_count = current_spoon_count - v_cost,
           updated_at = clock_timestamp()
     WHERE budget_id = v_budget.budget_id
    RETURNING * INTO v_budget;
  END IF;

  INSERT INTO task (
    assignee_id, assigner_id, task_name, task_kind, s_base, modifiers,
    high_friction, chronic_pain_flag, s_modifier_sum,
    shadow_work_flag, shadow_work_tag, external_ref, pacing_status
  ) VALUES (
    p_assignee_id, auth.uid(), p_task_name, p_task_kind, v_s_base, COALESCE(p_modifiers, '[]'::jsonb),
    COALESCE(p_high_friction, false), COALESCE(p_chronic_pain, false), v_mod_sum,
    COALESCE(p_shadow_work, false), p_shadow_work_tag, p_external_ref, 'ACTIVE'
  )
  RETURNING * INTO v_row;

  IF v_budget.current_spoon_count <= 3 THEN
    PERFORM fn_log_early_leave(p_assignee_id);
  END IF;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION rpc_assign_task(uuid, varchar, task_kind_enum, boolean, boolean, jsonb, boolean, varchar, varchar) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_assign_task(uuid, varchar, task_kind_enum, boolean, boolean, jsonb, boolean, varchar, varchar) TO authenticated;

-- ---------------------------------------------------------------------------
-- rpc_log_go_home — employee confirms going home (≤3 spoons today).
-- Returns the locked entry; no reason parameter by design.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_log_go_home()
RETURNS early_leave_log
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_budget spoon_budget;
BEGIN
  IF v_uid IS NULL THEN
    PERFORM fn_raise_business('anti_get_blocked');
  END IF;
  v_budget := fn_ensure_local_spoon_budget(v_uid);
  IF v_budget.current_spoon_count > 3 THEN
    PERFORM fn_raise_business('anti_get_blocked');
  END IF;
  -- Going home is an actual spoon report for today (counts toward the team respondent N).
  UPDATE spoon_budget SET reported_at = COALESCE(reported_at, clock_timestamp())
   WHERE budget_id = v_budget.budget_id;
  PERFORM fn_sync_employee_deprived(v_uid);
  RETURN fn_log_early_leave(v_uid);
END;
$$;

REVOKE ALL ON FUNCTION rpc_log_go_home() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_log_go_home() TO authenticated;

-- ---------------------------------------------------------------------------
-- v1.6.11 (Karin 24.10, O-5 / Q5 / O-16): Morning & midday check-in RPCs
--   * Morning check-in: simple average of the morning scales (0–10), with half-point / fractional
--     scores (e.g. 4.5) rounded in the employee's favor (floor(score) → less spoon deduction /
--     fewer spoons deducted: 0–4 → 0, 5 → −2, 6–7 → −3, 8–10 → −4), setting spoon_budget.reported_at
--     and awarding the 2.0 golden spoons shift-start allowance once per local workday (O-16).
--   * Midday check-in: open between 12:00 and 15:00 (employee local time), directly adjusts
--     available spoons by an integer delta from −4 to +4, capped at 0..12, without recalculating
--     the morning score.
--   * Q5: "Never show the deduction" applies ONLY to check-in survey answer options; task spoon
--     costs (0, 1, 2) and golden spoon reward amounts remain visible to the employee.
-- ---------------------------------------------------------------------------

-- Compute the simple average of the morning 0–10 scales (pain, mental, mood); rejects empty or out-of-range inputs.
CREATE OR REPLACE FUNCTION fn_morning_checkin_score(p_scales int[])
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_clean int[];
BEGIN
  IF p_scales IS NULL THEN
    RAISE EXCEPTION 'checkin_invalid_scales'
      USING ERRCODE = '22023', DETAIL = 'http_hint=400;code=checkin_invalid_scales', HINT = 'checkin_invalid_scales';
  END IF;
  SELECT array_agg(x) INTO v_clean FROM unnest(p_scales) x WHERE x IS NOT NULL;
  IF v_clean IS NULL OR cardinality(v_clean) < 1
     OR EXISTS (SELECT 1 FROM unnest(v_clean) x WHERE x < 0 OR x > 10) THEN
    RAISE EXCEPTION 'checkin_invalid_scales'
      USING ERRCODE = '22023', DETAIL = 'http_hint=400;code=checkin_invalid_scales', HINT = 'checkin_invalid_scales';
  END IF;
  RETURN (SELECT round(avg(x::numeric), 4) FROM unnest(v_clean) x);
END;
$$;

-- Spoons deducted for a morning average score (0–10). Half-point / fractional scores (e.g. 4.5, 5.5, 7.5)
-- are floored in the employee's favor (fewer spoons deducted): 0–4 → 0, 5 → 2, 6–7 → 3, 8–10 → 4.
CREATE OR REPLACE FUNCTION fn_morning_spoon_deduction(p_avg_score numeric)
RETURNS int
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_avg_score IS NULL THEN 0
    WHEN floor(p_avg_score)::int <= 4 THEN 0
    WHEN floor(p_avg_score)::int = 5  THEN 2
    WHEN floor(p_avg_score)::int <= 7 THEN 3
    ELSE 4
  END
$$;

-- Is an employee-local time inside the locked 12:00–15:00 midday check-in window (inclusive)?
CREATE OR REPLACE FUNCTION fn_is_midday_window(p_local_time time)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_local_time IS NOT NULL AND p_local_time >= TIME '12:00' AND p_local_time <= TIME '15:00'
$$;

-- Morning / shift-start check-in: accepts p_scales int[] (or p_pain / p_mental / p_mood), sets today's
-- spoons (12 − deduction) and reported_at, and credits 2.0 golden spoons once per local workday (O-16).
CREATE OR REPLACE FUNCTION rpc_morning_checkin(
  p_scales int[] DEFAULT NULL,
  p_pain   int   DEFAULT NULL,
  p_mental int   DEFAULT NULL,
  p_mood   int   DEFAULT NULL
)
RETURNS spoon_budget
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid     uuid := auth.uid();
  v_arr     int[];
  v_avg     numeric;
  v_ded     int;
  v_spoons  int;
  v_budget  spoon_budget;
  v_shift_reward numeric;
BEGIN
  IF v_uid IS NULL OR NOT fn_has_employee_profile(v_uid) THEN
    PERFORM fn_raise_business('anti_get_blocked');
  END IF;

  v_arr := COALESCE(p_scales, ARRAY[p_pain, p_mental, p_mood]);
  v_avg := fn_morning_checkin_score(v_arr);
  v_ded := fn_morning_spoon_deduction(v_avg);
  v_spoons := GREATEST(0, LEAST(12, 12 - v_ded));

  PERFORM fn_ensure_local_spoon_budget(v_uid);
  SELECT * INTO v_budget
    FROM spoon_budget
   WHERE user_id = v_uid AND budget_date = fn_user_local_date(v_uid)
   FOR UPDATE;

  -- O-16 / Q11: golden spoons per shift (once per local workday; CHR Coins stay 0 / v2).
  -- v1.6.16: amount = agent_settings.golden_spoons_per_shift (default 2.0); "לא הוגדר" → nothing credited.
  v_shift_reward := COALESCE(fn_agent_setting_num((SELECT u.company_id FROM users u WHERE u.user_id = v_uid),
                                                  'golden_spoons_per_shift'), 0);
  IF NOT v_budget.shift_golden_awarded AND v_shift_reward > 0 THEN
    INSERT INTO avatar_state (user_id, golden_spoons)
    VALUES (v_uid, v_shift_reward)
    ON CONFLICT (user_id) DO UPDATE
       SET golden_spoons = avatar_state.golden_spoons + v_shift_reward,
           updated_at = clock_timestamp();
  END IF;

  UPDATE spoon_budget
     SET current_spoon_count  = v_spoons,
         reported_at          = clock_timestamp(),
         row_source           = 'app',
         shift_golden_awarded = true,
         updated_at           = clock_timestamp()
   WHERE budget_id = v_budget.budget_id
  RETURNING * INTO v_budget;

  IF v_budget.current_spoon_count <= 3 THEN
    PERFORM fn_log_early_leave(v_uid);
  END IF;
  PERFORM fn_sync_employee_deprived(v_uid);
  RETURN v_budget;
END;
$$;

REVOKE ALL ON FUNCTION rpc_morning_checkin(int[], int, int, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_morning_checkin(int[], int, int, int) TO authenticated;

-- Midday check-in (O-5): open 12:00–15:00 employee-local time; directly adjusts available spoons by an
-- integer delta in −4..+4, clamped to 0..12, without recalculating the morning score.
CREATE OR REPLACE FUNCTION rpc_midday_checkin(p_delta int)
RETURNS spoon_budget
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid        uuid := auth.uid();
  v_tz         text;
  v_local_time time;
  v_budget     spoon_budget;
BEGIN
  IF v_uid IS NULL OR NOT fn_has_employee_profile(v_uid) THEN
    PERFORM fn_raise_business('anti_get_blocked');
  END IF;
  IF p_delta IS NULL OR p_delta < -4 OR p_delta > 4 THEN
    RAISE EXCEPTION 'checkin_invalid_delta'
      USING ERRCODE = '22023', DETAIL = 'http_hint=400;code=checkin_invalid_delta', HINT = 'checkin_invalid_delta';
  END IF;

  SELECT u.timezone INTO v_tz FROM users u WHERE u.user_id = v_uid;
  v_local_time := (clock_timestamp() AT TIME ZONE v_tz)::time;
  IF NOT fn_is_midday_window(v_local_time) THEN
    PERFORM fn_raise_business('midday_checkin_outside_window');
  END IF;

  PERFORM fn_ensure_local_spoon_budget(v_uid);
  SELECT * INTO v_budget
    FROM spoon_budget
   WHERE user_id = v_uid AND budget_date = fn_user_local_date(v_uid)
   FOR UPDATE;

  UPDATE spoon_budget
     SET current_spoon_count = GREATEST(0, LEAST(12, current_spoon_count + p_delta)),
         reported_at         = COALESCE(reported_at, clock_timestamp()),
         row_source          = 'app',
         updated_at          = clock_timestamp()
   WHERE budget_id = v_budget.budget_id
  RETURNING * INTO v_budget;

  IF v_budget.current_spoon_count <= 3 THEN
    PERFORM fn_log_early_leave(v_uid);
  END IF;
  PERFORM fn_sync_employee_deprived(v_uid);
  RETURN v_budget;
END;
$$;

REVOKE ALL ON FUNCTION rpc_midday_checkin(int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_midday_checkin(int) TO authenticated;

-- Alias: rpc_submit_morning_checkin → rpc_morning_checkin (O-5)
CREATE OR REPLACE FUNCTION rpc_submit_morning_checkin(
  p_scales int[] DEFAULT NULL,
  p_pain   int   DEFAULT NULL,
  p_mental int   DEFAULT NULL,
  p_mood   int   DEFAULT NULL
)
RETURNS spoon_budget
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT * FROM rpc_morning_checkin(p_scales, p_pain, p_mental, p_mood)
$$;

-- Alias: rpc_submit_midday_checkin → rpc_midday_checkin (O-5)
CREATE OR REPLACE FUNCTION rpc_submit_midday_checkin(p_delta int)
RETURNS spoon_budget
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT * FROM rpc_midday_checkin(p_delta)
$$;

REVOKE ALL ON FUNCTION rpc_submit_morning_checkin(int[], int, int, int), rpc_submit_midday_checkin(int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_submit_morning_checkin(int[], int, int, int), rpc_submit_midday_checkin(int) TO authenticated;

-- ---------------------------------------------------------------------------
-- rpc_upsert_journal_ciphertext — consent required (Q-002)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_upsert_journal_ciphertext(
  p_entry_id           uuid DEFAULT NULL,
  p_encrypted_blob     bytea DEFAULT NULL,
  p_encryption_iv      bytea DEFAULT NULL,
  p_encryption_tag     bytea DEFAULT NULL,
  p_encryption_version smallint DEFAULT 1,
  p_prompt_code        varchar DEFAULT NULL,
  p_shadow_work_flag   boolean DEFAULT false,
  p_shadow_work_tag    varchar DEFAULT NULL,
  p_is_clinical        boolean DEFAULT false
)
RETURNS journal_entry
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row journal_entry;
  v_consent boolean;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'consent_required'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=consent_required', HINT = 'consent_required';
  END IF;

  SELECT consent_vault INTO v_consent FROM users WHERE user_id = v_uid;
  IF NOT COALESCE(v_consent, false) THEN
    RAISE EXCEPTION 'consent_required'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=consent_required', HINT = 'consent_required';
  END IF;

  IF p_encrypted_blob IS NULL OR p_encryption_iv IS NULL THEN
    RAISE EXCEPTION 'vault_sealed'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=vault_sealed', HINT = 'vault_sealed';
  END IF;

  IF p_entry_id IS NULL THEN
    INSERT INTO journal_entry (
      user_id, prompt_code, encrypted_blob, encryption_iv, encryption_tag,
      encryption_version, shadow_work_flag, shadow_work_tag, is_clinical
    ) VALUES (
      v_uid, p_prompt_code, p_encrypted_blob, p_encryption_iv, p_encryption_tag,
      COALESCE(p_encryption_version, 1), COALESCE(p_shadow_work_flag, false),
      p_shadow_work_tag, COALESCE(p_is_clinical, false)
    )
    RETURNING * INTO v_row;
  ELSE
    UPDATE journal_entry
       SET encrypted_blob = p_encrypted_blob,
           encryption_iv = p_encryption_iv,
           encryption_tag = p_encryption_tag,
           encryption_version = COALESCE(p_encryption_version, encryption_version),
           prompt_code = COALESCE(p_prompt_code, prompt_code),
           shadow_work_flag = COALESCE(p_shadow_work_flag, shadow_work_flag),
           shadow_work_tag = COALESCE(p_shadow_work_tag, shadow_work_tag),
           is_clinical = COALESCE(p_is_clinical, is_clinical)
     WHERE entry_id = p_entry_id AND user_id = v_uid
    RETURNING * INTO v_row;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'vault_sealed'
        USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=vault_sealed', HINT = 'vault_sealed';
    END IF;
  END IF;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION rpc_upsert_journal_ciphertext(uuid, bytea, bytea, bytea, smallint, varchar, boolean, varchar, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_upsert_journal_ciphertext(uuid, bytea, bytea, bytea, smallint, varchar, boolean, varchar, boolean) TO authenticated;

-- ---------------------------------------------------------------------------
-- rpc_upsert_anchor_ciphertext — consent required
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_upsert_anchor_ciphertext(
  p_anchor_id          uuid DEFAULT NULL,
  p_encrypted_blob     bytea DEFAULT NULL,
  p_encryption_iv      bytea DEFAULT NULL,
  p_encryption_tag     bytea DEFAULT NULL,
  p_encryption_version smallint DEFAULT 1,
  p_lighting_type      varchar DEFAULT NULL,
  p_territory_schema   varchar DEFAULT NULL,
  p_exposure_gate      exposure_gate_enum DEFAULT 'FILTERED'
)
RETURNS anchor
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row anchor;
  v_consent boolean;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'consent_required'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=consent_required', HINT = 'consent_required';
  END IF;

  SELECT consent_vault INTO v_consent FROM users WHERE user_id = v_uid;
  IF NOT COALESCE(v_consent, false) THEN
    RAISE EXCEPTION 'consent_required'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=consent_required', HINT = 'consent_required';
  END IF;

  IF p_encrypted_blob IS NULL OR p_encryption_iv IS NULL THEN
    RAISE EXCEPTION 'vault_sealed'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=vault_sealed', HINT = 'vault_sealed';
  END IF;

  IF p_anchor_id IS NULL THEN
    INSERT INTO anchor (
      user_id, lighting_type, territory_schema, exposure_gate,
      encrypted_blob, encryption_iv, encryption_tag, encryption_version
    ) VALUES (
      v_uid, p_lighting_type, p_territory_schema, COALESCE(p_exposure_gate, 'FILTERED'),
      p_encrypted_blob, p_encryption_iv, p_encryption_tag, COALESCE(p_encryption_version, 1)
    )
    RETURNING * INTO v_row;
  ELSE
    UPDATE anchor
       SET encrypted_blob = p_encrypted_blob,
           encryption_iv = p_encryption_iv,
           encryption_tag = p_encryption_tag,
           encryption_version = COALESCE(p_encryption_version, encryption_version),
           lighting_type = COALESCE(p_lighting_type, lighting_type),
           territory_schema = COALESCE(p_territory_schema, territory_schema),
           exposure_gate = COALESCE(p_exposure_gate, exposure_gate),
           updated_at = clock_timestamp()
     WHERE anchor_id = p_anchor_id AND user_id = v_uid
    RETURNING * INTO v_row;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'vault_sealed'
        USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=vault_sealed', HINT = 'vault_sealed';
    END IF;
  END IF;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION rpc_upsert_anchor_ciphertext(uuid, bytea, bytea, bytea, smallint, varchar, varchar, exposure_gate_enum) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_upsert_anchor_ciphertext(uuid, bytea, bytea, bytea, smallint, varchar, varchar, exposure_gate_enum) TO authenticated;

-- ---------------------------------------------------------------------------
-- Cuckoo (locked 2026-10-12 16:14 + 60-second window)
-- fn_cuckoo_raise — system path (service_role): ≥10 ACTUAL contributors in the team
-- (lock #3), direct manager from users.reports_to (solid line), pseudonym snapshot. The employee sees it first (base table RLS).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_cuckoo_raise(
  p_target_user_id uuid,
  p_trigger_reason varchar,
  p_nlp_flag_codes jsonb DEFAULT '[]'::jsonb
)
RETURNS cuckoo_alert
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_user users%ROWTYPE;
  v_row  cuckoo_alert;
  v_id   uuid := gen_random_uuid();
  v_exp  timestamptz := clock_timestamp() + interval '60 seconds';
BEGIN
  SELECT * INTO v_user FROM users WHERE user_id = p_target_user_id;
  IF NOT FOUND OR v_user.reports_to IS NULL THEN
    PERFORM fn_raise_business('anti_get_blocked');
  END IF;
  IF v_user.display_pseudonym IS NULL OR length(trim(v_user.display_pseudonym)) = 0 THEN
    PERFORM fn_raise_business('pseudonym_required');
  END IF;

  PERFORM fn_assert_privacy_threshold(
    fn_cuckoo_recent_reporters(v_user.company_id, v_user.department),   -- rolling 30 days (locked 20.10)
    'cuckoo');

  INSERT INTO cuckoo_alert (
    alert_id, manager_id, target_user_id, target_pseudonym, org_id, department,
    trigger_reason, nlp_flag_codes, sovereign_veto_window_expiry, logic_hash
  ) VALUES (
    v_id, v_user.reports_to, p_target_user_id, v_user.display_pseudonym, v_user.company_id,
    v_user.department, p_trigger_reason, COALESCE(p_nlp_flag_codes, '[]'::jsonb), v_exp,
    fn_sha256_hex(jsonb_build_object(
      'alert_id', v_id, 'manager_id', v_user.reports_to, 'target_pseudonym', v_user.display_pseudonym,
      'trigger_reason', p_trigger_reason, 'expiry', v_exp)::text)
  )
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION fn_cuckoo_raise(uuid, varchar, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_cuckoo_raise(uuid, varchar, jsonb) TO service_role;

-- rpc_cuckoo_veto — employee sovereign veto within the 60-second window
CREATE OR REPLACE FUNCTION rpc_cuckoo_veto(p_alert_id uuid)
RETURNS cuckoo_alert
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_row cuckoo_alert;
BEGIN
  UPDATE cuckoo_alert
     SET status = 'VETOED_BY_EMPLOYEE'
   WHERE alert_id = p_alert_id
     AND target_user_id = auth.uid()
     AND status = 'VETO_WINDOW_ACTIVE'
     AND sovereign_veto_window_expiry > clock_timestamp()
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    PERFORM fn_raise_business('anti_get_blocked');
  END IF;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION rpc_cuckoo_veto(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_cuckoo_veto(uuid) TO authenticated;

-- rpc_cuckoo_commit_expired_job — cron: mark windows that passed without veto as
-- EXPIRED_COMMITTED (delivery to the manager view does not depend on this job).
CREATE OR REPLACE FUNCTION rpc_cuckoo_commit_expired_job()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_n int;
BEGIN
  UPDATE cuckoo_alert
     SET status = 'EXPIRED_COMMITTED'
   WHERE status = 'VETO_WINDOW_ACTIVE'
     AND sovereign_veto_window_expiry <= clock_timestamp();
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;

REVOKE ALL ON FUNCTION rpc_cuckoo_commit_expired_job() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_cuckoo_commit_expired_job() TO service_role;

-- Lock #8: pseudonyms are system-assigned (schema trigger trg_users_pseudonym).
-- The 1.5 self-set RPC is removed; there is no path for an employee to choose or edit one.
DROP FUNCTION IF EXISTS rpc_set_display_pseudonym(varchar);

-- ---------------------------------------------------------------------------
-- rpc_ledger_append — WORM insert only; hash chain computed by trigger.
-- Subject = HMAC pseudonym (never user id). deprivation_tax_cost = system snapshot
-- of the latest team_aggregate.deprivation_tax_amount for (org, department).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_ledger_append(
  p_event_type       varchar,
  p_amount_a         numeric DEFAULT NULL,
  p_amount_b         numeric DEFAULT NULL,
  p_subject_user_id  uuid DEFAULT NULL,
  p_org_id           uuid DEFAULT NULL,
  p_department       varchar DEFAULT NULL
)
RETURNS manager_ledger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row manager_ledger;
  v_tax numeric(14, 2);
BEGIN
  IF v_uid IS NULL OR fn_app_role() NOT IN ('manager', 'vp_hr', 'legal_ethics') THEN
    PERFORM fn_raise_business('anti_get_blocked');
  END IF;

  p_org_id := COALESCE(p_org_id, fn_my_company());

  IF p_org_id IS NOT NULL AND p_department IS NOT NULL THEN
    SELECT t.deprivation_tax_amount INTO v_tax
      FROM team_aggregate t
     WHERE t.org_id = p_org_id AND t.department = p_department
     ORDER BY t.calculated_at DESC
     LIMIT 1;
  END IF;

  INSERT INTO manager_ledger (
    manager_id, org_id, department, event_type, amount_a, amount_b,
    deprivation_tax_cost, subject_pseudonym, canonical_payload, current_hash
  ) VALUES (
    v_uid, p_org_id, p_department, p_event_type, p_amount_a, p_amount_b,
    v_tax, fn_subject_pseudonym(p_subject_user_id), '', repeat('0', 64)  -- overwritten by trigger
  )
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION rpc_ledger_append(varchar, numeric, numeric, uuid, uuid, varchar) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_ledger_append(varchar, numeric, numeric, uuid, uuid, varchar) TO authenticated;

-- Crypto-shredding & Offboarding Retention (lock #7 + v1.6.12 Karin 24.10, O-14):
--   (1) Self-request (rpc_request_crypto_shred / rpc_crypto_shred_pseudonym_key by the employee
--       herself): IMMEDIATE crypto-shredding (0-day wait).
--   (2) Automatic offboarding (rpc_offboard_employee triggered by HR/payroll termination event):
--       revokes access (employment_ended_at set, consent_vault = false) and wipes manager vault
--       immediately on termination date, and schedules crypto-shredding for terminated_at + 30 days
--       (cancellable via rpc_revert_offboarding if termination is reverted within those 30 days).
--       rpc_run_scheduled_crypto_shred shreds keys whose 30-day wait has elapsed.
-- HR, managers at any tier, the CEO and service callers cannot directly shred an active
-- employee's key → 403 crypto_shred_forbidden. Ledger rows and chain stay intact.

-- Internal: destroy one subject's HMAC key immediately. No grant to any client role.
CREATE OR REPLACE FUNCTION fn_crypto_shred_pseudonym_key(p_user_id uuid)
RETURNS pseudonym_key
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_row pseudonym_key;
BEGIN
  INSERT INTO pseudonym_key (user_id, key_material, scheduled_shred_at, shredded_at)
  VALUES (p_user_id, NULL, NULL, clock_timestamp())
  ON CONFLICT (user_id) DO UPDATE
     SET key_material       = NULL,
         scheduled_shred_at = NULL,
         shredded_at        = COALESCE(pseudonym_key.shredded_at, clock_timestamp())
  RETURNING * INTO v_row;
  -- v1.6.17 (A-8): the internal event ↔ employee link is only needed for a reversal, impossible after shredding.
  DELETE FROM happiness_debt_leaver_link l WHERE l.user_id = p_user_id;
  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION fn_crypto_shred_pseudonym_key(uuid) FROM PUBLIC;

-- Internal: schedule crypto-shredding for p_terminated_at + 30 days (O-14).
CREATE OR REPLACE FUNCTION fn_schedule_crypto_shred(p_user_id uuid, p_terminated_at timestamptz)
RETURNS pseudonym_key
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_row pseudonym_key;
BEGIN
  INSERT INTO pseudonym_key (user_id, key_material, scheduled_shred_at)
  VALUES (p_user_id, gen_random_bytes(32), p_terminated_at + interval '30 days')
  ON CONFLICT (user_id) DO UPDATE
     SET scheduled_shred_at = CASE
           WHEN pseudonym_key.shredded_at IS NULL THEN p_terminated_at + interval '30 days'
           ELSE NULL
         END
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION fn_schedule_crypto_shred(uuid, timestamptz) FROM PUBLIC;

-- Path 1 (O-14): self-request by the employee herself → immediate crypto-shredding (0-day wait).
-- Anyone else (incl. HR / managers / CEO / no JWT) → 403 crypto_shred_forbidden.
DROP FUNCTION IF EXISTS rpc_crypto_shred_pseudonym_key(uuid);
CREATE OR REPLACE FUNCTION rpc_crypto_shred_pseudonym_key(p_user_id uuid DEFAULT NULL)
RETURNS pseudonym_key
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF auth.uid() IS NULL OR (p_user_id IS NOT NULL AND p_user_id <> auth.uid()) THEN
    PERFORM fn_raise_business('crypto_shred_forbidden');
  END IF;
  RETURN fn_crypto_shred_pseudonym_key(auth.uid());
END;
$$;

-- O-14 canonical alias: rpc_request_crypto_shred (employee self-request, immediate 0-day wait).
CREATE OR REPLACE FUNCTION rpc_request_crypto_shred(p_user_id uuid DEFAULT NULL)
RETURNS pseudonym_key
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT * FROM rpc_crypto_shred_pseudonym_key(p_user_id)
$$;

REVOKE ALL ON FUNCTION rpc_crypto_shred_pseudonym_key(uuid), rpc_request_crypto_shred(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_crypto_shred_pseudonym_key(uuid), rpc_request_crypto_shred(uuid) TO authenticated;

-- Path 2 (O-14): offboarding trigger on users.employment_ended_at.
--   * When employment_ended_at is set: revoke vault consent immediately, schedule crypto-shredding
--     for employment_ended_at + 30 days (and if employment_ended_at is already >= 30 days in the past,
--     shred immediately).
--   * When employment_ended_at is cleared (termination reverted within 30 days before shred): cancel
--     the scheduled crypto-shredding.
CREATE OR REPLACE FUNCTION fn_users_offboarding_shred()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NEW.employment_ended_at IS NOT NULL AND (OLD.employment_ended_at IS NULL OR NEW.employment_ended_at IS DISTINCT FROM OLD.employment_ended_at) THEN
    UPDATE users SET consent_vault = false WHERE user_id = NEW.user_id AND consent_vault IS TRUE;
    PERFORM fn_schedule_crypto_shred(NEW.user_id, NEW.employment_ended_at);
    IF NEW.employment_ended_at + interval '30 days' <= clock_timestamp() THEN
      PERFORM fn_crypto_shred_pseudonym_key(NEW.user_id);
    END IF;
  ELSIF OLD.employment_ended_at IS NOT NULL AND NEW.employment_ended_at IS NULL THEN
    UPDATE pseudonym_key
       SET scheduled_shred_at = NULL
     WHERE user_id = NEW.user_id AND shredded_at IS NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_offboarding_shred ON users;
CREATE TRIGGER trg_users_offboarding_shred
    AFTER UPDATE OF employment_ended_at ON users
    FOR EACH ROW
    EXECUTE FUNCTION fn_users_offboarding_shred();

-- rpc_offboard_employee (O-14): triggered by HR/payroll termination event (service_role, or CHRO vp_hr
-- of the same company). Revokes access & vault immediately on termination date and schedules
-- crypto-shredding for terminated_at + 30 days.
DROP FUNCTION IF EXISTS rpc_offboard_employee(uuid);
CREATE OR REPLACE FUNCTION rpc_offboard_employee(
  p_user_id       uuid,
  p_terminated_at timestamptz DEFAULT NULL
)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_ended timestamptz;
BEGIN
  IF current_user = 'authenticated' THEN
    IF auth.uid() IS NULL OR NOT fn_is_chro() OR NOT EXISTS (
         SELECT 1 FROM users u WHERE u.user_id = p_user_id AND u.company_id = fn_my_company()) THEN
      PERFORM fn_raise_business('anti_get_blocked');
    END IF;
  END IF;

  UPDATE users
     SET employment_ended_at = COALESCE(employment_ended_at, p_terminated_at, clock_timestamp()),
         consent_vault       = false
   WHERE user_id = p_user_id
  RETURNING employment_ended_at INTO v_ended;

  IF v_ended IS NULL THEN
    PERFORM fn_raise_business('anti_get_blocked');
  END IF;

  PERFORM fn_audit_view('employee_offboarded',
                        jsonb_build_object('user_id', p_user_id, 'terminated_at', v_ended,
                                           'scheduled_shred_at', v_ended + interval '30 days'),
                        p_user_id);
  RETURN v_ended;
END;
$$;

REVOKE ALL ON FUNCTION rpc_offboard_employee(uuid, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_offboard_employee(uuid, timestamptz) TO service_role;

-- rpc_revert_offboarding (O-14): cancel scheduled crypto-shredding if termination is reverted
-- within the 30-day retention window (before the key is shredded). Refuses with 403
-- offboarding_shred_already_executed once the 30-day window has elapsed / key is shredded.
CREATE OR REPLACE FUNCTION rpc_revert_offboarding(p_user_id uuid)
RETURNS users
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_u   users;
  v_key pseudonym_key;
BEGIN
  IF current_user = 'authenticated' THEN
    IF auth.uid() IS NULL OR NOT fn_is_chro() OR NOT EXISTS (
         SELECT 1 FROM users u WHERE u.user_id = p_user_id AND u.company_id = fn_my_company()) THEN
      PERFORM fn_raise_business('anti_get_blocked');
    END IF;
  END IF;

  SELECT * INTO v_u FROM users WHERE user_id = p_user_id FOR UPDATE;
  IF NOT FOUND OR v_u.employment_ended_at IS NULL THEN
    PERFORM fn_raise_business('anti_get_blocked');
  END IF;

  SELECT * INTO v_key FROM pseudonym_key WHERE user_id = p_user_id FOR UPDATE;
  IF (v_key.user_id IS NOT NULL AND v_key.shredded_at IS NOT NULL)
     OR clock_timestamp() >= v_u.employment_ended_at + interval '30 days' THEN
    PERFORM fn_raise_business('offboarding_shred_already_executed');
  END IF;

  UPDATE users
     SET employment_ended_at = NULL
   WHERE user_id = p_user_id
  RETURNING * INTO v_u;

  UPDATE pseudonym_key
     SET scheduled_shred_at = NULL
   WHERE user_id = p_user_id AND shredded_at IS NULL;

  PERFORM fn_audit_view('employee_offboarding_reverted',
                        jsonb_build_object('user_id', p_user_id), p_user_id);
  RETURN v_u;
END;
$$;

REVOKE ALL ON FUNCTION rpc_revert_offboarding(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_revert_offboarding(uuid) TO service_role, authenticated;

-- rpc_run_scheduled_crypto_shred (O-14): scheduled job / RPC that shreds keys whose 30-day
-- offboarding retention window has elapsed. Returns the number of keys shredded.
CREATE OR REPLACE FUNCTION rpc_run_scheduled_crypto_shred()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  r   record;
  v_n int := 0;
BEGIN
  FOR r IN
    SELECT u.user_id
      FROM users u
      LEFT JOIN pseudonym_key pk ON pk.user_id = u.user_id
     WHERE u.employment_ended_at IS NOT NULL
       AND (pk.shredded_at IS NULL)
       AND COALESCE(pk.scheduled_shred_at, u.employment_ended_at + interval '30 days') <= clock_timestamp()
  LOOP
    PERFORM fn_crypto_shred_pseudonym_key(r.user_id);
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;

REVOKE ALL ON FUNCTION rpc_run_scheduled_crypto_shred() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_run_scheduled_crypto_shred() TO service_role;

-- ---------------------------------------------------------------------------
-- rpc_everstore_purchase — one RPC; client does NOT send price; CB does NOT block.
-- v1.6.13 (Karin 25.10):
--   * Open to every user with an active employee profile (#6: employees + managers/CEO/VPs buying
--     for themselves; governance-only accounts without an employee profile → 403 anti_get_blocked).
--   * Golden-spoons shelf allows ANY positive price (price_golden_spoons > 0) across all 8 categories
--     (cosmetic, time_benefit, health_wellbeing, learning, donation, experience, gift_card, merchandise).
--   * CHR Coins shelf is deferred to v2 (O-16) → refused in v1.
--   * Time-benefit voucher redemption privacy (נעילת הפרגוד): when category = 'time_benefit',
--     automatically inserts a standard HR approved absence / refresh time entry
--     (approved_absence_entry: 'זמן התרעננות / היעדרות מאושרת') with ZERO link to EverStore,
--     item_id, or Golden Spoons, while shop_purchase stays strictly hidden from managers.
-- ---------------------------------------------------------------------------
-- v1.6.17 (J-15): true when the user's employment has ended (users.employment_ended_at set).
CREATE OR REPLACE FUNCTION fn_employment_ended(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT COALESCE((SELECT u.employment_ended_at IS NOT NULL FROM users u WHERE u.user_id = p_user_id), false)
$$;
REVOKE ALL ON FUNCTION fn_employment_ended(uuid) FROM PUBLIC;

-- v1.6.17 (J-15, Karin 31.10): BEFORE INSERT guard — no time benefit (early leave, approved absence / day off)
-- may be recorded for an employee whose employment ended, whatever path writes it → 403 anti_get_blocked.
CREATE OR REPLACE FUNCTION fn_block_time_benefit_after_exit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF fn_employment_ended(NEW.user_id) THEN
    PERFORM fn_raise_business('anti_get_blocked');
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION fn_block_time_benefit_after_exit() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_early_leave_after_exit ON early_leave_log;
CREATE TRIGGER trg_early_leave_after_exit
    BEFORE INSERT ON early_leave_log
    FOR EACH ROW EXECUTE FUNCTION fn_block_time_benefit_after_exit();
DROP TRIGGER IF EXISTS trg_approved_absence_after_exit ON approved_absence_entry;
CREATE TRIGGER trg_approved_absence_after_exit
    BEFORE INSERT ON approved_absence_entry
    FOR EACH ROW EXECUTE FUNCTION fn_block_time_benefit_after_exit();

DROP FUNCTION IF EXISTS rpc_everstore_purchase(varchar, varchar);
CREATE OR REPLACE FUNCTION rpc_everstore_purchase(
  p_item_id         varchar,
  p_idempotency_key varchar,
  p_requested_date  date DEFAULT NULL
)
RETURNS avatar_state
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_item     shop_item_catalog%ROWTYPE;
  v_state    avatar_state;
  v_price    numeric(10, 1);
  v_prior    jsonb;
  v_inv      jsonb;
  v_departed boolean;
BEGIN
  -- Lock #6: open to every user with an employee interface (managers at every tier,
  -- CEO, VPs). Governance-only users (no employee profile) → 403.
  -- v1.6.16 (v3 §3.3): an ex-employee may still redeem during exit_redemption_days (30) after the end of
  -- employment (fn_in_exit_redemption_window); after that → 403. Time benefits are refused after exit.
  v_departed := v_uid IS NOT NULL AND NOT fn_has_employee_profile(v_uid) AND fn_in_exit_redemption_window(v_uid);
  IF v_uid IS NULL OR (NOT fn_has_employee_profile(v_uid) AND NOT v_departed) THEN
    PERFORM fn_raise_business('anti_get_blocked');
  END IF;

  IF p_idempotency_key IS NULL OR length(trim(p_idempotency_key)) = 0 THEN
    PERFORM fn_raise_business('anti_get_blocked');
  END IF;

  INSERT INTO avatar_state (user_id) VALUES (v_uid) ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO v_state FROM avatar_state WHERE user_id = v_uid FOR UPDATE;

  v_prior := v_state.shop_idempotency -> p_idempotency_key;
  IF v_prior IS NOT NULL AND (v_prior->>'status') = 'ok' THEN
    RETURN v_state;
  END IF;

  SELECT * INTO v_item FROM shop_item_catalog WHERE item_id = p_item_id AND is_active;
  IF NOT FOUND THEN
    PERFORM fn_raise_business('anti_get_blocked');
  END IF;

  IF v_item.currency = 'chr_coins' THEN
    -- O-16: CHR Coins shelf deferred to v2 → refused in v1
    PERFORM fn_raise_business('anti_get_blocked');
  END IF;
  IF v_item.category = 'time_benefit' AND fn_employment_ended(v_uid) THEN
    -- v1.6.17 J-15 (confirmed by Karin 31.10): no time benefit after employment ends — only EverStore
    -- products during the 30-day window (the DB guard fn_block_time_benefit_after_exit backs this up)
    PERFORM fn_raise_business('anti_get_blocked');
  END IF;

  v_price := v_item.price_coins;
  IF v_price IS NULL OR v_price <= 0 THEN
    PERFORM fn_raise_business('anti_get_blocked');
  END IF;

  IF v_state.golden_spoons < v_price THEN
    PERFORM fn_raise_business('anti_get_blocked');
  END IF;

  INSERT INTO shop_purchase (
    user_id, item_id, category, price_golden_spoons, cosmetic_only, idempotency_key
  ) VALUES (
    v_uid, v_item.item_id, v_item.category, v_price, COALESCE(v_item.cosmetic_only, true), p_idempotency_key
  )
  ON CONFLICT (user_id, idempotency_key) DO NOTHING;

  -- נעילת הפרגוד (Karin 25.10): time_benefit voucher automatically converts through HR into a
  -- standard approved absence / refresh time entry ('זמן התרעננות / היעדרות מאושרת') with no
  -- link to EverStore or item_id.
  IF v_item.category = 'time_benefit' THEN
    INSERT INTO approved_absence_entry (
      user_id, company_id, requested_date, entry_type, entry_text, schedule_status
    ) VALUES (
      v_uid,
      (SELECT u.company_id FROM users u WHERE u.user_id = v_uid),
      COALESCE(p_requested_date, fn_user_local_date(v_uid)),
      'approved_absence',
      'זמן התרעננות / היעדרות מאושרת',
      'pending_coordination'
    );
  END IF;

  v_inv := COALESCE(v_state.shop_inventory, '[]'::jsonb) || jsonb_build_array(
    jsonb_build_object(
      'item_id', p_item_id,
      'category', v_item.category,
      'qty', 1,
      'acquired_at', clock_timestamp(),
      'cosmetic_only', COALESCE(v_item.cosmetic_only, true)
    )
  );

  UPDATE avatar_state
     SET golden_spoons = golden_spoons - v_price,
         shop_inventory = v_inv,
         shop_idempotency = COALESCE(shop_idempotency, '{}'::jsonb) || jsonb_build_object(
           p_idempotency_key, jsonb_build_object('item_id', p_item_id, 'status', 'ok', 'ts', clock_timestamp())
         ),
         updated_at = clock_timestamp()
   WHERE user_id = v_uid
  RETURNING * INTO v_state;

  RETURN v_state;
END;
$$;

REVOKE ALL ON FUNCTION rpc_everstore_purchase(varchar, varchar, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_everstore_purchase(varchar, varchar, date) TO authenticated;

-- CHRO (vp_hr) adds or updates an EverStore catalog item across the 8 locked categories (v1.6.13, Karin 25.10).
CREATE OR REPLACE FUNCTION rpc_everstore_upsert_item(
  p_item_id             varchar,
  p_display_name        varchar,
  p_name_he             varchar,
  p_category            text,
  p_price_golden_spoons numeric,
  p_tier                shop_tier_enum DEFAULT 'custom',
  p_cosmetic_only       boolean DEFAULT false,
  p_provider            text DEFAULT NULL,
  p_is_active           boolean DEFAULT true
)
RETURNS shop_item_catalog
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_row shop_item_catalog;
BEGIN
  IF auth.uid() IS NULL OR NOT fn_is_chro() THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  IF p_item_id IS NULL OR length(btrim(p_item_id)) = 0
     OR p_display_name IS NULL OR length(btrim(p_display_name)) = 0
     OR p_name_he IS NULL OR length(btrim(p_name_he)) = 0 THEN
    PERFORM fn_raise_bad_request('invalid_shop_item');
  END IF;
  IF p_category IS NULL OR p_category NOT IN (
       'cosmetic', 'time_benefit', 'health_wellbeing', 'learning',
       'donation', 'experience', 'gift_card', 'merchandise') THEN
    PERFORM fn_raise_bad_request('invalid_shop_category');
  END IF;
  IF p_price_golden_spoons IS NULL OR p_price_golden_spoons <= 0
     OR p_price_golden_spoons <> round(p_price_golden_spoons, 1) THEN
    PERFORM fn_raise_bad_request('invalid_amount');
  END IF;

  INSERT INTO shop_item_catalog (
    item_id, display_name, name_he, category, provider, tier,
    price_coins, currency, cosmetic_only,
    real_money_purchase_allowed, affects_daily_energy_spoons, is_active
  ) VALUES (
    btrim(p_item_id), btrim(p_display_name), btrim(p_name_he), p_category, p_provider,
    COALESCE(p_tier, 'custom'::shop_tier_enum),
    p_price_golden_spoons, 'golden_spoons', COALESCE(p_cosmetic_only, p_category = 'cosmetic'),
    false, false, COALESCE(p_is_active, true)
  )
  ON CONFLICT (item_id) DO UPDATE SET
    display_name  = EXCLUDED.display_name,
    name_he       = EXCLUDED.name_he,
    category      = EXCLUDED.category,
    provider      = EXCLUDED.provider,
    tier          = EXCLUDED.tier,
    price_coins   = EXCLUDED.price_coins,
    cosmetic_only = EXCLUDED.cosmetic_only,
    is_active     = EXCLUDED.is_active
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION rpc_everstore_upsert_item(varchar, varchar, varchar, text, numeric, shop_tier_enum, boolean, text, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_everstore_upsert_item(varchar, varchar, varchar, text, numeric, shop_tier_enum, boolean, text, boolean) TO authenticated;

-- Direct manager coordinates the schedule of an approved absence / refresh time entry (נעילת הפרגוד).
-- Returns pseudonymous row only (no user_id, no EverStore/voucher info).
CREATE OR REPLACE FUNCTION rpc_coordinate_approved_absence(
  p_absence_id     uuid,
  p_requested_date date DEFAULT NULL
)
RETURNS TABLE (
  absence_id        uuid,
  display_pseudonym varchar,
  requested_date    date,
  entry_type        text,
  entry_text        text,
  schedule_status   text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_sub uuid;
BEGIN
  IF v_uid IS NULL OR NOT fn_viewer_may_see_pseudonyms() THEN
    PERFORM fn_raise_business('access_denied');
  END IF;

  SELECT a.user_id INTO v_sub
    FROM approved_absence_entry a
    JOIN users u ON u.user_id = a.user_id
   WHERE a.absence_id = p_absence_id
     AND u.reports_to = v_uid;
  IF NOT FOUND THEN
    PERFORM fn_raise_business('access_denied');
  END IF;

  UPDATE approved_absence_entry a
     SET requested_date  = COALESCE(p_requested_date, a.requested_date),
         schedule_status = 'coordinated'
   WHERE a.absence_id = p_absence_id;

  RETURN QUERY
  SELECT a.absence_id, u.display_pseudonym, a.requested_date, a.entry_type, a.entry_text, a.schedule_status
    FROM approved_absence_entry a
    JOIN users u ON u.user_id = a.user_id
   WHERE a.absence_id = p_absence_id;
END;
$$;

REVOKE ALL ON FUNCTION rpc_coordinate_approved_absence(uuid, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_coordinate_approved_absence(uuid, date) TO authenticated;

-- ---------------------------------------------------------------------------
-- rpc_convert_golden_to_chr — v2 design: ONE-WAY 1 golden spoon = 50 CHR Coins (no reverse function).
-- v1.6.16 (Karin 30.10, replaces the v1.6.13 "active on server" decision): CHR Coins shelf deferred to v2 →
-- the function stays DEFINED (signature, grant, OpenAPI path) for v2 readiness, but EVERY v1 call raises,
-- unconditionally and before any read or write: HTTP 422 chr_coins_deferred_to_v2 (SQLSTATE PT422).
-- No balance change, no golden_chr_conversion row. v2 will restore the conversion body.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_convert_golden_to_chr(
  p_golden_spoons   numeric,
  p_idempotency_key varchar
)
RETURNS avatar_state
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  RAISE EXCEPTION 'chr_coins_deferred_to_v2'
    USING ERRCODE = 'PT422',
          DETAIL  = 'http_hint=422;code=chr_coins_deferred_to_v2',
          HINT    = 'CHR Coins shelf is deferred to v2; Golden Spoons conversion is disabled in v1';
END;
$$;

REVOKE ALL ON FUNCTION rpc_convert_golden_to_chr(numeric, varchar) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_convert_golden_to_chr(numeric, varchar) TO authenticated;

-- ---------------------------------------------------------------------------
-- Questionnaires
-- rpc_submit_questionnaire — once per period (employee timezone), answers WORM,
-- reward credited as golden spoons. Not gated by the Circuit Breaker.
-- Errors: 403 questionnaire_not_eligible (tenure), 409 questionnaire_already_submitted,
--         400 questionnaire_invalid_answers. (v1.6.11 O-6: IHS enabled, scoring_not_locked removed.)
-- ---------------------------------------------------------------------------

-- Validate an answer array against a definition (count, NULLs, range).
-- For IHS (scoring_method = 'ihs'), any non-empty 1–5 answer array is accepted (mean converted to 0–100).
CREATE OR REPLACE FUNCTION fn_questionnaire_answers_valid(p_def questionnaire_definition, p_answers int[])
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_answers IS NOT NULL
     AND CASE WHEN p_def.scoring_method = 'ihs' THEN cardinality(p_answers) >= 1
              ELSE cardinality(p_answers) = p_def.item_count END
     AND (NOT p_def.all_required OR array_position(p_answers, NULL) IS NULL)
     AND (p_def.answer_min IS NULL OR NOT EXISTS (
            SELECT 1 FROM unnest(p_answers) a
             WHERE a IS NOT NULL AND (a < p_def.answer_min OR a > p_def.answer_max)))
$$;

-- Score a submission per the definition's scoring method (O-6 'ihs', O-7 'pcq12', 'tps12').
CREATE OR REPLACE FUNCTION fn_questionnaire_score(p_def questionnaire_definition, p_answers int[])
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_def.scoring_method = 'tps12' THEN
    RETURN fn_tps12_score(p_answers, p_def.reversed_items);
  ELSIF p_def.scoring_method = 'ihs' THEN
    RETURN fn_ihs_score(p_answers, p_def.reversed_items);
  ELSIF p_def.scoring_method = 'pcq12' THEN
    RETURN fn_pcq12_score(p_answers, p_def.reversed_items);
  END IF;
  RETURN NULL;
END;
$$;

-- v1.6.16 (v3 §3.6 + Karin 30.10): participation reward = the fixed amount of the definition's
-- reward_setting_key in agent_settings. It never receives the answers or the score. NULL = "לא הוגדר".
CREATE OR REPLACE FUNCTION fn_questionnaire_reward(p_def questionnaire_definition, p_company uuid)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT fn_agent_setting_num(p_company, p_def.reward_setting_key)
$$;
REVOKE ALL ON FUNCTION fn_questionnaire_reward(questionnaire_definition, uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION rpc_submit_questionnaire(
  p_code    varchar,
  p_answers int[]
)
RETURNS questionnaire_submission
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_def    questionnaire_definition;
  v_start  date;
  v_local  date;
  v_src    text;
  v_score  numeric;
  v_reward numeric;
  v_rstat  text;
  v_row    questionnaire_submission;
BEGIN
  IF v_uid IS NULL OR fn_app_role() <> 'employee' THEN
    PERFORM fn_raise_business('anti_get_blocked');
  END IF;

  SELECT * INTO v_def FROM questionnaire_definition WHERE code = p_code AND is_active;
  IF NOT FOUND THEN
    PERFORM fn_raise_business('anti_get_blocked');
  END IF;

  v_local := fn_user_local_date(v_uid);
  -- Lock #5 + O-49 (Karin 21.10): the wait counts from the day she joined her CURRENT team
  -- (team_joined_at, employee-local date), else from her hire_date; with neither she is exempt.
  SELECT w.wait_start, w.source INTO v_start, v_src FROM fn_tps_wait_start(v_uid) w;
  IF v_def.min_tenure_days > 0 AND v_src <> 'exempt' AND v_local < v_start + v_def.min_tenure_days THEN
    PERFORM fn_raise_business('questionnaire_not_eligible');
  END IF;

  IF NOT fn_questionnaire_answers_valid(v_def, p_answers) THEN
    RAISE EXCEPTION 'questionnaire_invalid_answers'
      USING ERRCODE = '22023', DETAIL = 'http_hint=400;code=questionnaire_invalid_answers',
            HINT = 'questionnaire_invalid_answers';
  END IF;

  v_score := fn_questionnaire_score(v_def, p_answers);   -- group metric only; never a reward input
  v_reward := fn_questionnaire_reward(v_def, (SELECT u.company_id FROM users u WHERE u.user_id = v_uid));
  v_rstat := CASE WHEN v_reward IS NULL THEN 'not_defined' ELSE 'set' END;
  v_reward := COALESCE(v_reward, 0);

  INSERT INTO questionnaire_submission (
    user_id, questionnaire_code, period_key, local_date, answers, score, reward_golden_spoons, reward_status
  ) VALUES (
    v_uid, v_def.code, fn_period_key(v_def.frequency, v_local), v_local, p_answers, v_score, v_reward, v_rstat
  )
  ON CONFLICT (user_id, questionnaire_code, period_key) DO NOTHING
  RETURNING * INTO v_row;

  IF v_row.submission_id IS NULL THEN
    RAISE EXCEPTION 'questionnaire_already_submitted'
      USING ERRCODE = '23505', DETAIL = 'http_hint=409;code=questionnaire_already_submitted',
            HINT = 'questionnaire_already_submitted';
  END IF;

  INSERT INTO avatar_state (user_id) VALUES (v_uid) ON CONFLICT (user_id) DO NOTHING;
  UPDATE avatar_state
     SET golden_spoons = golden_spoons + v_reward,
         updated_at = clock_timestamp()
   WHERE user_id = v_uid;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION rpc_submit_questionnaire(varchar, int[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_submit_questionnaire(varchar, int[]) TO authenticated;

-- Compatibility wrapper for 1.4 clients: PCQ-12 monthly (+10). Now needs the answers.
CREATE OR REPLACE FUNCTION rpc_pcq12_claim_monthly_reward(p_answers int[])
RETURNS questionnaire_submission
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT * FROM rpc_submit_questionnaire('PCQ-12', p_answers)
$$;

REVOKE ALL ON FUNCTION rpc_pcq12_claim_monthly_reward(int[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_pcq12_claim_monthly_reward(int[]) TO authenticated;

-- rpc_upsert_questionnaire_definition — vp_hr defines FUTURE questionnaires.
-- Locked catalogue rows cannot be changed here. CHECK: daily..monthly.
-- v1.6.16 (v3 §3.6): the amount is NEVER set per questionnaire — monthly → golden_spoons_per_questionnaire,
-- daily / weekly → golden_spoons_per_short_questionnaire (agent_settings). p_reward_amount is kept in the
-- signature for compatibility and must be NULL (else 400 questionnaire_reward_from_settings).
CREATE OR REPLACE FUNCTION rpc_upsert_questionnaire_definition(
  p_code          varchar,
  p_name_en       varchar,
  p_name_he       varchar,
  p_frequency     text,
  p_reward_amount numeric,
  p_item_count    int,
  p_answer_min    int DEFAULT NULL,
  p_answer_max    int DEFAULT NULL,
  p_is_active     boolean DEFAULT true
)
RETURNS questionnaire_definition
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_row questionnaire_definition;
BEGIN
  IF auth.uid() IS NULL OR fn_app_role() <> 'vp_hr' THEN
    PERFORM fn_raise_business('anti_get_blocked');
  END IF;
  IF EXISTS (SELECT 1 FROM questionnaire_definition WHERE code = p_code AND is_locked) THEN
    PERFORM fn_raise_business('questionnaire_locked');
  END IF;
  IF p_reward_amount IS NOT NULL THEN
    PERFORM fn_raise_bad_request('questionnaire_reward_from_settings');
  END IF;

  INSERT INTO questionnaire_definition (
    code, name_en, name_he, frequency, reward_type, reward_amount, reward_setting_key, item_count,
    answer_min, answer_max, is_locked, is_active, updated_at
  ) VALUES (
    p_code, p_name_en, p_name_he, p_frequency, 'participation', NULL,
    CASE WHEN p_frequency = 'monthly' THEN 'golden_spoons_per_questionnaire'
         ELSE 'golden_spoons_per_short_questionnaire' END,
    p_item_count, p_answer_min, p_answer_max, false, COALESCE(p_is_active, true), clock_timestamp()
  )
  ON CONFLICT (code) DO UPDATE SET
    name_en = EXCLUDED.name_en, name_he = EXCLUDED.name_he, frequency = EXCLUDED.frequency,
    reward_setting_key = EXCLUDED.reward_setting_key, item_count = EXCLUDED.item_count,
    answer_min = EXCLUDED.answer_min, answer_max = EXCLUDED.answer_max,
    is_active = EXCLUDED.is_active, updated_at = clock_timestamp()
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION rpc_upsert_questionnaire_definition(varchar, varchar, varchar, text, numeric, int, int, int, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_upsert_questionnaire_definition(varchar, varchar, varchar, text, numeric, int, int, int, boolean) TO authenticated;

-- ---------------------------------------------------------------------------
-- Lock #3 (v1.6.1): contributor counters — N is ALWAYS the number of distinct employees
-- whose data actually feeds an aggregate in its period, never team size.
-- ---------------------------------------------------------------------------

-- Employees of a team whose data feeds rpc_team_aggregate_refresh: spoons reported today,
-- TPS-12 or IHS answered this quarter, or a salary record.
CREATE OR REPLACE FUNCTION fn_team_aggregate_contributors(p_org_id uuid, p_department varchar)
RETURNS int
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT count(DISTINCT c.user_id)::int FROM (
    SELECT sb.user_id FROM spoon_budget sb JOIN users u ON u.user_id = sb.user_id
     WHERE u.company_id = p_org_id AND u.department = p_department AND u.app_role = 'employee'
       AND sb.reported_at IS NOT NULL
       AND sb.budget_date = (clock_timestamp() AT TIME ZONE u.timezone)::date
    UNION
    SELECT q.user_id FROM questionnaire_submission q JOIN users u ON u.user_id = q.user_id
     WHERE u.company_id = p_org_id AND u.department = p_department
       AND q.questionnaire_code IN ('TPS-12', 'IHS')
       AND q.period_key = fn_period_key('quarterly', (clock_timestamp() AT TIME ZONE u.timezone)::date)
    UNION
    SELECT e.user_id FROM employee_value_asset e JOIN users u ON u.user_id = e.user_id
     WHERE u.company_id = p_org_id AND u.department = p_department AND u.app_role = 'employee'
       AND e.annual_salary IS NOT NULL
  ) c
$$;

-- Employees of a team who contributed data (spoon report or questionnaire) since p_since.
-- Used for Cuckoo (N≥10) through fn_cuckoo_recent_reporters (rolling 30 days, locked 20.10).
CREATE OR REPLACE FUNCTION fn_team_activity_contributors(p_org_id uuid, p_department varchar, p_since timestamptz)
RETURNS int
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT count(DISTINCT c.user_id)::int FROM (
    SELECT sb.user_id FROM spoon_budget sb JOIN users u ON u.user_id = sb.user_id
     WHERE u.company_id = p_org_id AND u.department = p_department AND sb.reported_at > p_since
    UNION
    SELECT q.user_id FROM questionnaire_submission q JOIN users u ON u.user_id = q.user_id
     WHERE u.company_id = p_org_id AND u.department = p_department AND q.submitted_at > p_since
  ) c
$$;

REVOKE ALL ON FUNCTION fn_team_aggregate_contributors(uuid, varchar) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_team_activity_contributors(uuid, varchar, timestamptz) FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- Red team alert helpers (lock #4)
-- ---------------------------------------------------------------------------

-- Today's actually reported spoons for a team: count of reporters + their average.
-- Internal (no client grant). "Today" = each employee's local date.
CREATE OR REPLACE FUNCTION fn_team_spoon_reports(p_org_id uuid, p_department varchar)
RETURNS TABLE (reporters int, avg_spoons numeric)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT count(*)::int, round(avg(sb.current_spoon_count)::numeric, 2)
    FROM spoon_budget sb
    JOIN users u ON u.user_id = sb.user_id
   WHERE u.company_id = p_org_id
     AND u.department = p_department
     AND u.app_role = 'employee'
     AND sb.reported_at IS NOT NULL
     AND sb.budget_date = (clock_timestamp() AT TIME ZONE u.timezone)::date
$$;

REVOKE ALL ON FUNCTION fn_team_spoon_reports(uuid, varchar) FROM PUBLIC;

-- RED when the team average is below 3; GREEN otherwise; NULL = no alert (too few reporters).
CREATE OR REPLACE FUNCTION fn_spoon_alert_level(p_avg numeric)
RETURNS dichotomous_alert_enum
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE WHEN p_avg IS NULL THEN NULL
              WHEN p_avg < 3 THEN 'RED'::dichotomous_alert_enum
              ELSE 'GREEN'::dichotomous_alert_enum END
$$;

-- rpc_team_spoon_alert — manager reads the team trend only. ≥5 employees who actually
-- reported spoons today (lock #3), otherwise 403 aggregation_privacy_threshold.
-- Returns no names, no pseudonyms, no individual scores.
CREATE OR REPLACE FUNCTION rpc_team_spoon_alert(p_org_id uuid, p_department varchar DEFAULT 'General')
RETURNS TABLE (alert_level dichotomous_alert_enum, team_spoon_avg numeric, reporter_count int)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_rep int;
  v_avg numeric;
BEGIN
  IF auth.uid() IS NULL OR NOT fn_is_org_manager(p_org_id) THEN
    PERFORM fn_raise_business('aggregation_privacy_threshold');
  END IF;
  -- Lock #3: N = employees who actually reported spoons today (never team size).
  SELECT a.reporters, a.avg_spoons INTO v_rep, v_avg FROM fn_team_spoon_reports(p_org_id, p_department) a;
  PERFORM fn_assert_privacy_threshold(v_rep, 'regular');
  PERFORM fn_audit_view('team_spoon_alert', jsonb_build_object('org_id', p_org_id, 'department', p_department));
  RETURN QUERY SELECT fn_spoon_alert_level(v_avg), v_avg, v_rep;
END;
$$;

REVOKE ALL ON FUNCTION rpc_team_spoon_alert(uuid, varchar) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_team_spoon_alert(uuid, varchar) TO authenticated;

-- ---------------------------------------------------------------------------
-- v1.6.11 (Karin 24.10, O-1, O-2, O-3, O-4, O-18):
--   * fn_company_tier_avg_salary: company-wide average annual salary of employees in a turnover
--     tier group (junior = tier 1, mid = tiers 2–3, senior = tier 4); never individual or small-team
--     salary averages.
--   * fn_weekly_deprivation_metrics / fn_is_employee_deprived: an employee is deprived in a week
--     when her weekly average available spoons < 5 OR her weekly burnout score B_t >= 0.65.
--   * fn_chr_real_ebitda: GAAP EBITDA − happiness_debt_balance − 12 % deprivation tax.
-- ---------------------------------------------------------------------------

-- O-4 (Karin 24.10): company-wide average annual salary of active employees in turnover tier group p_tier.
CREATE OR REPLACE FUNCTION fn_company_tier_avg_salary(p_company_id uuid, p_tier text)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT round(avg(e.annual_salary), 2)
    FROM users u
    JOIN employee_value_asset e ON e.user_id = u.user_id
   WHERE u.company_id = p_company_id
     AND u.employment_ended_at IS NULL
     AND e.annual_salary IS NOT NULL
     AND fn_effective_turnover_tier(u.user_id) = p_tier
$$;

REVOKE ALL ON FUNCTION fn_company_tier_avg_salary(uuid, text) FROM PUBLIC;

-- O-3 (Karin 24.10): weekly average reported spoons and weekly B_t for an employee in a company week.
CREATE OR REPLACE FUNCTION fn_weekly_deprivation_metrics(
  p_user_id         uuid,
  p_week_start_date date DEFAULT NULL
)
RETURNS TABLE (
  week_start_date     date,
  weekly_spoon_avg    numeric,
  weekly_b_t          numeric,
  is_deprived_by_rule boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_week      date;
  v_spoon_avg numeric;
  v_bt        numeric;
BEGIN
  v_week := COALESCE(p_week_start_date, fn_local_week_start(p_user_id), fn_user_local_date(p_user_id) - 6);
  IF v_week IS NULL THEN
    RETURN QUERY SELECT NULL::date, NULL::numeric, NULL::numeric, false;
    RETURN;
  END IF;

  SELECT round(avg(sb.current_spoon_count)::numeric, 2)
    INTO v_spoon_avg
    FROM spoon_budget sb
   WHERE sb.user_id = p_user_id
     AND sb.reported_at IS NOT NULL
     AND sb.budget_date BETWEEN v_week AND v_week + 6;

  SELECT fn_b_t(w.stress_1to5, w.overtime_hours, w.productivity_drop_1to5)
    INTO v_bt
    FROM workload_self_report w
   WHERE w.user_id = p_user_id
     AND w.week_start_date = v_week;

  RETURN QUERY SELECT v_week, v_spoon_avg, v_bt,
                      (COALESCE(v_spoon_avg < 5, false) OR COALESCE(v_bt >= 0.65, false));
END;
$$;

REVOKE ALL ON FUNCTION fn_weekly_deprivation_metrics(uuid, date) FROM PUBLIC;

-- O-3 (Karin 24.10) + v1.6.16 (v3 §6.2 classify_deprived): deprived = the weekly rule (avg spoons < 5 OR
-- B_t >= 0.65) holds in the given week AND in the week before (TWO consecutive weeks). Falls back to
-- employee_value_asset.is_deprived only when the given week has no spoon or workload report at all.
-- The result feeds group counts only (never shown to a manager per employee).
CREATE OR REPLACE FUNCTION fn_is_employee_deprived(
  p_user_id         uuid,
  p_week_start_date date DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_m    record;
  v_prev record;
  v_flag boolean;
BEGIN
  SELECT * INTO v_m FROM fn_weekly_deprivation_metrics(p_user_id, p_week_start_date);
  SELECT e.is_deprived INTO v_flag FROM employee_value_asset e WHERE e.user_id = p_user_id;
  IF v_m.weekly_spoon_avg IS NOT NULL OR v_m.weekly_b_t IS NOT NULL THEN
    IF NOT v_m.is_deprived_by_rule THEN
      RETURN false;
    END IF;
    -- v3: the previous company week must also meet the rule (two consecutive weeks)
    SELECT * INTO v_prev FROM fn_weekly_deprivation_metrics(p_user_id, v_m.week_start_date - 7);
    RETURN COALESCE(v_prev.is_deprived_by_rule, false);
  END IF;
  RETURN COALESCE(v_flag, false);
END;
$$;

REVOKE ALL ON FUNCTION fn_is_employee_deprived(uuid, date) FROM PUBLIC;

-- Sync employee_value_asset.is_deprived and happiness_debt_liability from the O-3 / O-1 / O-4 rules.
CREATE OR REPLACE FUNCTION fn_sync_employee_deprived(
  p_user_id         uuid,
  p_week_start_date date DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_dep     boolean;
  v_comp    uuid;
  v_tier    text;
  v_sal     numeric;
  v_debt    numeric(12, 2) := 0;
BEGIN
  v_dep := fn_is_employee_deprived(p_user_id, p_week_start_date);
  SELECT u.company_id, fn_effective_turnover_tier(u.user_id)
    INTO v_comp, v_tier
    FROM users u WHERE u.user_id = p_user_id;

  IF v_dep AND v_tier IS NOT NULL THEN
    v_sal := fn_company_tier_avg_salary(v_comp, v_tier);
    v_debt := COALESCE(round(v_sal * fn_turnover_tier_midpoint_factor(v_tier), 2), 0);
  END IF;

  UPDATE employee_value_asset
     SET is_deprived = v_dep,
         happiness_debt_liability = v_debt,
         updated_at = clock_timestamp()
   WHERE user_id = p_user_id;
  RETURN v_dep;
END;
$$;

REVOKE ALL ON FUNCTION fn_sync_employee_deprived(uuid, date) FROM PUBLIC;

-- O-18 (Karin 24.10): CHR Real EBITDA = GAAP EBITDA − happiness_debt_balance − 12 % deprivation tax.
CREATE OR REPLACE FUNCTION fn_chr_real_ebitda(
  p_gaap_reported_ebitda   numeric,
  p_happiness_debt_balance numeric,
  p_deprivation_tax_amount numeric
)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT round(p_gaap_reported_ebitda - COALESCE(p_happiness_debt_balance, 0) - COALESCE(p_deprivation_tax_amount, 0), 2)
$$;

-- Actual contributors feeding Shadow Balance for (p_org_id, p_department) in the week (N≥10 required, lock #3).
CREATE OR REPLACE FUNCTION fn_shadow_balance_contributors(
  p_org_id          uuid,
  p_department      varchar,
  p_week_start_date date DEFAULT NULL
)
RETURNS int
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_cnt int;
BEGIN
  SELECT count(DISTINCT c.user_id)::int INTO v_cnt FROM (
    SELECT e.user_id
      FROM employee_value_asset e
      JOIN users u ON u.user_id = e.user_id
     WHERE u.company_id = p_org_id AND u.department = p_department
       AND u.employment_ended_at IS NULL
       AND fn_effective_turnover_tier(u.user_id) IS NOT NULL
       AND e.annual_salary IS NOT NULL
    UNION
    SELECT sb.user_id
      FROM spoon_budget sb
      JOIN users u ON u.user_id = sb.user_id
     WHERE u.company_id = p_org_id AND u.department = p_department
       AND u.employment_ended_at IS NULL
       AND fn_effective_turnover_tier(u.user_id) IS NOT NULL
       AND sb.reported_at IS NOT NULL
       AND sb.budget_date BETWEEN COALESCE(p_week_start_date, fn_local_week_start(u.user_id), fn_user_local_date(u.user_id) - 6)
                              AND COALESCE(p_week_start_date, fn_local_week_start(u.user_id), fn_user_local_date(u.user_id) - 6) + 6
    UNION
    SELECT w.user_id
      FROM workload_self_report w
      JOIN users u ON u.user_id = w.user_id
     WHERE u.company_id = p_org_id AND u.department = p_department
       AND u.employment_ended_at IS NULL
       AND fn_effective_turnover_tier(u.user_id) IS NOT NULL
       AND w.week_start_date = COALESCE(p_week_start_date, fn_local_week_start(u.user_id))
  ) c;
  RETURN COALESCE(v_cnt, 0);
END;
$$;

REVOKE ALL ON FUNCTION fn_shadow_balance_contributors(uuid, varchar, date) FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- rpc_team_aggregate_refresh — REGULAR team data, N ≥ 5 (403 below)
--   Uses company-wide turnover tier avg_annual_salary (O-4), midpoint (O-1), O-3 deprivation,
--   and TPS-12 + IHS quarterly team averages (O-6, ≥5 respondents each).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_team_aggregate_refresh(
  p_org_id     uuid,
  p_department varchar DEFAULT 'General'
)
RETURNS team_aggregate
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_n        int;
  v_avg      numeric(4, 2);
  v_deprived int;
  v_salary   numeric(12, 2);
  v_tax      numeric(14, 2);
  v_min      numeric(14, 2);
  v_max      numeric(14, 2);
  v_mid      numeric(14, 2);
  v_tps      numeric(5, 2);
  v_tps_n    int;
  v_ihs      numeric(5, 2);
  v_ihs_n    int;
  v_rep_n    int;
  v_sal_n    int;
  v_row      team_aggregate;
BEGIN
  IF auth.uid() IS NULL OR NOT fn_is_org_manager(p_org_id) THEN
    PERFORM fn_raise_business('aggregation_privacy_threshold');
  END IF;

  -- Lock #3: N = distinct employees whose data feeds this row. Each figure also needs its own ≥5.
  v_n := fn_team_aggregate_contributors(p_org_id, p_department);
  PERFORM fn_assert_privacy_threshold(v_n, 'regular');

  SELECT a.avg_spoons, a.reporters INTO v_avg, v_rep_n
    FROM fn_team_spoon_reports(p_org_id, p_department) a;
  IF v_rep_n < fn_privacy_min_n('regular') THEN
    v_avg := NULL;   -- below respondent N: no average, no alert
  END IF;

  -- O-1, O-2, O-3, O-4: use each member's effective turnover tier and the company-wide average
  -- salary of that tier group (never individual or small-team salary averages).
  WITH m AS (
    SELECT u.user_id,
           fn_effective_turnover_tier(u.user_id) AS tier,
           fn_is_employee_deprived(u.user_id) AS deprived,
           fn_company_tier_avg_salary(p_org_id, fn_effective_turnover_tier(u.user_id)) AS tier_salary
      FROM employee_value_asset e
      JOIN users u ON u.user_id = e.user_id
     WHERE u.company_id = p_org_id
       AND u.department = p_department
       AND u.app_role = 'employee'
       AND e.annual_salary IS NOT NULL
  )
  SELECT count(*) FILTER (WHERE m.deprived)::int,
         round(avg(m.tier_salary), 2),
         round(COALESCE(sum(m.tier_salary * fn_chr_productivity_factor()) FILTER (WHERE m.deprived), 0), 2),
         round(sum(m.tier_salary * t.min_pct / 100), 2),
         round(sum(m.tier_salary * t.max_pct / 100), 2),
         round(sum(m.tier_salary * t.midpoint_pct / 100), 2),
         count(*)::int
    INTO v_deprived, v_salary, v_tax, v_min, v_max, v_mid, v_sal_n
    FROM m
    LEFT JOIN turnover_tier_config t ON t.tier = m.tier;
  IF v_sal_n < fn_privacy_min_n('regular') THEN
    v_deprived := NULL; v_salary := NULL; v_tax := NULL; v_min := NULL; v_max := NULL; v_mid := NULL;
  END IF;

  SELECT round(avg(q.tps_12_score), 2), count(*)::int
    INTO v_tps, v_tps_n
    FROM questionnaire_submission q
    JOIN users u ON u.user_id = q.user_id
   WHERE u.company_id = p_org_id
     AND u.department = p_department
     AND q.questionnaire_code = 'TPS-12'
     AND q.period_key = fn_period_key('quarterly', (clock_timestamp() AT TIME ZONE u.timezone)::date);
  IF v_tps_n < fn_privacy_min_n('regular') THEN
    v_tps := NULL;
  END IF;

  -- v1.6.11 (O-6): IHS quarterly team average (N≥5 actual respondents)
  SELECT round(avg(q.ihs_score), 2), count(*)::int
    INTO v_ihs, v_ihs_n
    FROM questionnaire_submission q
    JOIN users u ON u.user_id = q.user_id
   WHERE u.company_id = p_org_id
     AND u.department = p_department
     AND q.questionnaire_code = 'IHS'
     AND q.period_key = fn_period_key('quarterly', (clock_timestamp() AT TIME ZONE u.timezone)::date);
  IF v_ihs_n < fn_privacy_min_n('regular') THEN
    v_ihs := NULL;
  END IF;

  INSERT INTO team_aggregate (
    org_id, department, contributor_count, salary_contributor_count, team_spoon_avg,
    deprived_count, avg_annual_salary, deprivation_tax_amount,
    turnover_cost_min_sum, turnover_cost_max_sum, turnover_cost_midpoint_sum,
    heat_map_bucket, tps_team_avg, tps_respondent_count,
    ihs_team_avg, ihs_respondent_count,
    spoon_reporter_count, dichotomous_alert_level, calculated_at
  ) VALUES (
    p_org_id, p_department, v_n, v_sal_n, v_avg,
    v_deprived, v_salary, v_tax,
    v_min, v_max, v_mid,
    NULL, v_tps, v_tps_n,
    v_ihs, v_ihs_n,
    v_rep_n,
    fn_spoon_alert_level(v_avg),
    clock_timestamp()
  )
  RETURNING * INTO v_row;

  PERFORM fn_audit_view('team_aggregate_refresh', jsonb_build_object('org_id', p_org_id, 'department', p_department));
  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION rpc_team_aggregate_refresh(uuid, varchar) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_team_aggregate_refresh(uuid, varchar) TO authenticated;

-- ---------------------------------------------------------------------------
-- rpc_shadow_balance_refresh — SENSITIVE, N ≥ 10 actual contributors (403 below).
-- v1.6.11 (Karin 24.10, O-1, O-2, O-3, O-4, O-18):
--   * Uses the company-wide average annual salary of each employee's turnover tier group (O-4:
--     junior = tier 1, mid = tiers 2–3, senior = tier 4; tier 5/outside excluded unless overridden).
--   * Deprived in the week = weekly avg spoons < 5 OR weekly B_t >= 0.65 (O-3).
--   * Happiness Debt (happiness_debt_sum / happiness_debt_balance) = Σ (tier_avg_salary × midpoint_factor)
--     over deprived employees (O-1: junior 0.40, mid 1.25, senior 3.00).
--   * 12 % Deprivation Tax (deprivation_tax_amount) = Σ (tier_avg_salary × 0.12) over deprived employees.
--   * shadow_balance_sum = happiness_debt_sum + deprivation_tax_amount.
--   * chr_real_ebitda = gaap_reported_ebitda − happiness_debt_balance − deprivation_tax_amount (O-18).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_shadow_balance_refresh(
  p_org_id               uuid,
  p_department           varchar DEFAULT 'General',
  p_gaap_reported_ebitda numeric DEFAULT NULL
)
RETURNS shadow_balance_aggregate
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_n        int;
  v_deprived int;
  v_tax      numeric(14, 2);
  v_debt     numeric(14, 2);
  v_shadow   numeric(14, 2);
  v_row      shadow_balance_aggregate;
BEGIN
  IF auth.uid() IS NULL OR NOT fn_is_org_manager(p_org_id) THEN
    PERFORM fn_raise_business('aggregation_privacy_threshold');
  END IF;

  v_n := fn_shadow_balance_contributors(p_org_id, p_department);
  PERFORM fn_assert_privacy_threshold(v_n, 'shadow_balance');

  WITH m AS (
    SELECT u.user_id,
           fn_effective_turnover_tier(u.user_id) AS tier,
           fn_is_employee_deprived(u.user_id) AS deprived,
           fn_company_tier_avg_salary(p_org_id, fn_effective_turnover_tier(u.user_id)) AS tier_salary
      FROM users u
     WHERE u.company_id = p_org_id
       AND u.department = p_department
       AND u.employment_ended_at IS NULL
       AND fn_effective_turnover_tier(u.user_id) IS NOT NULL
  )
  SELECT count(*) FILTER (WHERE m.deprived)::int,
         round(COALESCE(sum(m.tier_salary * fn_chr_productivity_factor()) FILTER (WHERE m.deprived), 0), 2),
         round(COALESCE(sum(m.tier_salary * fn_turnover_tier_midpoint_factor(m.tier)) FILTER (WHERE m.deprived), 0), 2)
    INTO v_deprived, v_tax, v_debt
    FROM m;

  v_shadow := round(COALESCE(v_debt, 0) + COALESCE(v_tax, 0), 2);
  PERFORM fn_audit_view('shadow_balance_refresh', jsonb_build_object('org_id', p_org_id, 'department', p_department));

  INSERT INTO shadow_balance_aggregate (
    org_id, department, contributor_count, deprived_count, deprivation_tax_amount,
    happiness_debt_sum, shadow_balance_sum, gaap_reported_ebitda
  ) VALUES (
    p_org_id, p_department, v_n, v_deprived, v_tax,
    v_debt, v_shadow, p_gaap_reported_ebitda
  )
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION rpc_shadow_balance_refresh(uuid, varchar, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_shadow_balance_refresh(uuid, varchar, numeric) TO authenticated;

-- Emergency mode (N ≥ 10 actual contributors): see the v1.6.1 section at the end of this file.


-- ---------------------------------------------------------------------------
-- rpc_signup_profile — create/ensure public.users row after auth.users signup
-- N-4 revised: p_timezone REQUIRED and must be valid IANA (no server DEFAULT/coerce).
-- Client: Intl.DateTimeFormat().resolvedOptions().timeZone; if detection fails, user
-- picks country of residence (and region/city if multi-zone); client maps → IANA.
-- p_country_code optional ISO 3166-1 alpha-2 (informational); no country→zone table on server.
-- Missing/empty → 400 timezone_required (22004); invalid → 400 invalid_timezone (22023).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_signup_profile(
  p_email        varchar,
  p_full_name    varchar,
  p_timezone     text,                    -- REQUIRED valid IANA
  p_country_code char(2) DEFAULT NULL,    -- optional ISO 3166-1 alpha-2
  p_company_id   uuid DEFAULT NULL,
  p_department   varchar DEFAULT 'General',
  p_app_role     text DEFAULT 'employee'
)
RETURNS users
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row users;
  v_tz      text;
  v_cc      char(2);
  v_existed boolean;
  v_onboard numeric;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'anti_get_blocked'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=anti_get_blocked', HINT = 'anti_get_blocked';
  END IF;

  IF p_email IS NULL OR btrim(p_email) = '' OR p_full_name IS NULL OR btrim(p_full_name) = '' THEN
    RAISE EXCEPTION 'anti_get_blocked'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=anti_get_blocked', HINT = 'anti_get_blocked';
  END IF;

  v_tz := NULLIF(btrim(COALESCE(p_timezone, '')), '');
  IF v_tz IS NULL THEN
    RAISE EXCEPTION 'timezone_required'
      USING ERRCODE = '22004',
            DETAIL = 'http_hint=400;code=timezone_required',
            HINT = 'timezone_required';
  END IF;
  IF NOT fn_is_valid_iana_timezone(v_tz) THEN
    RAISE EXCEPTION 'invalid_timezone'
      USING ERRCODE = '22023',
            DETAIL = 'http_hint=400;code=invalid_timezone',
            HINT = 'invalid_timezone';
  END IF;

  IF p_country_code IS NOT NULL THEN
    v_cc := upper(btrim(p_country_code::text))::char(2);
    IF v_cc !~ '^[A-Z]{2}$' THEN
      RAISE EXCEPTION 'invalid_timezone'
        USING ERRCODE = '22023',
              DETAIL = 'http_hint=400;code=invalid_timezone',
              HINT = 'invalid_timezone';
    END IF;
  ELSE
    v_cc := NULL;
  END IF;

  IF p_app_role IS NULL OR p_app_role NOT IN ('employee', 'manager', 'vp_hr', 'legal_ethics') THEN
    p_app_role := 'employee';
  END IF;

  v_existed := EXISTS (SELECT 1 FROM users WHERE user_id = v_uid);

  INSERT INTO users (user_id, email, full_name, timezone, country_code, company_id, department, app_role)
  VALUES (
    v_uid,
    btrim(p_email),
    btrim(p_full_name),
    v_tz,
    v_cc,
    p_company_id,
    COALESCE(NULLIF(btrim(p_department), ''), 'General'),
    p_app_role
  )
  ON CONFLICT (user_id) DO UPDATE
    SET email = EXCLUDED.email,
        full_name = EXCLUDED.full_name,
        -- Do not overwrite timezone/country on re-signup conflict; use profile RPCs
        company_id = COALESCE(EXCLUDED.company_id, users.company_id),
        department = COALESCE(EXCLUDED.department, users.department)
  RETURNING * INTO v_row;

  -- v1.6.11 (O-16 / Q11): golden spoons at signup (once per employee profile; CHR Coins stay 0 / v2).
  -- v1.6.16: amount = agent_settings.golden_spoons_per_onboarding (default 10.0); "לא הוגדר" → nothing.
  v_onboard := COALESCE(fn_agent_setting_num(v_row.company_id, 'golden_spoons_per_onboarding'), 0);
  IF NOT v_existed AND v_row.has_employee_profile AND v_onboard > 0 THEN
    INSERT INTO avatar_state (user_id, golden_spoons)
    VALUES (v_uid, v_onboard)
    ON CONFLICT (user_id) DO UPDATE
      SET golden_spoons = avatar_state.golden_spoons + v_onboard,
          updated_at = clock_timestamp();
  END IF;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION rpc_signup_profile(varchar, varchar, text, char, uuid, varchar, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_signup_profile(varchar, varchar, text, char, uuid, varchar, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- rpc_update_profile_timezone — profile change of IANA zone (N-4)
-- Rejects missing with timezone_required; invalid with invalid_timezone (HTTP 400).
-- Existing value kept on reject. Optional p_country_code updates country when provided.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_update_profile_timezone(
  p_timezone     text,
  p_country_code char(2) DEFAULT NULL
)
RETURNS users
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row users;
  v_tz  text;
  v_cc  char(2);
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'anti_get_blocked'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=anti_get_blocked', HINT = 'anti_get_blocked';
  END IF;

  v_tz := NULLIF(btrim(COALESCE(p_timezone, '')), '');
  IF v_tz IS NULL THEN
    RAISE EXCEPTION 'timezone_required'
      USING ERRCODE = '22004',
            DETAIL = 'http_hint=400;code=timezone_required',
            HINT = 'timezone_required';
  END IF;
  IF NOT fn_is_valid_iana_timezone(v_tz) THEN
    RAISE EXCEPTION 'invalid_timezone'
      USING ERRCODE = '22023',
            DETAIL = 'http_hint=400;code=invalid_timezone',
            HINT = 'invalid_timezone';
  END IF;

  IF p_country_code IS NOT NULL THEN
    v_cc := upper(btrim(p_country_code::text))::char(2);
    IF v_cc !~ '^[A-Z]{2}$' THEN
      RAISE EXCEPTION 'invalid_timezone'
        USING ERRCODE = '22023',
              DETAIL = 'http_hint=400;code=invalid_timezone',
              HINT = 'invalid_timezone';
    END IF;
  END IF;

  UPDATE users
     SET timezone = v_tz,
         country_code = COALESCE(v_cc, country_code)
   WHERE user_id = v_uid
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'anti_get_blocked'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=anti_get_blocked', HINT = 'anti_get_blocked';
  END IF;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION rpc_update_profile_timezone(text, char) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_update_profile_timezone(text, char) TO authenticated;

-- ---------------------------------------------------------------------------
-- rpc_upsert_employee_value_asset — salary inputs (self or manager/vp_hr) and
-- turnover tier override (vp_hr / CHRO only; O-2: defaults automatically from org_role.tier).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_upsert_employee_value_asset(
  p_user_id           uuid,
  p_annual_salary     numeric DEFAULT NULL,
  p_direct_cost_opex  numeric DEFAULT NULL,
  p_asset_value_capex numeric DEFAULT NULL,
  p_turnover_tier     text DEFAULT NULL
)
RETURNS employee_value_asset
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row employee_value_asset;
BEGIN
  IF v_uid IS NULL THEN
    PERFORM fn_raise_business('anti_get_blocked');
  END IF;
  IF v_uid <> p_user_id AND fn_app_role() NOT IN ('manager', 'vp_hr') THEN
    PERFORM fn_raise_business('anti_get_blocked');
  END IF;
  IF p_turnover_tier IS NOT NULL AND fn_app_role() <> 'vp_hr' THEN
    PERFORM fn_raise_business('anti_get_blocked');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE user_id = p_user_id) THEN
    PERFORM fn_raise_business('anti_get_blocked');
  END IF;

  INSERT INTO employee_value_asset (
    user_id, annual_salary, turnover_tier, turnover_tier_override, direct_cost_opex, asset_value_capex, updated_at
  ) VALUES (
    p_user_id, p_annual_salary, p_turnover_tier, (p_turnover_tier IS NOT NULL),
    COALESCE(p_direct_cost_opex, 0), p_asset_value_capex, clock_timestamp()
  )
  ON CONFLICT (user_id) DO UPDATE SET
    annual_salary          = COALESCE(EXCLUDED.annual_salary, employee_value_asset.annual_salary),
    turnover_tier          = CASE WHEN p_turnover_tier IS NOT NULL THEN p_turnover_tier ELSE employee_value_asset.turnover_tier END,
    turnover_tier_override = employee_value_asset.turnover_tier_override OR (p_turnover_tier IS NOT NULL),
    direct_cost_opex       = COALESCE(p_direct_cost_opex, employee_value_asset.direct_cost_opex),
    asset_value_capex      = COALESCE(EXCLUDED.asset_value_capex, employee_value_asset.asset_value_capex),
    updated_at             = clock_timestamp()
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION rpc_upsert_employee_value_asset(uuid, numeric, numeric, numeric, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_upsert_employee_value_asset(uuid, numeric, numeric, numeric, text) TO authenticated;

-- rpc_set_deprivation_flag — SYSTEM path only (service_role). Clients cannot set it.
-- O-3 (Karin 24.10): weekly deprivation is computed automatically by fn_is_employee_deprived
-- (weekly avg spoons < 5 OR weekly B_t >= 0.65); this system hook sets the fallback flag.
CREATE OR REPLACE FUNCTION rpc_set_deprivation_flag(p_user_id uuid, p_is_deprived boolean)
RETURNS employee_value_asset
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_row employee_value_asset;
BEGIN
  INSERT INTO employee_value_asset (user_id, is_deprived)
  VALUES (p_user_id, p_is_deprived)
  ON CONFLICT (user_id) DO UPDATE
     SET is_deprived = EXCLUDED.is_deprived, updated_at = clock_timestamp()
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION rpc_set_deprivation_flag(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_set_deprivation_flag(uuid, boolean) TO service_role;

-- ---------------------------------------------------------------------------
-- Deferred to v2 (locked 2026-10-12 / 2026-10-24 / 2026-10-25):
-- * CHR Coins earn amounts per action & CHR Coins shelf items/prices (O-16: v2)
-- * Avatar weight / immunity; Contrast Nullification; Dutch auction; sensors/HRV (O-22: v2)
-- * Golden Spoons never expire while the employee is active (locked 25.10)
-- ---------------------------------------------------------------------------

-- =============================================================================
-- v1.6.1 — role-tree access (B2), project manager (B3), board (B4),
-- emergency mode (B5), distress button (B6). Every view is audited (access_audit_log).
-- =============================================================================

-- 400 helper (SQLSTATE 22023 → PostgREST 400) for missing / invalid input.
CREATE OR REPLACE FUNCTION fn_raise_bad_request(p_code text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION '%', p_code
    USING ERRCODE = '22023', DETAIL = format('http_hint=400;code=%s', p_code), HINT = p_code;
END;
$$;

-- Spoon + TPS-12 figures for an explicit set of employees (internal). Each figure is
-- NULL unless its own contributors reach N_regular; contributor_count = union (lock #3).
CREATE OR REPLACE FUNCTION fn_group_wellbeing(p_users uuid[])
RETURNS TABLE (contributor_count int, spoon_reporter_count int, team_spoon_avg numeric,
               tps_respondent_count int, tps_avg numeric, alert_level dichotomous_alert_enum)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_min int := fn_privacy_min_n('regular');
BEGIN
  RETURN QUERY
  WITH sp AS (
    SELECT sb.user_id, sb.current_spoon_count FROM spoon_budget sb JOIN users u ON u.user_id = sb.user_id
     WHERE sb.user_id = ANY (p_users) AND sb.reported_at IS NOT NULL
       AND sb.budget_date = (clock_timestamp() AT TIME ZONE u.timezone)::date
  ), tp AS (
    SELECT q.user_id, q.tps_12_score FROM questionnaire_submission q JOIN users u ON u.user_id = q.user_id
     WHERE q.user_id = ANY (p_users) AND q.questionnaire_code = 'TPS-12'
       AND q.period_key = fn_period_key('quarterly', (clock_timestamp() AT TIME ZONE u.timezone)::date)
  ), agg AS (
    SELECT (SELECT count(*)::int FROM sp) AS sp_n, (SELECT round(avg(current_spoon_count), 2) FROM sp) AS sp_avg,
           (SELECT count(*)::int FROM tp) AS tp_n, (SELECT round(avg(tps_12_score), 2) FROM tp) AS tp_avg,
           (SELECT count(DISTINCT x.user_id)::int FROM (SELECT user_id FROM sp UNION SELECT user_id FROM tp) x) AS n
  )
  SELECT a.n, a.sp_n,
         CASE WHEN a.sp_n >= v_min THEN a.sp_avg END,
         a.tp_n,
         CASE WHEN a.tp_n >= v_min THEN a.tp_avg END,
         fn_spoon_alert_level(CASE WHEN a.sp_n >= v_min THEN a.sp_avg END)
    FROM agg a;
END;
$$;

REVOKE ALL ON FUNCTION fn_group_wellbeing(uuid[]) FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- B2 rpc_subtree_summary — a manager reads aggregates of her SOLID-line subtree
-- (default: her own). Dotted lines never grant access. CEO (averages-only) and the CHRO
-- may pick any root in the company. Employees / project managers / safety manager → 403.
-- N = actual contributors in the subtree (≥5), otherwise 403.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_subtree_summary(p_root uuid DEFAULT NULL)
RETURNS TABLE (contributor_count int, spoon_reporter_count int, team_spoon_avg numeric,
               tps_respondent_count int, tps_avg numeric, alert_level dichotomous_alert_enum)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_role  org_role := fn_viewer_role();
  v_root  uuid := COALESCE(p_root, auth.uid());
  v_users uuid[];
  v_n     int;
BEGIN
  IF auth.uid() IS NULL OR v_role IS NULL OR NOT (v_role.is_management OR fn_is_chro()) THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  IF v_root <> auth.uid() THEN
    IF v_role.averages_only OR fn_is_chro() THEN
      IF NOT EXISTS (SELECT 1 FROM users u WHERE u.user_id = v_root AND u.company_id = fn_my_company()) THEN
        PERFORM fn_raise_business('access_denied');
      END IF;
    ELSIF NOT fn_in_solid_subtree(auth.uid(), v_root) THEN
      PERFORM fn_raise_business('access_denied');   -- outside the solid line (dotted line ≠ access)
    END IF;
  END IF;
  SELECT array_agg(s.user_id) INTO v_users FROM fn_solid_subtree(v_root) s;
  SELECT g.contributor_count INTO v_n FROM fn_group_wellbeing(COALESCE(v_users, '{}')) g;
  PERFORM fn_assert_privacy_threshold(v_n, 'regular');
  PERFORM fn_audit_view('subtree_summary', jsonb_build_object('root', v_root));
  RETURN QUERY SELECT * FROM fn_group_wellbeing(v_users);
END;
$$;

-- ---------------------------------------------------------------------------
-- B2 rpc_direct_reports_pseudonyms — a DIRECT manager sees her direct reports by
-- pseudonym only (never names / ids). Averages-only roles (CEO, owners, board) → 403.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_direct_reports_pseudonyms()
RETURNS TABLE (display_pseudonym varchar)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_role org_role := fn_viewer_role();
BEGIN
  IF auth.uid() IS NULL OR v_role IS NULL OR NOT v_role.is_management OR v_role.averages_only THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  PERFORM fn_audit_view('direct_reports_pseudonyms');
  RETURN QUERY SELECT u.display_pseudonym FROM users u
                WHERE u.reports_to = auth.uid() AND u.employment_ended_at IS NULL
                ORDER BY u.display_pseudonym;
END;
$$;

-- ---------------------------------------------------------------------------
-- B2 rpc_company_averages — CEO, owners, board_chair / board_member (O-25: tier 5 governance
-- roles see whole-company organizational averages only, never team or individual breakdowns),
-- and management / CHRO read company-wide averages only.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_company_averages()
RETURNS TABLE (contributor_count int, spoon_reporter_count int, team_spoon_avg numeric,
               tps_respondent_count int, tps_avg numeric, alert_level dichotomous_alert_enum)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_role  org_role := fn_viewer_role();
  v_users uuid[];
  v_n     int;
BEGIN
  IF auth.uid() IS NULL OR v_role IS NULL
     OR NOT (v_role.is_management OR v_role.is_governance OR fn_is_chro()) THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  SELECT array_agg(u.user_id) INTO v_users FROM users u
   WHERE u.company_id = fn_my_company() AND u.has_employee_profile AND u.employment_ended_at IS NULL;
  SELECT g.contributor_count INTO v_n FROM fn_group_wellbeing(COALESCE(v_users, '{}')) g;
  PERFORM fn_assert_privacy_threshold(v_n, 'regular');
  PERFORM fn_audit_view('company_averages');
  RETURN QUERY SELECT * FROM fn_group_wellbeing(v_users);
END;
$$;

-- ---------------------------------------------------------------------------
-- O-25 (Karin 24.10): rpc_get_board_macro_metrics — Tier 5 governance roles
-- (board_chair, board_member, owner_shareholder) read all company-wide organizational averages
-- at the WHOLE-COMPANY level only (never any team, department, division, or individual breakdown):
--   * Regular company-wide metrics (each requires N >= 5 actual company respondents, else NULL):
--       TPS-12 (tps12_company_avg), spoons (spoons_company_avg), workload / EPWI / PEWI
--       (epwi_time_company_avg, epwi_cognitive_company_avg, pewi_company_avg), IHS (ihs_company_avg).
--   * Sensitive / Shadow Balance company-wide metrics (require N >= 10 actual company contributors,
--       else NULL): Happiness Debt (happiness_debt_balance), 12 % deprivation tax
--       (deprivation_tax_amount), shadow_balance_sum, and CHR Real EBITDA (chr_real_ebitda).
--   * Overall company contributor_count must reach at least N_regular (5), else 403
--     aggregation_privacy_threshold.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_get_board_macro_metrics(
  p_gaap_reported_ebitda numeric DEFAULT NULL
)
RETURNS TABLE (
  company_id                 uuid,
  contributor_count          int,
  spoon_reporter_count       int,
  spoons_company_avg         numeric,
  tps_respondent_count       int,
  tps12_company_avg          numeric,
  ihs_respondent_count       int,
  ihs_company_avg            numeric,
  workload_respondent_count  int,
  epwi_time_company_avg      numeric,
  epwi_cognitive_company_avg numeric,
  pewi_company_avg           numeric,
  shadow_contributor_count   int,
  deprived_count             int,
  happiness_debt_balance     numeric,
  deprivation_tax_amount     numeric,
  shadow_balance_sum         numeric,
  gaap_reported_ebitda       numeric,
  chr_real_ebitda            numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_role       org_role := fn_viewer_role();
  v_comp       uuid := fn_my_company();
  v_min_reg    int := fn_privacy_min_n('regular');          -- 5
  v_min_sb     int := fn_privacy_min_n('shadow_balance');   -- 10
  v_total_n    int;
  v_sp_n       int;
  v_sp_avg     numeric;
  v_tps_n      int;
  v_tps_avg    numeric;
  v_ihs_n      int;
  v_ihs_avg    numeric;
  v_wl_n       int;
  v_epwi_t     numeric;
  v_epwi_c     numeric;
  v_pewi       numeric;
  v_sb_n       int;
  v_dep_n      int;
  v_debt       numeric;
  v_tax        numeric;
  v_shadow     numeric;
  v_gaap       numeric;
  v_real_ebit  numeric;
BEGIN
  -- Governance roles (board_chair, board_member, owner_shareholder) of the company only
  IF auth.uid() IS NULL OR v_role IS NULL OR v_comp IS NULL
     OR NOT v_role.is_governance THEN
    PERFORM fn_raise_business('access_denied');
  END IF;

  -- 1. Spoons reported today across the whole company
  SELECT count(DISTINCT sb.user_id)::int, round(avg(sb.current_spoon_count)::numeric, 2)
    INTO v_sp_n, v_sp_avg
    FROM spoon_budget sb
    JOIN users u ON u.user_id = sb.user_id
   WHERE u.company_id = v_comp
     AND u.has_employee_profile
     AND u.employment_ended_at IS NULL
     AND sb.reported_at IS NOT NULL
     AND sb.budget_date = (clock_timestamp() AT TIME ZONE u.timezone)::date;
  IF v_sp_n < v_min_reg THEN v_sp_avg := NULL; END IF;

  -- 2. TPS-12 current quarter across the whole company
  SELECT count(DISTINCT q.user_id)::int, round(avg(q.tps_12_score), 2)
    INTO v_tps_n, v_tps_avg
    FROM questionnaire_submission q
    JOIN users u ON u.user_id = q.user_id
   WHERE u.company_id = v_comp
     AND u.employment_ended_at IS NULL
     AND q.questionnaire_code = 'TPS-12'
     AND q.period_key = fn_period_key('quarterly', (clock_timestamp() AT TIME ZONE u.timezone)::date);
  IF v_tps_n < v_min_reg THEN v_tps_avg := NULL; END IF;

  -- 3. IHS current quarter across the whole company
  SELECT count(DISTINCT q.user_id)::int, round(avg(q.ihs_score), 2)
    INTO v_ihs_n, v_ihs_avg
    FROM questionnaire_submission q
    JOIN users u ON u.user_id = q.user_id
   WHERE u.company_id = v_comp
     AND u.employment_ended_at IS NULL
     AND q.questionnaire_code = 'IHS'
     AND q.period_key = fn_period_key('quarterly', (clock_timestamp() AT TIME ZONE u.timezone)::date);
  IF v_ihs_n < v_min_reg THEN v_ihs_avg := NULL; END IF;

  -- 4. Workload / EPWI_time / EPWI_cognitive / PEWI in the current company week across the whole company
  SELECT count(DISTINCT w.user_id)::int,
         round(avg(fn_epwi_time(w.hours_worked, w.contract_hours)), 2),
         round(avg(fn_epwi_cognitive(fn_epwi_time(w.hours_worked, w.contract_hours), w.parallel_projects)), 2)
    INTO v_wl_n, v_epwi_t, v_epwi_c
    FROM workload_self_report w
    JOIN users u ON u.user_id = w.user_id
   WHERE u.company_id = v_comp
     AND u.employment_ended_at IS NULL
     AND w.week_start_date = fn_local_week_start(u.user_id);
  IF v_wl_n < v_min_reg THEN
    v_epwi_t := NULL; v_epwi_c := NULL; v_pewi := NULL;
  ELSE
    v_pewi := v_epwi_t;   -- company-wide PEWI = mean EPWI_time of reporting employees
  END IF;

  -- 5. Sensitive / Shadow Balance whole-company figures (requires N >= 10 actual contributors)
  SELECT count(DISTINCT c.user_id)::int INTO v_sb_n FROM (
    SELECT e.user_id FROM employee_value_asset e JOIN users u ON u.user_id = e.user_id
     WHERE u.company_id = v_comp AND u.employment_ended_at IS NULL
       AND fn_effective_turnover_tier(u.user_id) IS NOT NULL AND e.annual_salary IS NOT NULL
    UNION
    SELECT sb.user_id FROM spoon_budget sb JOIN users u ON u.user_id = sb.user_id
     WHERE u.company_id = v_comp AND u.employment_ended_at IS NULL
       AND fn_effective_turnover_tier(u.user_id) IS NOT NULL AND sb.reported_at IS NOT NULL
       AND sb.budget_date BETWEEN COALESCE(fn_local_week_start(u.user_id), fn_user_local_date(u.user_id) - 6)
                              AND COALESCE(fn_local_week_start(u.user_id), fn_user_local_date(u.user_id) - 6) + 6
    UNION
    SELECT w.user_id FROM workload_self_report w JOIN users u ON u.user_id = w.user_id
     WHERE u.company_id = v_comp AND u.employment_ended_at IS NULL
       AND fn_effective_turnover_tier(u.user_id) IS NOT NULL
       AND w.week_start_date = fn_local_week_start(u.user_id)
  ) c;

  -- Total distinct contributors across all company-wide sources
  SELECT count(DISTINCT x.user_id)::int INTO v_total_n FROM (
    SELECT sb.user_id FROM spoon_budget sb JOIN users u ON u.user_id = sb.user_id
     WHERE u.company_id = v_comp AND u.employment_ended_at IS NULL AND sb.reported_at IS NOT NULL
       AND sb.budget_date = (clock_timestamp() AT TIME ZONE u.timezone)::date
    UNION
    SELECT q.user_id FROM questionnaire_submission q JOIN users u ON u.user_id = q.user_id
     WHERE u.company_id = v_comp AND u.employment_ended_at IS NULL
       AND q.questionnaire_code IN ('TPS-12', 'IHS')
       AND q.period_key = fn_period_key('quarterly', (clock_timestamp() AT TIME ZONE u.timezone)::date)
    UNION
    SELECT w.user_id FROM workload_self_report w JOIN users u ON u.user_id = w.user_id
     WHERE u.company_id = v_comp AND u.employment_ended_at IS NULL
       AND w.week_start_date = fn_local_week_start(u.user_id)
    UNION
    SELECT e.user_id FROM employee_value_asset e JOIN users u ON u.user_id = e.user_id
     WHERE u.company_id = v_comp AND u.employment_ended_at IS NULL AND e.annual_salary IS NOT NULL
  ) x;

  PERFORM fn_assert_privacy_threshold(v_total_n, 'regular');

  IF v_sb_n >= v_min_sb THEN
    WITH m AS (
      SELECT u.user_id,
             fn_effective_turnover_tier(u.user_id) AS t_grp,
             fn_is_employee_deprived(u.user_id) AS deprived,
             fn_company_tier_avg_salary(v_comp, fn_effective_turnover_tier(u.user_id)) AS tier_salary
        FROM users u
       WHERE u.company_id = v_comp
         AND u.employment_ended_at IS NULL
         AND fn_effective_turnover_tier(u.user_id) IS NOT NULL
    )
    SELECT count(*) FILTER (WHERE m.deprived)::int,
           round(COALESCE(sum(m.tier_salary * fn_turnover_tier_midpoint_factor(m.t_grp)) FILTER (WHERE m.deprived), 0), 2),
           round(COALESCE(sum(m.tier_salary * fn_chr_productivity_factor()) FILTER (WHERE m.deprived), 0), 2)
      INTO v_dep_n, v_debt, v_tax
      FROM m;
    v_shadow := round(COALESCE(v_debt, 0) + COALESCE(v_tax, 0), 2);
    v_gaap := COALESCE(p_gaap_reported_ebitda,
                       (SELECT s.gaap_reported_ebitda FROM shadow_balance_aggregate s
                         WHERE s.org_id = v_comp AND s.gaap_reported_ebitda IS NOT NULL
                         ORDER BY s.calculated_at DESC LIMIT 1));
    IF v_gaap IS NOT NULL THEN
      v_real_ebit := fn_chr_real_ebitda(v_gaap, v_debt, v_tax);
    END IF;
  END IF;

  PERFORM fn_audit_view('board_macro_metrics', jsonb_build_object('company_id', v_comp));

  RETURN QUERY SELECT
    v_comp, v_total_n,
    v_sp_n, v_sp_avg,
    v_tps_n, v_tps_avg,
    v_ihs_n, v_ihs_avg,
    v_wl_n, v_epwi_t, v_epwi_c, v_pewi,
    v_sb_n, v_dep_n, v_debt, v_tax, v_shadow, v_gaap, v_real_ebit;
END;
$$;

-- ---------------------------------------------------------------------------
-- O-20 (Chief of Drive 24.10): rpc_provision_governance_user — CHRO (vp_hr) provisions
-- tier-5 governance users (board_chair, board_member, owner_shareholder), defaulting
-- has_employee_profile = false unless explicitly marked as also an employee (p_also_employee = true).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_provision_governance_user(
  p_user_id       uuid,
  p_email         varchar,
  p_full_name     varchar,
  p_org_role_code text,
  p_timezone      text,
  p_also_employee boolean DEFAULT false,
  p_department    varchar DEFAULT 'Board'
)
RETURNS users
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_comp uuid := fn_my_company();
  v_row  users;
BEGIN
  IF auth.uid() IS NULL OR NOT fn_is_chro() OR v_comp IS NULL THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  IF p_user_id IS NULL OR p_email IS NULL OR btrim(p_email) = '' OR p_full_name IS NULL OR btrim(p_full_name) = '' THEN
    PERFORM fn_raise_bad_request('invalid_governance_role');
  END IF;
  IF p_org_role_code IS NULL OR p_org_role_code NOT IN ('board_chair', 'board_member', 'owner_shareholder') THEN
    PERFORM fn_raise_bad_request('invalid_governance_role');
  END IF;

  INSERT INTO auth.users (id) VALUES (p_user_id) ON CONFLICT (id) DO NOTHING;

  INSERT INTO users (
    user_id, company_id, email, full_name, department,
    app_role, org_role_code, timezone, has_employee_profile
  ) VALUES (
    p_user_id, v_comp, btrim(p_email), btrim(p_full_name), COALESCE(NULLIF(btrim(p_department), ''), 'Board'),
    p_org_role_code, p_org_role_code, p_timezone, COALESCE(p_also_employee, false)
  )
  ON CONFLICT (user_id) DO UPDATE SET
    company_id           = v_comp,
    email                = EXCLUDED.email,
    full_name            = EXCLUDED.full_name,
    department           = EXCLUDED.department,
    app_role             = EXCLUDED.app_role,
    org_role_code        = EXCLUDED.org_role_code,
    timezone             = EXCLUDED.timezone,
    has_employee_profile = EXCLUDED.has_employee_profile
  RETURNING * INTO v_row;

  PERFORM fn_audit_view('provision_governance_user',
                        jsonb_build_object('user_id', p_user_id, 'role', p_org_role_code,
                                           'has_employee_profile', v_row.has_employee_profile),
                        p_user_id);
  RETURN v_row;
END;
$$;

-- ---------------------------------------------------------------------------
-- O-19 (Chief of Drive 24.10): Manager Vault RPCs
--   * Direct manager only (is_management = true, averages_only = false, active employment,
--     has at least one active solid-line direct report).
--   * Requires BOTH office network AND company device (is_office_network = true AND
--     is_company_device = true; else 403 manager_vault_environment_denied).
--   * Inactivity timeout (default 15 minutes): any read/write after last_active_at + timeout
--     wipes/closes the session and raises 403 manager_vault_session_expired.
--   * Transfer or dismissal wipes the vault immediately via trg_users_manager_vault_guard.
-- ---------------------------------------------------------------------------

-- Check that the caller is an eligible direct manager with an active, non-expired vault session.
CREATE OR REPLACE FUNCTION fn_assert_manager_vault_active()
RETURNS manager_vault_session
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_role org_role := fn_viewer_role();
  v_sess manager_vault_session;
BEGIN
  IF v_uid IS NULL OR v_role IS NULL OR NOT v_role.is_management OR v_role.averages_only THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM users u WHERE u.reports_to = v_uid AND u.employment_ended_at IS NULL) THEN
    PERFORM fn_raise_business('access_denied');
  END IF;

  SELECT * INTO v_sess FROM manager_vault_session WHERE manager_id = v_uid;
  IF NOT FOUND OR v_sess.wiped_at IS NOT NULL OR NOT v_sess.is_office_network OR NOT v_sess.is_company_device THEN
    PERFORM fn_raise_business('manager_vault_environment_denied');
  END IF;

  IF clock_timestamp() > v_sess.last_active_at + make_interval(mins => v_sess.timeout_minutes) THEN
    UPDATE manager_vault_session
       SET is_office_network = false,
           is_company_device = false,
           wiped_at          = clock_timestamp(),
           wipe_reason       = 'inactivity_timeout'
     WHERE manager_id = v_uid;
    PERFORM fn_raise_business('manager_vault_session_expired');
  END IF;

  UPDATE manager_vault_session
     SET last_active_at = clock_timestamp()
   WHERE manager_id = v_uid
  RETURNING * INTO v_sess;

  RETURN v_sess;
END;
$$;

REVOKE ALL ON FUNCTION fn_assert_manager_vault_active() FROM PUBLIC;

-- Open / refresh a direct manager's private vault session on office network + company computer.
CREATE OR REPLACE FUNCTION rpc_manager_vault_open(
  p_is_office_network boolean,
  p_is_company_device boolean,
  p_timeout_minutes   int DEFAULT 15
)
RETURNS manager_vault_session
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_role org_role := fn_viewer_role();
  v_sess manager_vault_session;
BEGIN
  IF v_uid IS NULL OR v_role IS NULL OR NOT v_role.is_management OR v_role.averages_only THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM users u WHERE u.reports_to = v_uid AND u.employment_ended_at IS NULL) THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  IF NOT COALESCE(p_is_office_network, false) OR NOT COALESCE(p_is_company_device, false) THEN
    PERFORM fn_raise_business('manager_vault_environment_denied');
  END IF;
  IF p_timeout_minutes IS NULL OR p_timeout_minutes < 1 OR p_timeout_minutes > 60 THEN
    PERFORM fn_raise_bad_request('invalid_vault_timeout');
  END IF;

  INSERT INTO manager_vault_session (
    manager_id, is_office_network, is_company_device, timeout_minutes, opened_at, last_active_at, wiped_at, wipe_reason
  ) VALUES (
    v_uid, true, true, p_timeout_minutes, clock_timestamp(), clock_timestamp(), NULL, NULL
  )
  ON CONFLICT (manager_id) DO UPDATE SET
    is_office_network = true,
    is_company_device = true,
    timeout_minutes   = EXCLUDED.timeout_minutes,
    opened_at         = clock_timestamp(),
    last_active_at    = clock_timestamp(),
    wiped_at          = NULL,
    wipe_reason       = NULL
  RETURNING * INTO v_sess;

  PERFORM fn_audit_view('manager_vault_open', jsonb_build_object('timeout_minutes', p_timeout_minutes));
  RETURN v_sess;
END;
$$;

-- Store / update a direct report's entry in the direct manager's private vault.
CREATE OR REPLACE FUNCTION rpc_manager_vault_put(
  p_subject_user_id uuid,
  p_encrypted_note  bytea DEFAULT NULL
)
RETURNS manager_vault_entry
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid   uuid := auth.uid();
  v_sub   users;
  v_entry manager_vault_entry;
BEGIN
  PERFORM fn_assert_manager_vault_active();

  SELECT * INTO v_sub FROM users
   WHERE user_id = p_subject_user_id
     AND reports_to = v_uid
     AND employment_ended_at IS NULL;
  IF NOT FOUND THEN
    PERFORM fn_raise_business('access_denied');
  END IF;

  INSERT INTO manager_vault_entry (
    manager_id, subject_user_id, display_pseudonym, encrypted_note, updated_at
  ) VALUES (
    v_uid, v_sub.user_id, v_sub.display_pseudonym, p_encrypted_note, clock_timestamp()
  )
  ON CONFLICT (manager_id, subject_user_id) DO UPDATE SET
    display_pseudonym = EXCLUDED.display_pseudonym,
    encrypted_note    = EXCLUDED.encrypted_note,
    updated_at        = clock_timestamp()
  RETURNING * INTO v_entry;

  PERFORM fn_audit_view('manager_vault_put', jsonb_build_object('subject_pseudonym', v_sub.display_pseudonym));
  RETURN v_entry;
END;
$$;

-- Read the direct manager's private vault entries (only active direct reports, requires active session).
CREATE OR REPLACE FUNCTION rpc_manager_vault_entries()
RETURNS TABLE (
  entry_id          uuid,
  subject_user_id   uuid,
  full_name         varchar,
  display_pseudonym varchar,
  encrypted_note    bytea,
  updated_at        timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  PERFORM fn_assert_manager_vault_active();
  PERFORM fn_audit_view('manager_vault_read');

  RETURN QUERY
  SELECT e.entry_id, e.subject_user_id, u.full_name, u.display_pseudonym, e.encrypted_note, e.updated_at
    FROM manager_vault_entry e
    JOIN users u ON u.user_id = e.subject_user_id
   WHERE e.manager_id = v_uid
     AND u.reports_to = v_uid
     AND u.employment_ended_at IS NULL
   ORDER BY u.display_pseudonym;
END;
$$;

-- Explicitly close / lock the direct manager's vault session.
CREATE OR REPLACE FUNCTION rpc_manager_vault_close()
RETURNS manager_vault_session
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_sess manager_vault_session;
BEGIN
  IF v_uid IS NULL THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  UPDATE manager_vault_session
     SET is_office_network = false,
         is_company_device = false,
         wiped_at          = clock_timestamp(),
         wipe_reason       = 'manual_close'
   WHERE manager_id = v_uid
  RETURNING * INTO v_sess;
  RETURN v_sess;
END;
$$;

-- ---------------------------------------------------------------------------
-- B2 rpc_chro_named_view — the CHRO (app_role vp_hr) sees NAMED data of one employee
-- only with a reason; every view is audited with the reason.
-- Q6 (locked 12.10): any reason permitted under labour law. Free text, but required (non-empty,
-- also enforced by CHECK chk_audit_chro_reason); every view audited. Formerly: free
--   text required for now.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_chro_named_view(p_user_id uuid, p_reason text)
RETURNS TABLE (user_id uuid, full_name varchar, department varchar, org_role_code text,
               day_status day_status_enum, last_early_leave date)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT fn_is_chro() THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    PERFORM fn_raise_bad_request('reason_required');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM users u WHERE u.user_id = p_user_id AND u.company_id = fn_my_company()) THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  PERFORM fn_audit_view('chro_named_view', '{}'::jsonb, p_user_id, trim(p_reason));
  RETURN QUERY
  SELECT u.user_id, u.full_name, u.department::varchar, u.org_role_code,
         (SELECT sb.day_status FROM spoon_budget sb WHERE sb.user_id = u.user_id ORDER BY sb.budget_date DESC LIMIT 1),
         (SELECT max(l.local_date) FROM early_leave_log l WHERE l.user_id = u.user_id)
    FROM users u WHERE u.user_id = p_user_id;
END;
$$;

-- B3 rpc_project_load was removed in v1.6.3 — see rpc_project_workload (workload module).

-- ---------------------------------------------------------------------------
-- B4 rpc_board_macro_trends — board chair / members: quarterly or annual macro trends
-- of the company or of ONE division (root = a division_manager). Closed periods only
-- (no real-time), no drill-down below division, each period needs ≥20 actual
-- respondents (rows below are suppressed; none left → 403).
-- Historical closed-quarter/year TPS-12 series. For whole-company macro metrics across all indicators see rpc_get_board_macro_metrics (O-25).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_board_macro_trends(p_granularity text, p_division_root uuid DEFAULT NULL)
RETURNS TABLE (period_start date, respondent_count int, tps_avg numeric)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_users uuid[];
  v_min   int := fn_privacy_min_n('board');
BEGIN
  IF auth.uid() IS NULL OR NOT (fn_viewer_has_role('board_chair') OR fn_viewer_has_role('board_member')) THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  IF p_granularity IS NULL OR p_granularity NOT IN ('quarter', 'year') THEN
    PERFORM fn_raise_bad_request('invalid_period');
  END IF;
  IF p_division_root IS NULL THEN
    SELECT array_agg(u.user_id) INTO v_users FROM users u WHERE u.company_id = fn_my_company();
  ELSE
    -- No drill-down: only a division root (division_manager) of the board's company.
    IF NOT EXISTS (SELECT 1 FROM users u WHERE u.user_id = p_division_root
                    AND u.company_id = fn_my_company() AND u.org_role_code = 'division_manager') THEN
      PERFORM fn_raise_business('access_denied');
    END IF;
    SELECT array_agg(s.user_id) INTO v_users FROM fn_solid_subtree(p_division_root) s;
  END IF;

  RETURN QUERY
  SELECT date_trunc(p_granularity, q.submitted_at AT TIME ZONE u.timezone)::date,
         count(DISTINCT q.user_id)::int, round(avg(q.tps_12_score), 2)
    FROM questionnaire_submission q JOIN users u ON u.user_id = q.user_id
   WHERE q.user_id = ANY (COALESCE(v_users, '{}')) AND q.questionnaire_code = 'TPS-12'
     AND date_trunc(p_granularity, q.submitted_at AT TIME ZONE u.timezone)
         < date_trunc(p_granularity, clock_timestamp() AT TIME ZONE u.timezone)   -- closed periods only
   GROUP BY 1
  HAVING count(DISTINCT q.user_id) >= v_min       -- periods below N=20 respondents are suppressed
   ORDER BY 1;
  IF NOT FOUND THEN
    PERFORM fn_raise_business('aggregation_privacy_threshold');
  END IF;
  PERFORM fn_audit_view('board_macro_trends', jsonb_build_object('granularity', p_granularity, 'division_root', p_division_root));
END;
$$;

-- ---------------------------------------------------------------------------
-- B5 Emergency mode. Only the safety & emergency manager declares and ends it.
-- Immediate access (no reason, no threshold) to the roster while ACTIVE only; HR review
-- by the CHRO afterwards. Misuse rule: access outside an active emergency is refused;
-- the HR review may mark the declaration MISUSE (recorded immutably in the audit log).
-- 3 types locked 13.10; misuse sequence (Q5) + CHRO co-sign (Q7 / O-35) encoded below.
-- ---------------------------------------------------------------------------

-- Safety manager of the given company (internal).
CREATE OR REPLACE FUNCTION fn_is_safety_manager_of(p_company uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT fn_viewer_has_role('safety_emergency_manager') AND fn_my_company() = p_company
$$;

REVOKE ALL ON FUNCTION fn_is_safety_manager_of(uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION rpc_emergency_declare(p_type emergency_type_enum)
RETURNS emergency_event
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_row     emergency_event;
  v_alone   boolean;
BEGIN
  IF auth.uid() IS NULL OR NOT fn_viewer_has_role('safety_emergency_manager') THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  -- Q5: after a second MISUSE the declarer loses the right to open alone → co-sign needed.
  v_alone := fn_emergency_may_open_alone(auth.uid());
  BEGIN
    INSERT INTO emergency_event (company_id, emergency_type, declared_by, status)
    VALUES (fn_my_company(), p_type, auth.uid(), CASE WHEN v_alone THEN 'ACTIVE' ELSE 'PENDING_COSIGN' END)
    RETURNING * INTO v_row;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'emergency_already_active'
      USING ERRCODE = '23505', DETAIL = 'http_hint=409;code=emergency_already_active', HINT = 'emergency_already_active';
  END;
  IF v_alone THEN
    PERFORM fn_emergency_notify_chro(v_row, 'emergency_declared');
  ELSE
    PERFORM fn_emergency_request_cosign(v_row);
  END IF;
  PERFORM fn_audit_view(CASE WHEN v_alone THEN 'emergency_declare' ELSE 'emergency_declare_pending_cosign' END,
                        jsonb_build_object('event_id', v_row.event_id, 'type', p_type));
  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION rpc_emergency_end(p_event_id uuid)
RETURNS emergency_event
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_row emergency_event;
BEGIN
  SELECT * INTO v_row FROM emergency_event e WHERE e.event_id = p_event_id;
  IF auth.uid() IS NULL OR NOT FOUND OR NOT fn_is_safety_manager_of(v_row.company_id) THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  IF v_row.status <> 'ACTIVE' THEN
    PERFORM fn_raise_business('emergency_not_active');
  END IF;
  UPDATE emergency_event SET status = 'ENDED', ended_by = auth.uid(), ended_at = clock_timestamp(),
                             hr_review_status = 'PENDING'
   WHERE event_id = p_event_id RETURNING * INTO v_row;
  INSERT INTO notification (recipient_id, kind, ref_id)
  SELECT u.user_id, 'emergency_hr_review', p_event_id FROM users u
   WHERE u.company_id = v_row.company_id AND u.app_role = 'vp_hr' AND u.employment_ended_at IS NULL;
  PERFORM fn_audit_view('emergency_end', jsonb_build_object('event_id', p_event_id));
  RETURN v_row;
END;
$$;

-- Immediate access while ACTIVE: name, phone, last location, safe flag. Audited.
CREATE OR REPLACE FUNCTION rpc_emergency_roster(p_event_id uuid)
RETURNS TABLE (full_name varchar, phone varchar, last_location text, reported_safe boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_row emergency_event;
BEGIN
  SELECT * INTO v_row FROM emergency_event e WHERE e.event_id = p_event_id;
  IF auth.uid() IS NULL OR NOT FOUND OR NOT fn_is_safety_manager_of(v_row.company_id) THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  IF v_row.status <> 'ACTIVE' THEN
    PERFORM fn_raise_business('emergency_not_active');   -- misuse rule: no access after the end
  END IF;
  PERFORM fn_audit_view('emergency_roster', jsonb_build_object('event_id', p_event_id));
  RETURN QUERY
  SELECT u.full_name, u.phone, u.last_location,
         EXISTS (SELECT 1 FROM emergency_safe_report s WHERE s.event_id = p_event_id AND s.user_id = u.user_id)
    FROM users u
   WHERE u.company_id = v_row.company_id AND u.has_employee_profile AND u.employment_ended_at IS NULL
   ORDER BY u.full_name;
END;
$$;

CREATE OR REPLACE FUNCTION rpc_emergency_report_safe(p_event_id uuid)
RETURNS emergency_safe_report
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_row emergency_safe_report;
BEGIN
  IF auth.uid() IS NULL OR NOT fn_has_employee_profile(auth.uid())
     OR NOT EXISTS (SELECT 1 FROM emergency_event e WHERE e.event_id = p_event_id
                     AND e.status = 'ACTIVE' AND e.company_id = fn_my_company()) THEN
    PERFORM fn_raise_business('emergency_not_active');
  END IF;
  INSERT INTO emergency_safe_report (event_id, user_id) VALUES (p_event_id, auth.uid())
  ON CONFLICT (event_id, user_id) DO UPDATE SET reported_at = emergency_safe_report.reported_at
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

-- Team status for managers / CHRO: number of "safe" reports in a department, shown only
-- at ≥10 actual reporters (emergency scope, lock #3).
CREATE OR REPLACE FUNCTION rpc_emergency_team_status(p_event_id uuid, p_department varchar)
RETURNS TABLE (safe_reporter_count int)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_company uuid;
  v_n int;
BEGIN
  SELECT e.company_id INTO v_company FROM emergency_event e WHERE e.event_id = p_event_id;
  IF auth.uid() IS NULL OR v_company IS NULL OR NOT fn_is_org_manager(v_company) THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  SELECT count(*)::int INTO v_n FROM emergency_safe_report s JOIN users u ON u.user_id = s.user_id
   WHERE s.event_id = p_event_id AND u.department = p_department;
  PERFORM fn_assert_privacy_threshold(v_n, 'emergency');
  PERFORM fn_audit_view('emergency_team_status', jsonb_build_object('event_id', p_event_id, 'department', p_department));
  RETURN QUERY SELECT v_n;
END;
$$;

-- HR review by the CHRO after the emergency ended.
CREATE OR REPLACE FUNCTION rpc_emergency_hr_review(p_event_id uuid, p_outcome text)
RETURNS emergency_event
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_row emergency_event;
BEGIN
  SELECT * INTO v_row FROM emergency_event e WHERE e.event_id = p_event_id;
  IF auth.uid() IS NULL OR NOT FOUND OR NOT fn_is_chro() OR v_row.company_id <> fn_my_company() THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  IF p_outcome IS NULL OR p_outcome NOT IN ('JUSTIFIED', 'MISUSE') THEN
    PERFORM fn_raise_bad_request('invalid_review_outcome');
  END IF;
  IF v_row.status <> 'ENDED' OR v_row.hr_review_status <> 'PENDING' THEN
    PERFORM fn_raise_business('emergency_review_not_pending');
  END IF;
  UPDATE emergency_event SET hr_review_status = p_outcome, hr_reviewed_by = auth.uid(), hr_reviewed_at = clock_timestamp()
   WHERE event_id = p_event_id RETURNING * INTO v_row;
  IF p_outcome = 'MISUSE' THEN
    v_row := fn_emergency_apply_misuse(v_row);       -- Q5: notify the declarer (talk follows)
  ELSE
    PERFORM fn_audit_view('emergency_hr_review', jsonb_build_object('event_id', p_event_id, 'declared_by', v_row.declared_by));
  END IF;
  RETURN v_row;
END;
$$;

-- ---------------------------------------------------------------------------
-- B6 Distress button — employee-only, manual (no NLP, no automatic trigger, nobody can
-- press for someone else). 60-second grace: cancel → silent log, nothing sent. After
-- that the safety manager gets name, phone, last location and time; the CHRO gets an
-- awareness-only notice (no PII). No team access is opened. Only the safety manager
-- closes it (reason enum); on close PII is removed, the record is read-only, an immutable
-- audit row is written and the CHRO gets a silent notice. False alarms leave analytics.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_distress_press(p_location text DEFAULT NULL)
RETURNS TABLE (event_id uuid, grace_expires_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_user users%ROWTYPE;
  v_loc  text;
  v_row  distress_event;
  v_now  timestamptz := clock_timestamp();
BEGIN
  SELECT * INTO v_user FROM users u WHERE u.user_id = auth.uid();
  IF auth.uid() IS NULL OR NOT FOUND OR NOT fn_has_employee_profile(auth.uid()) THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  v_loc := COALESCE(p_location, v_user.last_location);
  IF v_loc IS NOT NULL AND v_loc NOT IN ('home', 'office', 'site') THEN
    PERFORM fn_raise_bad_request('invalid_location');
  END IF;
  -- One open event per employee: a second press returns the open one.
  SELECT * INTO v_row FROM distress_event d WHERE d.user_id = auth.uid() AND d.status IN ('GRACE', 'DISPATCHED');
  IF NOT FOUND THEN
    INSERT INTO distress_event (company_id, user_id, last_location, pressed_at, grace_expires_at)
    VALUES (v_user.company_id, auth.uid(), v_loc, v_now, v_now + interval '60 seconds')
    RETURNING * INTO v_row;
  END IF;
  RETURN QUERY SELECT v_row.event_id, v_row.grace_expires_at;
END;
$$;

CREATE OR REPLACE FUNCTION rpc_distress_cancel(p_event_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_row distress_event;
BEGIN
  SELECT * INTO v_row FROM distress_event d WHERE d.event_id = p_event_id AND d.user_id = auth.uid();
  IF auth.uid() IS NULL OR NOT FOUND THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  IF v_row.status <> 'GRACE' OR clock_timestamp() >= v_row.grace_expires_at THEN
    PERFORM fn_raise_business('distress_grace_expired');
  END IF;
  UPDATE distress_event SET status = 'CANCELLED', user_id = NULL, last_location = NULL WHERE event_id = p_event_id;
  INSERT INTO distress_silent_log (event_id, company_id) VALUES (p_event_id, v_row.company_id);
  RETURN 'CANCELLED';   -- nothing is sent to anyone
END;
$$;

-- System job (every few seconds): dispatch events whose 60-second grace passed.
CREATE OR REPLACE FUNCTION rpc_distress_dispatch_job()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_ev distress_event;
  v_n  int := 0;
BEGIN
  FOR v_ev IN SELECT * FROM distress_event d WHERE d.status = 'GRACE' AND d.grace_expires_at <= clock_timestamp()
              FOR UPDATE SKIP LOCKED LOOP
    UPDATE distress_event d
       SET status = 'DISPATCHED', dispatched_at = clock_timestamp(),
           subject_name = u.full_name, subject_phone = u.phone
      FROM users u
     WHERE d.event_id = v_ev.event_id AND u.user_id = v_ev.user_id;
    INSERT INTO notification (recipient_id, kind, ref_id)
    SELECT u.user_id, 'distress_alert', v_ev.event_id FROM users u
     WHERE u.company_id = v_ev.company_id AND u.org_role_code = 'safety_emergency_manager' AND u.employment_ended_at IS NULL;
    -- Lock 20.10: push AND sms, same transaction, same timestamp, no fallback ordering.
    PERFORM fn_distress_queue_deliveries(v_ev);
    INSERT INTO notification (recipient_id, kind, ref_id)
    SELECT u.user_id, 'distress_awareness', v_ev.event_id FROM users u
     WHERE u.company_id = v_ev.company_id AND u.app_role = 'vp_hr' AND u.employment_ended_at IS NULL;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;

-- Safety manager inbox: open (dispatched) events with PII. Audited.
CREATE OR REPLACE FUNCTION rpc_distress_safety_inbox()
RETURNS TABLE (event_id uuid, subject_name varchar, subject_phone varchar, last_location text, pressed_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT fn_viewer_has_role('safety_emergency_manager') THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  PERFORM fn_audit_view('distress_inbox');
  RETURN QUERY SELECT d.event_id, d.subject_name, d.subject_phone, d.last_location, d.pressed_at
                 FROM distress_event d
                WHERE d.company_id = fn_my_company() AND d.status = 'DISPATCHED'
                ORDER BY d.pressed_at;
END;
$$;

CREATE OR REPLACE FUNCTION rpc_distress_close(p_event_id uuid, p_reason distress_close_reason_enum)
RETURNS TABLE (event_id uuid, status text, close_reason distress_close_reason_enum)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_row distress_event;
BEGIN
  SELECT * INTO v_row FROM distress_event d WHERE d.event_id = p_event_id;
  IF auth.uid() IS NULL OR NOT FOUND OR NOT fn_is_safety_manager_of(v_row.company_id) THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  IF p_reason IS NULL THEN
    PERFORM fn_raise_bad_request('reason_required');
  END IF;
  IF v_row.status <> 'DISPATCHED' THEN
    PERFORM fn_raise_business('distress_record_immutable');
  END IF;
  UPDATE distress_event d
     SET status = 'CLOSED', closed_by = auth.uid(), closed_at = clock_timestamp(), close_reason = p_reason,
         user_id = NULL, subject_name = NULL, subject_phone = NULL, last_location = NULL
   WHERE d.event_id = p_event_id;
  PERFORM fn_audit_view('distress_closed', jsonb_build_object('event_id', p_event_id, 'reason', p_reason));
  INSERT INTO notification (recipient_id, kind, ref_id, silent)
  SELECT u.user_id, 'distress_closed', p_event_id, true FROM users u
   WHERE u.company_id = v_row.company_id AND u.app_role = 'vp_hr' AND u.employment_ended_at IS NULL;
  RETURN QUERY SELECT p_event_id, 'CLOSED'::text, p_reason;
END;
$$;

-- Grants (v1.6.1)
REVOKE ALL ON FUNCTION rpc_subtree_summary(uuid), rpc_direct_reports_pseudonyms(), rpc_company_averages(),
  rpc_get_board_macro_metrics(numeric), rpc_provision_governance_user(uuid, varchar, varchar, text, text, boolean, varchar),
  rpc_manager_vault_open(boolean, boolean, int), rpc_manager_vault_put(uuid, bytea),
  rpc_manager_vault_entries(), rpc_manager_vault_close(),
  rpc_chro_named_view(uuid, text), rpc_board_macro_trends(text, uuid),
  rpc_emergency_declare(emergency_type_enum), rpc_emergency_end(uuid), rpc_emergency_roster(uuid),
  rpc_emergency_report_safe(uuid), rpc_emergency_team_status(uuid, varchar), rpc_emergency_hr_review(uuid, text),
  rpc_distress_press(text), rpc_distress_cancel(uuid), rpc_distress_dispatch_job(),
  rpc_distress_safety_inbox(), rpc_distress_close(uuid, distress_close_reason_enum),
  fn_group_wellbeing(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_subtree_summary(uuid), rpc_direct_reports_pseudonyms(), rpc_company_averages(),
  rpc_get_board_macro_metrics(numeric), rpc_provision_governance_user(uuid, varchar, varchar, text, text, boolean, varchar),
  rpc_manager_vault_open(boolean, boolean, int), rpc_manager_vault_put(uuid, bytea),
  rpc_manager_vault_entries(), rpc_manager_vault_close(),
  rpc_chro_named_view(uuid, text), rpc_board_macro_trends(text, uuid),
  rpc_emergency_declare(emergency_type_enum), rpc_emergency_end(uuid), rpc_emergency_roster(uuid),
  rpc_emergency_report_safe(uuid), rpc_emergency_team_status(uuid, varchar), rpc_emergency_hr_review(uuid, text),
  rpc_distress_press(text), rpc_distress_cancel(uuid), rpc_distress_safety_inbox(),
  rpc_distress_close(uuid, distress_close_reason_enum) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_distress_dispatch_job() TO service_role;

-- =============================================================================
-- v1.6.3 (2026-10-20) — Cuckoo window, project workload module, soft WIP alert,
-- v2 integration stub, distress push + SMS delivery, emergency misuse sequence (Q5).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Cuckoo: rolling 30-day reporter window (locked by Karin 20.10).
-- ---------------------------------------------------------------------------

-- The locked Cuckoo reporter window.
CREATE OR REPLACE FUNCTION fn_cuckoo_window()
RETURNS interval
LANGUAGE sql
IMMUTABLE
AS $$ SELECT interval '30 days' $$;

-- Distinct team members who reported (spoons or questionnaire) inside the rolling window.
CREATE OR REPLACE FUNCTION fn_cuckoo_recent_reporters(p_org_id uuid, p_department varchar)
RETURNS int
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT fn_team_activity_contributors(p_org_id, p_department, clock_timestamp() - fn_cuckoo_window())
$$;

REVOKE ALL ON FUNCTION fn_cuckoo_recent_reporters(uuid, varchar) FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- Workload formulas (locked infographic numbers; pure functions, no data access).
-- ---------------------------------------------------------------------------

-- Context-switch loss L(P) from the locked table. P>5 counts as 5 (Karin, Q3) → 0.75; P<1 → NULL.
CREATE OR REPLACE FUNCTION fn_context_switch_loss(p_parallel int)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$ SELECT c.loss_fraction FROM context_switch_loss_config c WHERE c.parallel_projects = LEAST(p_parallel, 5) $$;

-- EPWI_time = Σ(T_standard × D) / W_effective. NULL when capacity is unknown / zero.
CREATE OR REPLACE FUNCTION fn_epwi_time(p_demand_hours numeric, p_effective_hours numeric)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$ SELECT CASE WHEN p_effective_hours > 0 THEN p_demand_hours / p_effective_hours END $$;

-- EPWI_cognitive = EPWI_time / (1 − L(P)).
CREATE OR REPLACE FUNCTION fn_epwi_cognitive(p_epwi_time numeric, p_parallel int)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$ SELECT p_epwi_time / (1 - fn_context_switch_loss(p_parallel)) $$;

-- Reject a Likert answer that is not an integer 1–5 (400 workload_invalid_answers). NULL passes.
CREATE OR REPLACE FUNCTION fn_assert_likert_1to5(p_x numeric)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_x IS NOT NULL AND (p_x <> trunc(p_x) OR p_x < 1 OR p_x > 5) THEN
    PERFORM fn_raise_bad_request('workload_invalid_answers');
  END IF;
END;
$$;

-- Reject negative overtime hours (400 workload_invalid_answers). NULL passes.
CREATE OR REPLACE FUNCTION fn_assert_overtime_hours(p_hours numeric)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_hours IS NOT NULL AND p_hours < 0 THEN
    PERFORM fn_raise_bad_request('workload_invalid_answers');
  END IF;
END;
$$;

-- Likert 1–5 → 0–1: (x − 1) / 4 (Karin 20.10). Used for S (stress) and D (productivity drop).
CREATE OR REPLACE FUNCTION fn_likert_unit(p_x numeric)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$ SELECT (p_x - 1) / 4 $$;

-- O = min(weekly overtime hours / 10, 1), clamped at 0 (Karin's 10-hour cap, 20.10).
CREATE OR REPLACE FUNCTION fn_overtime_unit(p_hours numeric)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$ SELECT GREATEST(LEAST(p_hours / 10, 1), 0) $$;

-- B_t = 0.41·S + 0.37·O + 0.22·D (Karin 20.10; linear, all weights positive).
-- Validates inputs first; any missing input → NULL (never a partial score).
CREATE OR REPLACE FUNCTION fn_b_t(p_stress_1to5 numeric, p_overtime_hours numeric, p_productivity_drop_1to5 numeric)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  PERFORM fn_assert_likert_1to5(p_stress_1to5);
  PERFORM fn_assert_likert_1to5(p_productivity_drop_1to5);
  PERFORM fn_assert_overtime_hours(p_overtime_hours);
  IF p_stress_1to5 IS NULL OR p_overtime_hours IS NULL OR p_productivity_drop_1to5 IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN 0.41 * fn_likert_unit(p_stress_1to5)
       + 0.37 * fn_overtime_unit(p_overtime_hours)
       + 0.22 * fn_likert_unit(p_productivity_drop_1to5);
END;
$$;

-- AIDB = (1 − σ_w / μ_w) × 100 %.
CREATE OR REPLACE FUNCTION fn_aidb(p_sigma numeric, p_mu numeric)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$ SELECT CASE WHEN p_mu > 0 THEN (1 - p_sigma / p_mu) * 100 END $$;

-- AIDB of a list of per-member loads. σ = population SD (confirmed by Chief of Drive 24.10, O-31).
CREATE OR REPLACE FUNCTION fn_aidb_of(p_loads numeric[])
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$ SELECT fn_aidb(stddev_pop(x), avg(x)) FROM unnest(p_loads) x $$;

-- TRR = N_reassigned / N_total × 100 %.
CREATE OR REPLACE FUNCTION fn_trr(p_reassigned numeric, p_total numeric)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$ SELECT CASE WHEN p_total > 0 THEN p_reassigned / p_total * 100 END $$;

-- M_SPOF = 1 + K_critical_single / K_total.
CREATE OR REPLACE FUNCTION fn_m_spof(p_critical_single numeric, p_total numeric)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$ SELECT CASE WHEN p_total > 0 THEN 1 + p_critical_single / p_total END $$;

-- EPWI_time band: target 0.75–0.90; overload > 1.00 (locked). Other labels descriptive only.
CREATE OR REPLACE FUNCTION fn_epwi_time_band(p_x numeric)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$ SELECT CASE WHEN p_x IS NULL THEN NULL WHEN p_x > 1.00 THEN 'overload'
                  WHEN p_x > 0.90 THEN 'above_target' WHEN p_x >= 0.75 THEN 'target'
                  ELSE 'below_target' END $$;

-- EPWI_cognitive band (confirmed by Chief of Drive 24.10, O-30): ≤ 1.10 target; > 1.10 and ≤ 1.50 above_target; > 1.50 overload (danger).
CREATE OR REPLACE FUNCTION fn_epwi_cognitive_band(p_x numeric)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$ SELECT CASE WHEN p_x IS NULL THEN NULL WHEN p_x > 1.50 THEN 'overload'
                  WHEN p_x > 1.10 THEN 'above_target' ELSE 'target' END $$;

-- B_t band: low < 0.35; medium 0.35 ≤ B < 0.65; high ≥ 0.65 (infographic bands, locked).
CREATE OR REPLACE FUNCTION fn_b_t_band(p_x numeric)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$ SELECT CASE WHEN p_x IS NULL THEN NULL WHEN p_x >= 0.65 THEN 'high'
                  WHEN p_x < 0.35 THEN 'low' ELSE 'medium' END $$;

-- AIDB band: target > 80 %; < 65 % = selective burnout risk (locked); between = below_target.
CREATE OR REPLACE FUNCTION fn_aidb_band(p_x numeric)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$ SELECT CASE WHEN p_x IS NULL THEN NULL WHEN p_x > 80 THEN 'target'
                  WHEN p_x < 65 THEN 'selective_burnout_risk' ELSE 'below_target' END $$;

-- TRR band: > 18 % = planning failure (locked).
CREATE OR REPLACE FUNCTION fn_trr_band(p_x numeric)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$ SELECT CASE WHEN p_x IS NULL THEN NULL WHEN p_x > 18 THEN 'planning_failure' ELSE 'ok' END $$;

-- Week key (v1.6.5): first day of the COMPANY week that contains the employee-local date of p_at.
-- v1.6.7: resolved against the week-start history in force on that date (fn_company_week_start).
CREATE OR REPLACE FUNCTION fn_local_week_start(p_user_id uuid, p_at timestamptz DEFAULT clock_timestamp())
RETURNS date
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT fn_company_week_start(u.company_id, (p_at AT TIME ZONE u.timezone)::date)
    FROM users u WHERE u.user_id = p_user_id
$$;

-- ---------------------------------------------------------------------------
-- Self-report (v1 only data source).
-- ---------------------------------------------------------------------------

-- Validate the self-report answers (400 workload_invalid_answers). Stress / drop: integer 1–5 or NULL.
CREATE OR REPLACE FUNCTION fn_workload_validate(p_contract numeric, p_worked numeric, p_overtime numeric,
                                                p_parallel int, p_stress numeric, p_drop numeric)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_contract IS NULL OR p_worked IS NULL OR p_overtime IS NULL OR p_parallel IS NULL
     OR p_contract <= 0 OR p_contract > 168 OR p_worked < 0 OR p_worked > 168
     OR p_overtime > p_worked OR p_parallel < 0 THEN
    PERFORM fn_raise_bad_request('workload_invalid_answers');
  END IF;
  PERFORM fn_assert_overtime_hours(p_overtime);
  PERFORM fn_assert_likert_1to5(p_stress);
  PERFORM fn_assert_likert_1to5(p_drop);
END;
$$;

-- Employee-local calendar date of a timestamp.
CREATE OR REPLACE FUNCTION fn_user_local_day(p_user_id uuid, p_at timestamptz DEFAULT clock_timestamp())
RETURNS date
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$ SELECT (p_at AT TIME ZONE u.timezone)::date FROM users u WHERE u.user_id = p_user_id $$;

-- O-40 (Chief of Drive 20.10): a work date is accepted from 14 days back to 1 day ahead of the
-- employee's local today (her own timezone, O-42). Outside → 422 work_date_out_of_range.
CREATE OR REPLACE FUNCTION fn_assert_work_date_in_range(p_work_date date, p_today date)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_work_date IS NULL OR p_today IS NULL OR p_work_date > p_today + 1 OR p_work_date < p_today - 14 THEN
    RAISE EXCEPTION 'work_date_out_of_range'
      USING ERRCODE = 'PT422', DETAIL = 'http_hint=422;code=work_date_out_of_range', HINT = 'work_date_out_of_range';
  END IF;
END;
$$;

-- Employee submits her WEEKLY self-report (Q6: once per company week, keyed by week_start_date;
-- a duplicate is rejected with 409, never updated in place; WORM). Separate from spoons.
-- p_work_date = start date of the work / shift reported (a night shift counts toward the day it
-- started); it decides the week. Omitted → her local date today. Range: today − 14 … today + 1 (O-40).
CREATE OR REPLACE FUNCTION rpc_submit_workload_self_report(
    p_contract_hours numeric, p_hours_worked numeric, p_overtime_hours numeric,
    p_parallel_projects int, p_stress_1to5 numeric DEFAULT NULL, p_productivity_drop_1to5 numeric DEFAULT NULL,
    p_work_date date DEFAULT NULL)
RETURNS TABLE (report_id uuid, week_start_date date)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_week  date;
  v_id    uuid;
  v_today date;
BEGIN
  IF auth.uid() IS NULL OR NOT fn_has_employee_profile(auth.uid()) THEN
    PERFORM fn_raise_business('anti_get_blocked');
  END IF;
  v_today := fn_user_local_day(auth.uid());
  PERFORM fn_assert_work_date_in_range(COALESCE(p_work_date, v_today), v_today);
  PERFORM fn_workload_validate(p_contract_hours, p_hours_worked, p_overtime_hours, p_parallel_projects,
                               p_stress_1to5, p_productivity_drop_1to5);
  BEGIN
    INSERT INTO workload_self_report (user_id, company_id, work_date, contract_hours, hours_worked,
                                      overtime_hours, parallel_projects, stress_1to5, productivity_drop_1to5)
    VALUES (auth.uid(), fn_my_company(), COALESCE(p_work_date, v_today), p_contract_hours,
            p_hours_worked, p_overtime_hours, p_parallel_projects, p_stress_1to5::smallint, p_productivity_drop_1to5::smallint)
    RETURNING workload_self_report.report_id, workload_self_report.week_start_date INTO v_id, v_week;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'workload_report_already_submitted'
      USING ERRCODE = '23505', DETAIL = 'http_hint=409;code=workload_report_already_submitted',
            HINT = 'workload_report_already_submitted';
  END;
  PERFORM fn_sync_employee_deprived(auth.uid(), v_week);
  RETURN QUERY SELECT v_id, v_week;
END;
$$;

-- Core project assignments of one employee (WIP count; assignment data, not wellbeing).
CREATE OR REPLACE FUNCTION fn_core_assignment_count(p_user_id uuid)
RETURNS int
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT count(*)::int FROM project_member m JOIN project p ON p.project_id = m.project_id
   WHERE m.user_id = p_user_id AND p.is_core
$$;

-- Lock 1: personal indices for the CALLER only (no user parameter exists).
-- Proxies: Σ(T_standard×D) ≈ hours_worked; W_effective ≈ contract_hours; P = parallel_projects.
-- B_t (v1.6.4): 0.41·S + 0.37·O + 0.22·D from THAT week's report; NULL if stress / drop missing.
-- Employee-only; not part of any PM / manager / CHRO aggregate.
CREATE OR REPLACE FUNCTION rpc_my_workload_indices(p_week_start_date date DEFAULT NULL)
RETURNS TABLE (week_start_date date, epwi_time numeric, epwi_time_band text, epwi_cognitive numeric,
               epwi_cognitive_band text, b_t numeric, b_t_band text, core_assignment_count int)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_r   workload_self_report;
  v_t   numeric;
  v_c   numeric;
  v_b   numeric;
BEGIN
  IF auth.uid() IS NULL OR NOT fn_has_employee_profile(auth.uid()) THEN
    PERFORM fn_raise_business('anti_get_blocked');
  END IF;
  SELECT * INTO v_r FROM workload_self_report w
   WHERE w.user_id = auth.uid() AND w.week_start_date = COALESCE(p_week_start_date, fn_local_week_start(auth.uid()));
  IF NOT FOUND THEN
    RETURN;
  END IF;
  v_t := fn_epwi_time(v_r.hours_worked, v_r.contract_hours);
  v_c := fn_epwi_cognitive(v_t, v_r.parallel_projects);
  v_b := fn_b_t(v_r.stress_1to5, v_r.overtime_hours, v_r.productivity_drop_1to5);
  RETURN QUERY SELECT v_r.week_start_date, v_t, fn_epwi_time_band(v_t), v_c, fn_epwi_cognitive_band(v_c),
                      v_b, fn_b_t_band(v_b), fn_core_assignment_count(auth.uid());
END;
$$;

-- The caller is the project manager of this project (role + ownership).
CREATE OR REPLACE FUNCTION fn_is_pm_of(p_project_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT fn_viewer_has_role('project_manager')
     AND EXISTS (SELECT 1 FROM project p WHERE p.project_id = p_project_id AND p.project_manager_id = auth.uid())
$$;

REVOKE ALL ON FUNCTION fn_is_pm_of(uuid) FROM PUBLIC;

-- v1.6.7 (Karin 20.10): PEWI = mean EPWI of the project's members who reported in the company week
-- (EPWI_time — the base EPWI; Karin to confirm vs EPWI_cognitive). Only the mean and the count.
CREATE OR REPLACE FUNCTION fn_project_pewi_of(p_project_id uuid, p_week_start_date date)
RETURNS TABLE (reporter_count int, pewi numeric)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT count(DISTINCT w.user_id)::int, avg(fn_epwi_time(w.hours_worked, w.contract_hours))
    FROM project_member m JOIN workload_self_report w ON w.user_id = m.user_id
   WHERE m.project_id = p_project_id AND w.week_start_date = p_week_start_date
$$;

-- PM view of PEWI alone (Karin 20.10): below N_project (5) actual reporters → pewi NULL and
-- suppressed = true (no 403 here, unlike rpc_project_workload). Every view is audited.
CREATE OR REPLACE FUNCTION rpc_project_pewi(p_project_id uuid, p_week_start_date date DEFAULT NULL)
RETURNS TABLE (week_start_date date, pewi numeric, suppressed boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_week date := COALESCE(p_week_start_date, fn_local_week_start(auth.uid()));
  v_r    record;
  v_ok   boolean;
BEGIN
  IF auth.uid() IS NULL OR NOT fn_is_pm_of(p_project_id) THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  SELECT * INTO v_r FROM fn_project_pewi_of(p_project_id, v_week);
  v_ok := v_r.reporter_count >= fn_privacy_min_n('project');
  PERFORM fn_audit_view('project_pewi_view', jsonb_build_object('project_id', p_project_id,
                        'week_start_date', v_week, 'suppressed', NOT v_ok));
  RETURN QUERY SELECT v_week, CASE WHEN v_ok THEN v_r.pewi END, NOT v_ok;
END;
$$;

-- Lock 1: project-level aggregates for the PM at N≥5 actual respondents; audited.
-- PEWI (v1.6.7): mean EPWI_time of the reporting members (fn_project_pewi_of).
-- AIDB: per-respondent hours_worked as the load proxy (v2: action items per member).
-- TRR: needs task reassignment data → NULL until v2. M_SPOF / spof_alert: v2 items only, no employee id.
CREATE OR REPLACE FUNCTION rpc_project_workload(p_project_id uuid, p_week_start_date date DEFAULT NULL)
RETURNS TABLE (week_start_date date, respondent_count int, pewi numeric, aidb numeric, aidb_band text,
               trr numeric, trr_band text, m_spof numeric, spof_alert boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_week  date := COALESCE(p_week_start_date, fn_local_week_start(auth.uid()));
  v_loads numeric[];
  v_aidb  numeric;
  v_ks    int;
  v_kt    int;
BEGIN
  IF auth.uid() IS NULL OR NOT fn_is_pm_of(p_project_id) THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  SELECT array_agg(w.hours_worked) INTO v_loads
    FROM project_member m JOIN workload_self_report w ON w.user_id = m.user_id
   WHERE m.project_id = p_project_id AND w.week_start_date = v_week;
  PERFORM fn_assert_privacy_threshold(COALESCE(cardinality(v_loads), 0), 'project');
  v_aidb := fn_aidb_of(v_loads);
  SELECT count(*) FILTER (WHERE i.is_critical AND i.single_holder)::int, count(*)::int
    INTO v_ks, v_kt FROM project_spof_item i WHERE i.project_id = p_project_id;
  PERFORM fn_audit_view('project_workload_view', jsonb_build_object('project_id', p_project_id, 'week_start_date', v_week));
  RETURN QUERY SELECT v_week, cardinality(v_loads), (SELECT f.pewi FROM fn_project_pewi_of(p_project_id, v_week) f),
                      v_aidb, fn_aidb_band(v_aidb),
                      NULL::numeric, NULL::text, fn_m_spof(v_ks, v_kt),
                      CASE WHEN v_kt > 0 THEN v_ks > 0 END;
END;
$$;

-- ---------------------------------------------------------------------------
-- Soft WIP limit (lock 3): >2 core projects → alert to her and the PM; never blocks.
-- ---------------------------------------------------------------------------

-- Write the WIP alerts for one employee (count only; PM rows carry no employee id).
CREATE OR REPLACE FUNCTION fn_wip_raise_alerts(p_user_id uuid, p_project_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_n int := fn_core_assignment_count(p_user_id);
BEGIN
  IF v_n <= 2 THEN
    RETURN;
  END IF;
  INSERT INTO wip_alert (recipient_id, audience, project_id, core_assignment_count)
  VALUES (p_user_id, 'employee', p_project_id, v_n);
  INSERT INTO wip_alert (recipient_id, audience, project_id, core_assignment_count)
  SELECT p.project_manager_id, 'project_manager', p.project_id, v_n
    FROM project p WHERE p.project_id = p_project_id AND p.project_manager_id IS NOT NULL;
END;
$$;

REVOKE ALL ON FUNCTION fn_wip_raise_alerts(uuid, uuid) FROM PUBLIC;

-- Is this project marked core by its PM (v1.6.4, Q4)?
CREATE OR REPLACE FUNCTION fn_project_is_core(p_project_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$ SELECT COALESCE((SELECT p.is_core FROM project p WHERE p.project_id = p_project_id), false) $$;

-- Trigger body: after a member joins a CORE project, check the soft limit (no blocking).
CREATE OR REPLACE FUNCTION fn_project_member_wip()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF fn_project_is_core(NEW.project_id) THEN
    PERFORM fn_wip_raise_alerts(NEW.user_id, NEW.project_id);
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_project_member_wip ON project_member;
CREATE TRIGGER trg_project_member_wip
    AFTER INSERT ON project_member
    FOR EACH ROW EXECUTE FUNCTION fn_project_member_wip();

-- Trigger body: a project switched to core → re-check the soft limit for each member.
CREATE OR REPLACE FUNCTION fn_project_core_wip()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NEW.is_core AND NOT OLD.is_core THEN
    PERFORM fn_wip_raise_alerts(m.user_id, NEW.project_id) FROM project_member m WHERE m.project_id = NEW.project_id;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_project_core_wip ON project;
CREATE TRIGGER trg_project_core_wip
    AFTER UPDATE OF is_core ON project
    FOR EACH ROW EXECUTE FUNCTION fn_project_core_wip();

-- Reject a missing core choice (400 project_is_core_required): the PM must choose explicitly.
CREATE OR REPLACE FUNCTION fn_assert_is_core_given(p_is_core boolean)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_is_core IS NULL THEN
    PERFORM fn_raise_bad_request('project_is_core_required');
  END IF;
END;
$$;

-- PM creates a project in her company and becomes its PM; is_core is REQUIRED (Q4).
CREATE OR REPLACE FUNCTION rpc_project_create(p_name text, p_is_core boolean)
RETURNS project
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_row project;
BEGIN
  IF auth.uid() IS NULL OR NOT fn_viewer_has_role('project_manager') OR fn_my_company() IS NULL THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  PERFORM fn_assert_is_core_given(p_is_core);
  IF p_name IS NULL OR length(btrim(p_name)) = 0 THEN
    PERFORM fn_raise_bad_request('project_name_required');
  END IF;
  INSERT INTO project (company_id, name, project_manager_id, is_core)
  VALUES (fn_my_company(), btrim(p_name), auth.uid(), p_is_core) RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

-- Only the PM of the project changes its core toggle (Q4). Switching to core re-checks WIP.
CREATE OR REPLACE FUNCTION rpc_project_set_core(p_project_id uuid, p_is_core boolean)
RETURNS project
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_row project;
BEGIN
  IF auth.uid() IS NULL OR NOT fn_is_pm_of(p_project_id) THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  PERFORM fn_assert_is_core_given(p_is_core);
  UPDATE project SET is_core = p_is_core WHERE project_id = p_project_id RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

-- PM assigns a member of her company to her project. Returns the core count; never blocks.
CREATE OR REPLACE FUNCTION rpc_project_assign_member(p_project_id uuid, p_user_id uuid)
RETURNS TABLE (core_assignment_count int)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT fn_is_pm_of(p_project_id)
     OR NOT EXISTS (SELECT 1 FROM users u WHERE u.user_id = p_user_id AND u.company_id = fn_my_company()
                     AND u.has_employee_profile AND u.employment_ended_at IS NULL) THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  INSERT INTO project_member (project_id, user_id) VALUES (p_project_id, p_user_id)
  ON CONFLICT (project_id, user_id) DO NOTHING;
  RETURN QUERY SELECT fn_core_assignment_count(p_user_id);
END;
$$;

-- ---------------------------------------------------------------------------
-- v2 integration adapter stub (Jira / Asana / Monday). Does nothing in v1.
-- TODO להשלמה (v2): map tasks → T_standard, D, N_reassigned, N_total, K_critical_single, K_total.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_workload_integration_sync(p_provider text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF p_provider IS NULL OR p_provider NOT IN ('jira', 'asana', 'monday') THEN
    PERFORM fn_raise_bad_request('invalid_provider');
  END IF;
  RETURN 'not_implemented_v2';   -- no reads, no writes
END;
$$;

-- ---------------------------------------------------------------------------
-- Distress delivery: push AND sms together, immediately at dispatch (lock 20.10, option a).
-- ---------------------------------------------------------------------------

-- Queue both channels for every safety manager of the event's company, one timestamp.
CREATE OR REPLACE FUNCTION fn_distress_queue_deliveries(p_ev distress_event)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_now timestamptz := clock_timestamp();
  v_n   int;
BEGIN
  INSERT INTO distress_alert_delivery (event_id, recipient_id, channel, queued_at)
  SELECT p_ev.event_id, u.user_id, c.channel, v_now
    FROM users u CROSS JOIN (VALUES ('push'), ('sms')) AS c(channel)
   WHERE u.company_id = p_ev.company_id AND u.org_role_code = 'safety_emergency_manager'
     AND u.employment_ended_at IS NULL;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;

-- In-app push sender stub (the app reads the notification row). TODO להשלמה: push provider.
CREATE OR REPLACE FUNCTION fn_push_send(p_delivery_id uuid)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$ SELECT 'PROVIDER_NOT_CONFIGURED'::text $$;

-- SMS provider stub (v1 adapter). TODO להשלמה: SMS provider + phone delivery.
CREATE OR REPLACE FUNCTION fn_sms_provider_send(p_delivery_id uuid)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$ SELECT 'PROVIDER_NOT_CONFIGURED'::text $$;

-- System job: attempt every queued delivery; each channel is attempted on its own.
CREATE OR REPLACE FUNCTION rpc_distress_delivery_job()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_d distress_alert_delivery;
  v_n int := 0;
BEGIN
  FOR v_d IN SELECT * FROM distress_alert_delivery WHERE status = 'QUEUED' FOR UPDATE SKIP LOCKED LOOP
    UPDATE distress_alert_delivery
       SET status = CASE v_d.channel WHEN 'push' THEN fn_push_send(v_d.delivery_id)
                                     ELSE fn_sms_provider_send(v_d.delivery_id) END,
           attempted_at = clock_timestamp()
     WHERE delivery_id = v_d.delivery_id;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;

-- ---------------------------------------------------------------------------
-- Emergency misuse (Q5, locked 13.10): applies to the declarer.
-- Sequence: close → notify → talk. After a second MISUSE she may not open alone.
-- Co-signer (Q7 / O-35, locked 20.10): the CHRO (app_role vp_hr) only.
-- ---------------------------------------------------------------------------

-- Number of MISUSE findings against a declarer.
CREATE OR REPLACE FUNCTION fn_emergency_misuse_count(p_user_id uuid)
RETURNS int
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$ SELECT count(*)::int FROM emergency_event e WHERE e.declared_by = p_user_id AND e.hr_review_status = 'MISUSE' $$;

-- May this declarer still open an emergency alone (fewer than 2 MISUSE findings)?
CREATE OR REPLACE FUNCTION fn_emergency_may_open_alone(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$ SELECT fn_emergency_misuse_count(p_user_id) < 2 $$;

-- Notify the company CHRO about an emergency event.
CREATE OR REPLACE FUNCTION fn_emergency_notify_chro(p_ev emergency_event, p_kind text)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  INSERT INTO notification (recipient_id, kind, ref_id)
  SELECT u.user_id, p_kind, p_ev.event_id FROM users u
   WHERE u.company_id = p_ev.company_id AND u.app_role = 'vp_hr' AND u.employment_ended_at IS NULL
$$;

-- Ask the co-signer (the CHRO only — Karin, Q7) to confirm a restricted declaration.
CREATE OR REPLACE FUNCTION fn_emergency_request_cosign(p_ev emergency_event)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  INSERT INTO notification (recipient_id, kind, ref_id)
  SELECT u.user_id, 'emergency_cosign_request', p_ev.event_id FROM users u
   WHERE u.company_id = p_ev.company_id AND u.employment_ended_at IS NULL AND u.user_id <> p_ev.declared_by
     AND u.app_role = 'vp_hr'
$$;

-- Notify step of the misuse sequence: tell the declarer, audit immutably.
CREATE OR REPLACE FUNCTION fn_emergency_apply_misuse(p_ev emergency_event)
RETURNS emergency_event
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_row emergency_event;
BEGIN
  UPDATE emergency_event SET misuse_notified_at = clock_timestamp()
   WHERE event_id = p_ev.event_id RETURNING * INTO v_row;
  INSERT INTO notification (recipient_id, kind, ref_id) VALUES (v_row.declared_by, 'emergency_misuse_notice', v_row.event_id);
  PERFORM fn_audit_view('emergency_misuse', jsonb_build_object('event_id', v_row.event_id, 'declared_by', v_row.declared_by,
                        'misuse_count', fn_emergency_misuse_count(v_row.declared_by)));
  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION fn_emergency_misuse_count(uuid), fn_emergency_may_open_alone(uuid),
  fn_emergency_notify_chro(emergency_event, text), fn_emergency_request_cosign(emergency_event),
  fn_emergency_apply_misuse(emergency_event) FROM PUBLIC;

-- The CHRO (only — Karin, Q7) co-approves a restricted declaration → ACTIVE. Never closes it.
CREATE OR REPLACE FUNCTION rpc_emergency_cosign(p_event_id uuid)
RETURNS emergency_event
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_row emergency_event;
BEGIN
  SELECT * INTO v_row FROM emergency_event e WHERE e.event_id = p_event_id;
  IF auth.uid() IS NULL OR NOT FOUND OR v_row.company_id <> fn_my_company() OR v_row.declared_by = auth.uid()
     OR NOT fn_is_chro() THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  IF v_row.status <> 'PENDING_COSIGN' THEN
    PERFORM fn_raise_business('emergency_not_pending_cosign');
  END IF;
  UPDATE emergency_event SET status = 'ACTIVE', cosigned_by = auth.uid(), cosigned_at = clock_timestamp()
   WHERE event_id = p_event_id RETURNING * INTO v_row;
  PERFORM fn_emergency_notify_chro(v_row, 'emergency_declared');
  PERFORM fn_audit_view('emergency_cosign', jsonb_build_object('event_id', p_event_id));
  RETURN v_row;
END;
$$;

-- v1.6.4: rpc_emergency_misuse_close REMOVED (Karin, Q7: closing stays with the safety manager
-- alone; the CHRO never closes). Q5 sequence = safety manager ends (rpc_emergency_end) →
-- CHRO review MISUSE notifies the declarer (rpc_emergency_hr_review) → talk (below).

-- Talk step: the CHRO records the conversation with the declarer (only after the notice).
CREATE OR REPLACE FUNCTION rpc_emergency_misuse_talk(p_event_id uuid)
RETURNS emergency_event
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_row emergency_event;
BEGIN
  SELECT * INTO v_row FROM emergency_event e WHERE e.event_id = p_event_id;
  IF auth.uid() IS NULL OR NOT FOUND OR NOT fn_is_chro() OR v_row.company_id <> fn_my_company() THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  IF v_row.hr_review_status IS DISTINCT FROM 'MISUSE' OR v_row.misuse_notified_at IS NULL OR v_row.misuse_talk_at IS NOT NULL THEN
    PERFORM fn_raise_business('emergency_misuse_sequence');
  END IF;
  UPDATE emergency_event SET misuse_talk_at = clock_timestamp(), misuse_talk_by = auth.uid()
   WHERE event_id = p_event_id RETURNING * INTO v_row;
  PERFORM fn_audit_view('emergency_misuse_talk', jsonb_build_object('event_id', p_event_id, 'declared_by', v_row.declared_by));
  RETURN v_row;
END;
$$;

-- Grants (v1.6.3)
REVOKE ALL ON FUNCTION rpc_submit_workload_self_report(numeric, numeric, numeric, int, numeric, numeric, date),
  rpc_my_workload_indices(date), rpc_project_workload(uuid, date), rpc_project_assign_member(uuid, uuid),
  rpc_workload_integration_sync(text), rpc_distress_delivery_job(), rpc_emergency_cosign(uuid),
  rpc_emergency_misuse_talk(uuid), fn_core_assignment_count(uuid),
  rpc_project_create(text, boolean), rpc_project_set_core(uuid, boolean), fn_project_is_core(uuid),
  fn_project_core_wip(),
  fn_local_week_start(uuid, timestamptz), fn_distress_queue_deliveries(distress_event),
  fn_project_member_wip(), fn_context_switch_loss(int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_submit_workload_self_report(numeric, numeric, numeric, int, numeric, numeric, date),
  rpc_my_workload_indices(date), rpc_project_workload(uuid, date), rpc_project_assign_member(uuid, uuid),
  rpc_emergency_cosign(uuid), rpc_emergency_misuse_talk(uuid),
  rpc_project_create(text, boolean), rpc_project_set_core(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_workload_integration_sync(text), rpc_distress_delivery_job() TO service_role;

-- ---------------------------------------------------------------------------
-- v1.6.5 — company calendar settings (Karin 20.10).
-- O-36 (locked 20.10): restricted to the CHRO (app_role vp_hr),
-- the only existing company-level settings role. Employees of the company may read them.
-- ---------------------------------------------------------------------------

-- Reject a day-of-week outside 0–6 (400 invalid_company_setting). NULL = leave unchanged.
CREATE OR REPLACE FUNCTION fn_assert_dow(p_dow int)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_dow IS NOT NULL AND (p_dow < 0 OR p_dow > 6) THEN
    PERFORM fn_raise_bad_request('invalid_company_setting');
  END IF;
END;
$$;

-- The caller's company calendar settings (read-only for any member of the company).
-- v1.6.7: week_start_dow = the latest setting; week_start_effective_from = when it takes effect
-- (NULL = initial setting); week_start_dow_in_force = the start day of the current company week;
-- timezone_status ('needs_review' → UI warning to confirm), reminders_on_hold, country.
CREATE OR REPLACE FUNCTION rpc_company_settings()
RETURNS TABLE (week_start_dow smallint, week_start_effective_from date, week_start_dow_in_force smallint,
               last_workday_dow smallint, timezone text, timezone_status text, reminder_time time,
               reminders_on_hold boolean, country text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF auth.uid() IS NULL OR fn_my_company() IS NULL THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  RETURN QUERY
  SELECT c.week_start_dow,
         (SELECT NULLIF(max(h.effective_from), '-infinity'::date) FROM company_week_start_history h WHERE h.company_id = c.company_id),
         (SELECT r.week_start_dow FROM fn_company_week_rule_at(c.company_id, fn_company_local_today(c.company_id)) r),
         c.last_workday_dow, c.timezone, c.timezone_status, c.reminder_time, c.reminders_on_hold, c.country
    FROM companies c WHERE c.company_id = fn_my_company();
END;
$$;

-- CHRO changes her company's calendar settings; NULL arguments leave a value unchanged.
-- O-36 (Karin 20.10, RESOLVED): only the CHRO (app_role vp_hr); no system-admin role.
-- A week-start change is never blocked: it is scheduled for the next week boundary (O-41).
-- An explicit timezone counts as the CHRO's confirmation (timezone_status → confirmed).
-- Setting the country of a held company releases its reminders (trigger, O-43).
CREATE OR REPLACE FUNCTION rpc_company_settings_update(
    p_week_start_dow int DEFAULT NULL, p_last_workday_dow int DEFAULT NULL,
    p_timezone text DEFAULT NULL, p_reminder_time time DEFAULT NULL, p_country text DEFAULT NULL)
RETURNS TABLE (week_start_dow smallint, week_start_effective_from date, week_start_dow_in_force smallint,
               last_workday_dow smallint, timezone text, timezone_status text, reminder_time time,
               reminders_on_hold boolean, country text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT fn_is_chro() OR fn_my_company() IS NULL THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  PERFORM fn_assert_dow(p_week_start_dow);
  PERFORM fn_assert_dow(p_last_workday_dow);
  UPDATE companies c
     SET country          = COALESCE(upper(p_country), c.country),
         week_start_dow   = COALESCE(p_week_start_dow::smallint, c.week_start_dow),
         last_workday_dow = COALESCE(p_last_workday_dow::smallint, c.last_workday_dow),
         timezone         = COALESCE(p_timezone, c.timezone),
         timezone_status  = CASE WHEN p_timezone IS NOT NULL THEN 'confirmed' ELSE c.timezone_status END,
         reminder_time    = COALESCE(p_reminder_time, c.reminder_time)
   WHERE c.company_id = fn_my_company();
  PERFORM fn_audit_view('company_settings_update', jsonb_strip_nulls(jsonb_build_object(
    'company_id', fn_my_company(), 'week_start_dow', p_week_start_dow, 'last_workday_dow', p_last_workday_dow,
    'timezone', p_timezone, 'reminder_time', p_reminder_time, 'country', p_country)));
  RETURN QUERY SELECT * FROM rpc_company_settings();
END;
$$;

-- O-43: the CHRO confirms the company timezone (optionally correcting it); clears needs_review. Audited.
CREATE OR REPLACE FUNCTION rpc_company_timezone_confirm(p_timezone text DEFAULT NULL)
RETURNS TABLE (timezone text, timezone_status text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_prev text;
BEGIN
  IF auth.uid() IS NULL OR NOT fn_is_chro() OR fn_my_company() IS NULL THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  SELECT c.timezone_status INTO v_prev FROM companies c WHERE c.company_id = fn_my_company();
  UPDATE companies c SET timezone = COALESCE(p_timezone, c.timezone), timezone_status = 'confirmed'
   WHERE c.company_id = fn_my_company();
  PERFORM fn_audit_view('company_timezone_confirmed', jsonb_build_object('company_id', fn_my_company(),
    'timezone', (SELECT c.timezone FROM companies c WHERE c.company_id = fn_my_company()), 'previous_status', v_prev));
  RETURN QUERY SELECT c.timezone, c.timezone_status FROM companies c WHERE c.company_id = fn_my_company();
END;
$$;

-- When the weekly reminder is due for a company week: the last workday within that 7-day week at
-- reminder_time, company-local. NULL while the company's reminders are on hold (no country, O-43),
-- when it has no timezone, or when p_week_start_date is not a week start — e.g. a bridge day
-- (v1.6.8: a bridge has no reminder).
CREATE OR REPLACE FUNCTION fn_company_reminder_at(p_company_id uuid, p_week_start_date date)
RETURNS timestamptz
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT CASE WHEN NOT c.reminders_on_hold THEN
           ((e.d - ((extract(dow FROM e.d)::int - c.last_workday_dow + 7) % 7)) + c.reminder_time) AT TIME ZONE c.timezone END
    FROM companies c, LATERAL (SELECT fn_company_week_end(c.company_id, p_week_start_date) AS d) e
   WHERE c.company_id = p_company_id
$$;

-- Reminder sender job (service_role). STUB — TODO להשלמה: push / in-app sender, idempotency.
CREATE OR REPLACE FUNCTION rpc_workload_reminder_job()
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$ SELECT 'reminder_sender_not_configured'::text $$;

REVOKE ALL ON FUNCTION fn_user_local_day(uuid, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_assert_work_date_in_range(date, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION rpc_company_settings(), rpc_company_settings_update(int, int, text, time, text),
  rpc_company_timezone_confirm(text), fn_company_reminder_at(uuid, date), rpc_workload_reminder_job(),
  fn_project_pewi_of(uuid, date), rpc_project_pewi(uuid, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_company_settings(), rpc_company_settings_update(int, int, text, time, text),
  rpc_company_timezone_confirm(text), rpc_project_pewi(uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_workload_reminder_job() TO service_role;

-- =============================================================================
-- v1.6.16 AGENTS (agents-bot-instructions-v3, Karin 30.10). Advisory only: no agent pays, changes a
-- budget or messages an employee. No agent output contains person_id, user_id, pseudonym or any
-- employee identifier (tests: tests/test_agents_v1_6_16.sql). Months, end-of-month forecasts and the
-- daily summary time use the company timezone (agent_settings.company_timezone → companies.timezone).
-- =============================================================================

-- ---------- shared helpers ----------

-- Raise HTTP 422 (SQLSTATE PT422) with the Error Contract DETAIL.
CREATE OR REPLACE FUNCTION fn_raise_unprocessable(p_code text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION '%', p_code
    USING ERRCODE = 'PT422', DETAIL = format('http_hint=422;code=%s', p_code), HINT = p_code;
END;
$$;

-- True when the call comes from a client role (PostgREST SET ROLE authenticated / anon).
CREATE OR REPLACE FUNCTION fn_is_client_call()
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(current_setting('role', true), 'none') IN ('authenticated', 'anon')
$$;

-- Caller is an active cfo or vp_hr of p_company (v3 §2.3: the only roles that see ILS / budget data).
CREATE OR REPLACE FUNCTION fn_is_finance_viewer(p_company uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (SELECT 1 FROM users u
                  WHERE u.user_id = auth.uid() AND u.company_id = p_company
                    AND u.employment_ended_at IS NULL AND u.app_role IN ('vp_hr', 'cfo'))
$$;

-- 403 insufficient_privilege unless a service call or an active cfo / vp_hr of the company.
CREATE OR REPLACE FUNCTION fn_assert_finance_viewer(p_company uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF fn_is_client_call() AND (p_company IS NULL OR NOT fn_is_finance_viewer(p_company)) THEN
    PERFORM fn_raise_business('insufficient_privilege');
  END IF;
END;
$$;

-- Company timezone for agents (v3 §1.7): the agent setting, else companies.timezone, else UTC.
CREATE OR REPLACE FUNCTION fn_agent_company_tz(p_company uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT COALESCE(fn_agent_setting_text(p_company, 'company_timezone'),
                  (SELECT c.timezone FROM companies c WHERE c.company_id = p_company), 'UTC')
$$;

-- Company-local wall-clock time of an instant.
CREATE OR REPLACE FUNCTION fn_agent_local_ts(p_company uuid, p_at timestamptz)
RETURNS timestamp
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT p_at AT TIME ZONE fn_agent_company_tz(p_company)
$$;

-- First day of the company-local month of an instant.
CREATE OR REPLACE FUNCTION fn_agent_month_start(p_company uuid, p_at timestamptz)
RETURNS date
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT date_trunc('month', fn_agent_local_ts(p_company, p_at))::date
$$;

-- Instant at which a company-local date starts.
CREATE OR REPLACE FUNCTION fn_agent_day_start(p_company uuid, p_day date)
RETURNS timestamptz
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT p_day::timestamp AT TIME ZONE fn_agent_company_tz(p_company)
$$;

-- First day of a month (normalises any date).
CREATE OR REPLACE FUNCTION fn_month_of(p_day date)
RETURNS date
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT date_trunc('month', p_day)::date
$$;

-- Month p_n months after (negative = before) p_month.
CREATE OR REPLACE FUNCTION fn_month_shift(p_month date, p_n int)
RETURNS date
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT (date_trunc('month', p_month) + make_interval(months => p_n))::date
$$;

-- Hebrew label of a setting value in effect ("לא הוגדר" when not defined).
CREATE OR REPLACE FUNCTION fn_setting_display_he(p_row agent_settings)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE WHEN p_row.value_status = 'not_defined' THEN 'לא הוגדר'
              WHEN p_row.value_kind = 'numeric' THEN trim_scale(p_row.value_numeric)::text
              ELSE p_row.value_text END
$$;

REVOKE ALL ON FUNCTION fn_is_finance_viewer(uuid), fn_assert_finance_viewer(uuid), fn_agent_company_tz(uuid),
                       fn_agent_local_ts(uuid, timestamptz), fn_agent_month_start(uuid, timestamptz),
                       fn_agent_day_start(uuid, date) FROM PUBLIC;

-- ---------- agent settings API (GET / PUT /agents/settings) ----------

-- All settings in effect for a company (cfo / vp_hr only). "לא הוגדר" is shown, never a made-up value.
CREATE OR REPLACE FUNCTION rpc_get_agent_settings(p_company_id uuid)
RETURNS TABLE (setting_key text, value_kind text, value_numeric numeric, value_text text, value_status text,
               display_he text, is_locked boolean, scope text, source_note text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  PERFORM fn_assert_finance_viewer(p_company_id);
  RETURN QUERY
  SELECT d.setting_key, e.value_kind, e.value_numeric, e.value_text, e.value_status,
         fn_setting_display_he(e), e.is_locked,
         CASE WHEN e.company_id IS NULL THEN 'default' ELSE 'company' END, e.source_note
    FROM agent_settings d
    CROSS JOIN LATERAL (SELECT (fn_agent_setting_row(p_company_id, d.setting_key)).*) e
   WHERE d.company_id IS NULL
   ORDER BY d.setting_key;
END;
$$;

-- Validate a new setting value against its kind (400 invalid_setting_value).
CREATE OR REPLACE FUNCTION fn_validate_agent_setting(p_kind text, p_num numeric, p_text text)
RETURNS void
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  IF p_num IS NULL AND p_text IS NULL THEN
    RETURN;                                   -- reset to the default row
  END IF;
  IF (p_kind = 'numeric' AND (p_num IS NULL OR p_text IS NOT NULL OR p_num < 0))
     OR (p_kind <> 'numeric' AND (p_text IS NULL OR p_num IS NOT NULL))
     OR (p_kind = 'timezone' AND NOT fn_is_valid_iana_timezone(p_text))
     OR (p_kind = 'method' AND p_text NOT IN ('fixed_cost', 'avg_redeemed'))
     OR (p_kind = 'time' AND p_text !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$') THEN
    PERFORM fn_raise_bad_request('invalid_setting_value');
  END IF;
END;
$$;

-- Set (or, with both values NULL, reset) a company override (cfo / vp_hr). Locked keys → 403 setting_locked.
CREATE OR REPLACE FUNCTION rpc_put_agent_setting(
  p_company_id    uuid,
  p_setting_key   text,
  p_value_numeric numeric DEFAULT NULL,
  p_value_text    text DEFAULT NULL
)
RETURNS TABLE (setting_key text, value_kind text, value_numeric numeric, value_text text, value_status text,
               display_he text, is_locked boolean, scope text, source_note text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_def agent_settings;
BEGIN
  PERFORM fn_assert_finance_viewer(p_company_id);
  SELECT * INTO v_def FROM agent_settings s WHERE s.company_id IS NULL AND s.setting_key = p_setting_key;
  IF NOT FOUND THEN
    PERFORM fn_raise_bad_request('unknown_setting');
  END IF;
  IF v_def.is_locked THEN
    PERFORM fn_raise_business('setting_locked');
  END IF;
  PERFORM fn_validate_agent_setting(v_def.value_kind, p_value_numeric, p_value_text);
  IF p_setting_key = 'score_range_coefficient' AND p_value_numeric IS NOT NULL AND p_value_numeric <= 0 THEN
    PERFORM fn_raise_bad_request('invalid_setting_value');
  END IF;

  DELETE FROM agent_settings s WHERE s.company_id = p_company_id AND s.setting_key = p_setting_key;
  IF p_value_numeric IS NOT NULL OR p_value_text IS NOT NULL THEN
    INSERT INTO agent_settings (company_id, setting_key, value_kind, value_numeric, value_text, value_status, is_locked, source_note)
    VALUES (p_company_id, p_setting_key, v_def.value_kind,
            CASE WHEN v_def.value_kind = 'numeric' THEN p_value_numeric END,
            CASE WHEN v_def.value_kind <> 'numeric' THEN p_value_text END,
            'set', false, 'company override');
  END IF;
  PERFORM fn_audit_view('agent_setting_put', jsonb_build_object('company_id', p_company_id, 'setting_key', p_setting_key));
  RETURN QUERY SELECT * FROM rpc_get_agent_settings(p_company_id) g WHERE g.setting_key = p_setting_key;
END;
$$;

REVOKE ALL ON FUNCTION rpc_get_agent_settings(uuid), rpc_put_agent_setting(uuid, text, numeric, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_get_agent_settings(uuid), rpc_put_agent_setting(uuid, text, numeric, text) TO authenticated, service_role;

-- ---------- score range & comparison gate (v3 §1.4, §4.3) ----------

-- Score range half-width = score_range_coefficient × (1 − r), r = reporting rate in [0, 1] (400 otherwise).
CREATE OR REPLACE FUNCTION fn_margin_of_error(p_company uuid, p_r numeric)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF p_r IS NULL OR p_r < 0 OR p_r > 1 THEN
    PERFORM fn_raise_bad_request('invalid_response_rate');
  END IF;
  RETURN round(fn_agent_setting_num(p_company, 'score_range_coefficient') * (1 - p_r), 4);
END;
$$;

-- True only when the two ranges do not overlap: |a − b| > margin(r_a) + margin(r_b).
CREATE OR REPLACE FUNCTION fn_can_compare(p_company uuid, p_a numeric, p_r_a numeric, p_b numeric, p_r_b numeric)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT CASE WHEN p_a IS NULL OR p_b IS NULL THEN false
              ELSE abs(p_a - p_b) > fn_margin_of_error(p_company, p_r_a) + fn_margin_of_error(p_company, p_r_b) END
$$;

-- margin_of_error(score, r) on a 0–100 scale, with the caller's company coefficient.
CREATE OR REPLACE FUNCTION rpc_margin_of_error(p_score numeric, p_response_rate numeric)
RETURNS TABLE (score numeric, response_rate numeric, margin numeric, range_low numeric, range_high numeric)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_m numeric;
BEGIN
  IF p_score IS NULL OR p_score < 0 OR p_score > 100 THEN
    PERFORM fn_raise_bad_request('invalid_score');
  END IF;
  v_m := fn_margin_of_error(fn_my_company(), p_response_rate);
  RETURN QUERY SELECT p_score, p_response_rate, v_m, greatest(0, p_score - v_m), least(100, p_score + v_m);
END;
$$;

-- can_compare(score_a, r_a, score_b, r_b): false + "אין הבדל שאפשר לקבוע" when the ranges overlap.
CREATE OR REPLACE FUNCTION rpc_can_compare(p_score_a numeric, p_r_a numeric, p_score_b numeric, p_r_b numeric)
RETURNS TABLE (comparable boolean, required_gap numeric, display_he text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_c uuid := fn_my_company();
  v_ok boolean;
BEGIN
  v_ok := fn_can_compare(v_c, p_score_a, p_r_a, p_score_b, p_r_b);
  RETURN QUERY SELECT v_ok, fn_margin_of_error(v_c, p_r_a) + fn_margin_of_error(v_c, p_r_b),
                      CASE WHEN v_ok THEN NULL ELSE 'אין הבדל שאפשר לקבוע' END;
END;
$$;

REVOKE ALL ON FUNCTION fn_margin_of_error(uuid, numeric), fn_can_compare(uuid, numeric, numeric, numeric, numeric) FROM PUBLIC;
REVOKE ALL ON FUNCTION rpc_margin_of_error(numeric, numeric), rpc_can_compare(numeric, numeric, numeric, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_margin_of_error(numeric, numeric), rpc_can_compare(numeric, numeric, numeric, numeric) TO authenticated, service_role;

-- ---------- Agent 1 · EverStore budget ----------

-- Golden Spoons redeemed in EverStore by a company's employees in [p_from, p_to).
CREATE OR REPLACE FUNCTION fn_everstore_spent(p_company uuid, p_from timestamptz, p_to timestamptz)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT COALESCE(sum(sp.price_golden_spoons), 0)
    FROM shop_purchase sp JOIN users u ON u.user_id = sp.user_id
   WHERE u.company_id = p_company AND sp.purchased_at >= p_from AND sp.purchased_at < p_to
$$;

-- Budget state at an instant: month budget, spent so far, utilization %, linear end-of-month forecast %.
CREATE OR REPLACE FUNCTION fn_everstore_budget_state(p_company uuid, p_at timestamptz)
RETURNS TABLE (budget_month date, budget numeric, spent numeric, utilization_pct numeric, forecast_pct numeric)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_month   date := fn_agent_month_start(p_company, p_at);
  v_budget  numeric;
  v_spent   numeric;
  v_elapsed int;
  v_days    int;
BEGIN
  SELECT b.budget_golden_spoons INTO v_budget FROM everstore_budget b
   WHERE b.company_id = p_company AND b.budget_month = v_month;
  v_spent := fn_everstore_spent(p_company, fn_agent_day_start(p_company, v_month), p_at);
  v_elapsed := (fn_agent_local_ts(p_company, p_at)::date - v_month) + 1;
  v_days := (fn_month_shift(v_month, 1) - v_month);
  RETURN QUERY SELECT v_month, v_budget, v_spent,
    CASE WHEN v_budget > 0 THEN round(v_spent / v_budget * 100, 2) END,
    CASE WHEN v_budget > 0 THEN round(v_spent / v_elapsed * v_days / v_budget * 100, 2) END;
END;
$$;

-- The three alert thresholds (75 / 90 / 100 % by default) in effect, ascending.
CREATE OR REPLACE FUNCTION fn_budget_thresholds(p_company uuid)
RETURNS int[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT ARRAY(SELECT t::int FROM unnest(ARRAY[fn_agent_setting_num(p_company, 'budget_threshold_low_pct'),
                                               fn_agent_setting_num(p_company, 'budget_threshold_mid_pct'),
                                               fn_agent_setting_num(p_company, 'budget_threshold_high_pct')]) t
                WHERE t IS NOT NULL ORDER BY t)
$$;

-- Set the monthly EverStore budget in Golden Spoons (cfo / vp_hr). The agent itself never changes it.
CREATE OR REPLACE FUNCTION rpc_everstore_budget_set(p_company_id uuid, p_month date, p_budget_golden_spoons numeric)
RETURNS everstore_budget
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_row everstore_budget;
BEGIN
  PERFORM fn_assert_finance_viewer(p_company_id);
  IF p_month IS NULL OR p_budget_golden_spoons IS NULL OR p_budget_golden_spoons <= 0 THEN
    PERFORM fn_raise_bad_request('invalid_amount');
  END IF;
  INSERT INTO everstore_budget (company_id, budget_month, budget_golden_spoons)
  VALUES (p_company_id, fn_month_of(p_month), p_budget_golden_spoons)
  ON CONFLICT (company_id, budget_month) DO UPDATE
    SET budget_golden_spoons = EXCLUDED.budget_golden_spoons, set_at = clock_timestamp()
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

-- Set the internal ILS cost of a catalog item (cfo / vp_hr; used by liability_method avg_redeemed only).
CREATE OR REPLACE FUNCTION rpc_everstore_item_cost_set(p_item_id varchar, p_internal_cost_ils numeric)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  PERFORM fn_assert_finance_viewer(fn_my_company());
  IF p_internal_cost_ils IS NULL OR p_internal_cost_ils < 0
     OR NOT EXISTS (SELECT 1 FROM shop_item_catalog c WHERE c.item_id = p_item_id) THEN
    PERFORM fn_raise_bad_request('invalid_amount');
  END IF;
  INSERT INTO everstore_item_cost (item_id, internal_cost_ils) VALUES (p_item_id, p_internal_cost_ils)
  ON CONFLICT (item_id) DO UPDATE SET internal_cost_ils = EXCLUDED.internal_cost_ils, updated_at = clock_timestamp();
END;
$$;

-- run_daily_budget_summary(company): ONE summary per company-local day at daily_summary_time, created only
-- when a threshold not reported earlier in the budget month is crossed (v3 §3.4). Service job or cfo / vp_hr.
CREATE OR REPLACE FUNCTION rpc_run_daily_budget_summary(p_company_id uuid, p_now timestamptz DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_now      timestamptz := COALESCE(p_now, clock_timestamp());
  v_local    timestamp;
  v_time     text;
  v_state    record;
  v_reported int[];
  v_crossed  int[];
  v_row      agent_daily_summaries;
BEGIN
  PERFORM fn_assert_finance_viewer(p_company_id);
  v_local := fn_agent_local_ts(p_company_id, v_now);
  v_time := fn_agent_setting_text(p_company_id, 'daily_summary_time');
  IF v_time IS NULL THEN
    RETURN jsonb_build_object('status', 'not_defined', 'setting_key', 'daily_summary_time', 'display_he', 'לא הוגדר');
  END IF;
  IF v_local::time < v_time::time THEN
    RETURN jsonb_build_object('status', 'not_yet', 'local_date', v_local::date);
  END IF;
  SELECT * INTO v_row FROM agent_daily_summaries s WHERE s.company_id = p_company_id AND s.local_date = v_local::date;
  IF FOUND THEN
    RETURN jsonb_build_object('status', 'exists', 'local_date', v_row.local_date, 'thresholds_crossed', to_jsonb(v_row.thresholds_crossed));
  END IF;

  SELECT * INTO v_state FROM fn_everstore_budget_state(p_company_id, v_now);
  IF v_state.budget IS NULL THEN
    RETURN jsonb_build_object('status', 'no_budget', 'display_he', 'לא הוגדר', 'budget_month', v_state.budget_month);
  END IF;
  SELECT COALESCE(array_agg(DISTINCT t), '{}') INTO v_reported
    FROM agent_daily_summaries s, unnest(s.thresholds_crossed) t
   WHERE s.company_id = p_company_id AND s.budget_month = v_state.budget_month;
  SELECT COALESCE(array_agg(t ORDER BY t), '{}') INTO v_crossed
    FROM unnest(fn_budget_thresholds(p_company_id)) t
   WHERE v_state.utilization_pct >= t AND NOT (t = ANY (v_reported));
  IF cardinality(v_crossed) = 0 THEN
    RETURN jsonb_build_object('status', 'no_crossing', 'local_date', v_local::date);
  END IF;

  INSERT INTO agent_daily_summaries (company_id, local_date, budget_month, thresholds_crossed, utilization_pct, forecast_pct, sent_at)
  VALUES (p_company_id, v_local::date, v_state.budget_month, v_crossed, v_state.utilization_pct, v_state.forecast_pct, v_now)
  RETURNING * INTO v_row;
  RETURN jsonb_build_object('status', 'created', 'local_date', v_row.local_date, 'budget_month', v_row.budget_month,
                            'thresholds_crossed', to_jsonb(v_row.thresholds_crossed),
                            'utilization_pct', v_row.utilization_pct, 'forecast_pct', v_row.forecast_pct);
END;
$$;

-- GET /agents/budget/daily-summary?date= — the summary of a company-local day (cfo / vp_hr), or status none.
CREATE OR REPLACE FUNCTION rpc_get_daily_budget_summary(p_company_id uuid, p_date date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_row agent_daily_summaries;
BEGIN
  PERFORM fn_assert_finance_viewer(p_company_id);
  SELECT * INTO v_row FROM agent_daily_summaries s WHERE s.company_id = p_company_id AND s.local_date = p_date;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'none', 'local_date', p_date);
  END IF;
  RETURN jsonb_build_object('status', 'sent', 'local_date', v_row.local_date, 'budget_month', v_row.budget_month,
                            'thresholds_crossed', to_jsonb(v_row.thresholds_crossed),
                            'utilization_pct', v_row.utilization_pct, 'forecast_pct', v_row.forecast_pct, 'sent_at', v_row.sent_at);
END;
$$;

-- Average internal ILS cost of one redeemed Golden Spoon in the company (items with a known cost only).
CREATE OR REPLACE FUNCTION fn_avg_redeemed_spoon_cost_ils(p_company uuid)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT CASE WHEN sum(sp.price_golden_spoons) > 0 THEN sum(c.internal_cost_ils) / sum(sp.price_golden_spoons) END
    FROM shop_purchase sp
    JOIN users u ON u.user_id = sp.user_id
    JOIN everstore_item_cost c ON c.item_id = sp.item_id
   WHERE u.company_id = p_company
$$;

-- get_open_golden_spoons_liability(company) — cfo / vp_hr only (v3 §3.2): open Golden Spoons + internal ILS
-- estimate by liability_method. No per-employee figure, no rate shown to any employee API.
CREATE OR REPLACE FUNCTION rpc_get_open_golden_spoons_liability(p_company_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_open   numeric;
  v_method text := fn_agent_setting_text(p_company_id, 'liability_method');
  v_cost   numeric;
BEGIN
  PERFORM fn_assert_finance_viewer(p_company_id);
  SELECT COALESCE(sum(a.golden_spoons), 0) INTO v_open
    FROM avatar_state a JOIN users u ON u.user_id = a.user_id WHERE u.company_id = p_company_id;
  v_cost := CASE v_method WHEN 'fixed_cost' THEN fn_agent_setting_num(p_company_id, 'spoon_cost_ils')
                          WHEN 'avg_redeemed' THEN fn_avg_redeemed_spoon_cost_ils(p_company_id) END;
  RETURN jsonb_build_object(
    'open_golden_spoons', v_open,
    'ils_estimate', CASE WHEN v_cost IS NOT NULL THEN round(v_open * v_cost, 2) END,
    'ils_status', CASE WHEN v_cost IS NULL THEN 'not_defined' ELSE 'set' END,
    'liability_method', COALESCE(v_method, 'not_defined'),
    'display_he', CASE WHEN v_cost IS NULL THEN 'לא הוגדר' END,
    'how_calculated_he', CASE v_method
       WHEN 'fixed_cost' THEN 'מספר Golden Spoons פתוחות × עלות פנימית קבועה לכפית (spoon_cost_ils).'
       WHEN 'avg_redeemed' THEN 'מספר Golden Spoons פתוחות × העלות הממוצעת של Golden Spoon שמומשה בפועל.'
       ELSE 'שיטת ההערכה לא הוגדרה; מוצג רק מספר ה-Golden Spoons הפתוחות.' END
       || ' כולל עובדים שעזבו בתוך 30 יום למימוש; אחרי זה היתרה מתאפסת.',
    'updated_at', clock_timestamp());
END;
$$;

-- Last company-local day an ex-employee may still redeem (end-of-employment date + exit_redemption_days).
CREATE OR REPLACE FUNCTION fn_exit_redemption_deadline(p_user_id uuid)
RETURNS date
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT fn_agent_local_ts(u.company_id, u.employment_ended_at)::date
         + fn_agent_setting_num(u.company_id, 'exit_redemption_days')::int
    FROM users u WHERE u.user_id = p_user_id AND u.employment_ended_at IS NOT NULL
$$;

-- True while an ex-employee (with an employee profile) is inside the 30-day redemption window.
CREATE OR REPLACE FUNCTION fn_in_exit_redemption_window(p_user_id uuid, p_at timestamptz DEFAULT NULL)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT COALESCE((SELECT u.has_employee_profile
                          AND fn_agent_local_ts(u.company_id, COALESCE(p_at, clock_timestamp()))::date
                              <= fn_exit_redemption_deadline(u.user_id)
                     FROM users u WHERE u.user_id = p_user_id AND u.employment_ended_at IS NOT NULL), false)
$$;

-- expire_departed_golden_spoons() — daily job: from day 31 after the end of employment the balance resets
-- to 0, leaves the open liability and is logged WORM in golden_spoons_ledger ('expired_after_exit').
CREATE OR REPLACE FUNCTION rpc_expire_departed_golden_spoons(p_now timestamptz DEFAULT NULL)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_now timestamptz := COALESCE(p_now, clock_timestamp());
  r     record;
  v_n   int := 0;
BEGIN
  IF fn_is_client_call() THEN
    PERFORM fn_raise_business('insufficient_privilege');
  END IF;
  FOR r IN
    SELECT u.user_id, u.company_id, a.golden_spoons, fn_exit_redemption_deadline(u.user_id) AS deadline
      FROM users u JOIN avatar_state a ON a.user_id = u.user_id
     WHERE u.employment_ended_at IS NOT NULL AND a.golden_spoons > 0
       AND fn_agent_local_ts(u.company_id, v_now)::date > fn_exit_redemption_deadline(u.user_id)
     FOR UPDATE OF a
  LOOP
    INSERT INTO golden_spoons_ledger (user_id, company_id, event_type, amount, exit_deadline)
    VALUES (r.user_id, r.company_id, 'expired_after_exit', r.golden_spoons, r.deadline)
    ON CONFLICT (user_id, event_type, exit_deadline) DO NOTHING;
    UPDATE avatar_state SET golden_spoons = 0, updated_at = clock_timestamp() WHERE user_id = r.user_id;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;

REVOKE ALL ON FUNCTION fn_everstore_spent(uuid, timestamptz, timestamptz), fn_everstore_budget_state(uuid, timestamptz),
                       fn_budget_thresholds(uuid), fn_avg_redeemed_spoon_cost_ils(uuid),
                       fn_exit_redemption_deadline(uuid), fn_in_exit_redemption_window(uuid, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION rpc_everstore_budget_set(uuid, date, numeric), rpc_everstore_item_cost_set(varchar, numeric),
                       rpc_run_daily_budget_summary(uuid, timestamptz), rpc_get_daily_budget_summary(uuid, date),
                       rpc_get_open_golden_spoons_liability(uuid), rpc_expire_departed_golden_spoons(timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_everstore_budget_set(uuid, date, numeric), rpc_everstore_item_cost_set(varchar, numeric),
                          rpc_run_daily_budget_summary(uuid, timestamptz), rpc_get_daily_budget_summary(uuid, date),
                          rpc_get_open_golden_spoons_liability(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION rpc_expire_departed_golden_spoons(timestamptz) TO service_role;

-- ---------- EverStore anonymous aggregate budget summary (former v1.6.14 scope, vp_hr / cfo) ----------
-- Aggregates by category / item only: purchase_count + total_golden_spoons, plus the time_benefit total.
-- Never user_id, pseudonym, person_id, team / department or any individual timestamp.
-- Small cells (v3 §3.5): categories with < small_category_min_buyers (5) distinct buyers form "אחר"; if "אחר"
-- still has < 5 buyers it merges into the smallest category that passes (marked "כולל קטגוריות קטנות"); if no
-- category passes, only the company total is returned. Items with < 5 buyers inside a passing category are
-- collapsed into one "פריטים נוספים" row of that category (v1.6.16 judgment, same rule one level down).
CREATE OR REPLACE FUNCTION fn_everstore_budget_summary(p_from date DEFAULT NULL, p_to date DEFAULT NULL)
RETURNS TABLE (
  row_type                  text,
  category                  text,
  item_id                   varchar,
  name_he                   varchar,
  tier                      text,
  cosmetic_only             boolean,
  provider                  text,
  purchase_count            bigint,
  total_golden_spoons       numeric(12, 1),
  includes_small_categories boolean,
  note_he                   text
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_company  uuid := fn_my_company();
  v_min      int;
  v_from     date;
  v_to       date;
  v_has_small boolean;
  v_other_n  int;
  v_target   text;
  v_tb_n     int;
BEGIN
  IF v_company IS NULL OR NOT fn_is_finance_viewer(v_company) THEN
    PERFORM fn_raise_business('insufficient_privilege');
  END IF;
  v_min  := fn_agent_setting_num(v_company, 'small_category_min_buyers')::int;
  v_from := COALESCE(p_from, fn_agent_month_start(v_company, clock_timestamp()));
  v_to   := COALESCE(p_to, fn_agent_local_ts(v_company, clock_timestamp())::date);
  IF v_from > v_to THEN
    PERFORM fn_raise_bad_request('invalid_date_range');
  END IF;

  CREATE TEMP TABLE IF NOT EXISTS pg_temp.es_base (buyer uuid, category text, item_id varchar, name_he varchar,
    tier text, cosmetic_only boolean, provider text, spoons numeric) ON COMMIT DROP;
  TRUNCATE pg_temp.es_base;
  INSERT INTO pg_temp.es_base
  SELECT sp.user_id, sp.category, sp.item_id, c.name_he, c.tier::text, sp.cosmetic_only, c.provider, sp.price_golden_spoons
    FROM shop_purchase sp
    JOIN users u ON u.user_id = sp.user_id
    JOIN shop_item_catalog c ON c.item_id = sp.item_id
   WHERE u.company_id = v_company
     AND fn_agent_local_ts(v_company, sp.purchased_at)::date BETWEEN v_from AND v_to;

  SELECT bool_or(n < v_min) INTO v_has_small
    FROM (SELECT count(DISTINCT b.buyer) AS n FROM pg_temp.es_base b GROUP BY b.category) x;
  SELECT count(DISTINCT b.buyer) INTO v_other_n FROM pg_temp.es_base b
   WHERE b.category IN (SELECT b2.category FROM pg_temp.es_base b2 GROUP BY b2.category HAVING count(DISTINCT b2.buyer) < v_min);
  IF COALESCE(v_has_small, false) AND v_other_n < v_min THEN
    SELECT b.category INTO v_target FROM pg_temp.es_base b GROUP BY b.category
    HAVING count(DISTINCT b.buyer) >= v_min
     ORDER BY count(DISTINCT b.buyer), sum(b.spoons), b.category LIMIT 1;
  END IF;
  SELECT count(DISTINCT b.buyer) INTO v_tb_n FROM pg_temp.es_base b WHERE b.category = 'time_benefit';

  -- 1. company total (always)
  RETURN QUERY SELECT 'company_total'::text, NULL::text, NULL::varchar, 'סך החברה'::varchar, NULL::text, NULL::boolean,
                      NULL::text, count(*)::bigint, COALESCE(sum(b.spoons), 0)::numeric(12, 1), false, NULL::text
                 FROM pg_temp.es_base b;
  -- 2. explicit time_benefit voucher total (shown only with ≥ v_min buyers)
  RETURN QUERY SELECT 'time_benefit_total'::text, 'time_benefit'::text, NULL::varchar, 'שוברי זמן'::varchar, NULL::text,
                      NULL::boolean, NULL::text,
                      CASE WHEN v_tb_n >= v_min OR v_tb_n = 0 THEN count(*)::bigint END,
                      CASE WHEN v_tb_n >= v_min OR v_tb_n = 0 THEN COALESCE(sum(b.spoons), 0)::numeric(12, 1) END,
                      false, CASE WHEN v_tb_n BETWEEN 1 AND v_min - 1 THEN 'אין מספיק קונים להצגה' END
                 FROM pg_temp.es_base b WHERE b.category = 'time_benefit';
  IF COALESCE(v_has_small, false) AND v_other_n < v_min AND v_target IS NULL THEN
    RETURN;                                   -- no category passes: company total only
  END IF;

  -- 3. item rows of passing categories (items with < v_min buyers collapsed per category)
  RETURN QUERY
  WITH cat AS (SELECT b.category FROM pg_temp.es_base b GROUP BY b.category HAVING count(DISTINCT b.buyer) >= v_min),
       itm AS (SELECT b.category, b.item_id, count(DISTINCT b.buyer) AS buyers FROM pg_temp.es_base b
                WHERE b.category IN (SELECT cat.category FROM cat) GROUP BY b.category, b.item_id)
  SELECT CASE WHEN i.buyers >= v_min THEN 'item' ELSE 'item_small_merged' END,
         b.category,
         CASE WHEN i.buyers >= v_min THEN b.item_id END,
         CASE WHEN i.buyers >= v_min THEN b.name_he ELSE 'פריטים נוספים'::varchar END,
         CASE WHEN i.buyers >= v_min THEN b.tier END,
         CASE WHEN i.buyers >= v_min THEN b.cosmetic_only END,
         CASE WHEN i.buyers >= v_min THEN b.provider END,
         count(*)::bigint, sum(b.spoons)::numeric(12, 1),
         b.category IS NOT DISTINCT FROM v_target,
         CASE WHEN b.category IS NOT DISTINCT FROM v_target THEN 'כולל קטגוריות קטנות' END
    FROM pg_temp.es_base b JOIN itm i ON i.category = b.category AND i.item_id = b.item_id
   GROUP BY 1, 2, 3, 4, 5, 6, 7, 10, 11
   ORDER BY 2, 3 NULLS LAST;

  -- 4. small categories: own "אחר" row (≥ v_min buyers together) or merged into v_target
  IF COALESCE(v_has_small, false) THEN
    RETURN QUERY
    SELECT CASE WHEN v_target IS NULL THEN 'other' ELSE 'merged_small_categories' END,
           COALESCE(v_target, 'אחר'), NULL::varchar, 'אחר'::varchar, NULL::text, NULL::boolean, NULL::text,
           count(*)::bigint, sum(b.spoons)::numeric(12, 1), v_target IS NOT NULL,
           CASE WHEN v_target IS NOT NULL THEN 'כולל קטגוריות קטנות' END
      FROM pg_temp.es_base b
     WHERE b.category IN (SELECT b2.category FROM pg_temp.es_base b2 GROUP BY b2.category HAVING count(DISTINCT b2.buyer) < v_min);
  END IF;
END;
$$;

-- Same summary as an RPC (POST /rpc/rpc_everstore_budget_summary).
CREATE OR REPLACE FUNCTION rpc_everstore_budget_summary(p_from date DEFAULT NULL, p_to date DEFAULT NULL)
RETURNS TABLE (row_type text, category text, item_id varchar, name_he varchar, tier text, cosmetic_only boolean,
               provider text, purchase_count bigint, total_golden_spoons numeric(12, 1),
               includes_small_categories boolean, note_he text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT * FROM fn_everstore_budget_summary(p_from, p_to)
$$;

-- Current company-local month to date, as a view (vp_hr / cfo; others → 403 from the function).
CREATE OR REPLACE VIEW everstore_budget_summary_v AS
  SELECT * FROM fn_everstore_budget_summary(NULL, NULL);

REVOKE ALL ON FUNCTION fn_everstore_budget_summary(date, date), rpc_everstore_budget_summary(date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_everstore_budget_summary(date, date), rpc_everstore_budget_summary(date, date) TO authenticated;
REVOKE ALL ON everstore_budget_summary_v FROM PUBLIC, anon;
GRANT SELECT ON everstore_budget_summary_v TO authenticated;

-- ---------- Agent 2 · burnout forecast (team = company + department; group level only) ----------

-- Employees of a team during a company month: everyone employed at any time that month — leavers of the
-- month stay in the denominator (v3 §4.5). Governance-only users (no employee profile) are not counted.
CREATE OR REPLACE FUNCTION fn_team_month_members(p_company uuid, p_group varchar, p_month date)
RETURNS int
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT count(*)::int FROM users u
   WHERE u.company_id = p_company AND (p_group IS NULL OR u.department = p_group) AND u.has_employee_profile
     AND (u.hire_date IS NULL OR u.hire_date < fn_month_shift(p_month, 1))
     AND (u.employment_ended_at IS NULL OR fn_agent_local_ts(p_company, u.employment_ended_at)::date >= p_month)
$$;

-- Team PCQ-12 monthly average (0–100) and its number of מדווחים בפועל (distinct reporters).
CREATE OR REPLACE FUNCTION fn_team_month_pcq(p_company uuid, p_group varchar, p_month date)
RETURNS TABLE (avg_score numeric, reporters int)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT round(avg(q.pcq12_score), 2), count(DISTINCT q.user_id)::int
    FROM questionnaire_submission q JOIN users u ON u.user_id = q.user_id
   WHERE u.company_id = p_company AND (p_group IS NULL OR u.department = p_group)
     AND q.questionnaire_code = 'PCQ-12'
     AND q.local_date >= p_month AND q.local_date < fn_month_shift(p_month, 1)
$$;

-- Approved absences of a team in a month as ONE aggregate count: early leave + approved absence entries.
CREATE OR REPLACE FUNCTION fn_team_month_absences(p_company uuid, p_group varchar, p_month date)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT ((SELECT count(*) FROM early_leave_log e JOIN users u ON u.user_id = e.user_id
            WHERE u.company_id = p_company AND u.department = p_group
              AND e.local_date >= p_month AND e.local_date < fn_month_shift(p_month, 1))
        + (SELECT count(*) FROM approved_absence_entry a JOIN users u ON u.user_id = a.user_id
            WHERE u.company_id = p_company AND u.department = p_group
              AND a.requested_date >= p_month AND a.requested_date < fn_month_shift(p_month, 1)))::numeric
$$;

-- Latest team מס קיפוח (team_aggregate) and Happiness Debt (shadow_balance_aggregate) of a company month.
CREATE OR REPLACE FUNCTION fn_team_month_tax_debt(p_company uuid, p_group varchar, p_month date)
RETURNS TABLE (deprivation_tax numeric, happiness_debt numeric)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT (SELECT t.deprivation_tax_amount FROM team_aggregate t
           WHERE t.org_id = p_company AND t.department = p_group
             AND t.calculated_at >= fn_agent_day_start(p_company, p_month)
             AND t.calculated_at <  fn_agent_day_start(p_company, fn_month_shift(p_month, 1))
           ORDER BY t.calculated_at DESC LIMIT 1),
         (SELECT s.happiness_debt_balance FROM shadow_balance_aggregate s
           WHERE s.org_id = p_company AND s.department = p_group
             AND s.calculated_at >= fn_agent_day_start(p_company, p_month)
             AND s.calculated_at <  fn_agent_day_start(p_company, fn_month_shift(p_month, 1))
           ORDER BY s.calculated_at DESC LIMIT 1)
$$;

-- Moving average of the p_w elements ending at index p_end (NULLs ignored).
CREATE OR REPLACE FUNCTION fn_ma(p_vals numeric[], p_end int, p_w int)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT round(avg(v), 4) FROM unnest(p_vals[greatest(1, p_end - p_w + 1):p_end]) v
$$;

-- Pooled reporting rate r over the p_w months ending at p_end (Σ reporters ÷ Σ employees).
CREATE OR REPLACE FUNCTION fn_pooled_rate(p_rep int[], p_mem int[], p_end int, p_w int)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE WHEN sum(m) > 0 THEN least(1, round(sum(r)::numeric / sum(m), 4)) ELSE 0 END
    FROM unnest(p_rep[greatest(1, p_end - p_w + 1):p_end], p_mem[greatest(1, p_end - p_w + 1):p_end]) x(r, m)
$$;

-- One burnout indicator: crosses its threshold in each of the last p_k periods of the moving average?
-- p_kind 'drop' (PCQ-12: drop ≥ pct AND larger than the two score ranges) or 'rise' (rise ≥ pct).
CREATE OR REPLACE FUNCTION fn_burnout_signal(p_company uuid, p_kind text, p_vals numeric[], p_w int, p_k int,
                                             p_pct numeric, p_rep int[] DEFAULT NULL, p_mem int[] DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_n int := cardinality(p_vals);
  v_cur numeric; v_prev numeric; v_ok boolean;
  v_crossed boolean[] := '{}';
BEGIN
  FOR i IN (v_n - p_k + 1)..v_n LOOP
    v_cur := fn_ma(p_vals, i, p_w);
    v_prev := fn_ma(p_vals, i - 1, p_w);
    IF v_cur IS NULL OR v_prev IS NULL OR v_prev <= 0 THEN
      v_ok := false;
    ELSIF p_kind = 'drop' THEN
      v_ok := (v_prev - v_cur) / v_prev * 100 >= p_pct
              AND (v_prev - v_cur) > fn_margin_of_error(p_company, fn_pooled_rate(p_rep, p_mem, i, p_w))
                                     + fn_margin_of_error(p_company, fn_pooled_rate(p_rep, p_mem, i - 1, p_w));
    ELSE
      v_ok := (v_cur - v_prev) / v_prev * 100 >= p_pct;
    END IF;
    v_crossed := v_crossed || v_ok;
  END LOOP;
  v_cur := fn_ma(p_vals, v_n, p_w);
  v_prev := fn_ma(p_vals, v_n - 1, p_w);
  RETURN jsonb_build_object(
    'moving_average', v_cur, 'previous_moving_average', v_prev,
    'change_pct', CASE WHEN v_prev > 0 THEN round((v_cur - v_prev) / v_prev * 100, 2) END,
    'threshold_pct', p_pct, 'crossed_last_periods', to_jsonb(v_crossed),
    'rising', (SELECT bool_and(c) FROM unnest(v_crossed) c));
END;
$$;

-- Voluntary exits + transfer requests of a team (or the whole company when p_group IS NULL) over the
-- p_w company months ending at p_month.
CREATE OR REPLACE FUNCTION fn_movement_events(p_company uuid, p_group varchar, p_month date, p_w int)
RETURNS int
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT COALESCE(sum(m.voluntary_exits + m.transfer_requests), 0)::int FROM team_movements m
   WHERE m.company_id = p_company AND (p_group IS NULL OR m.group_id = p_group)
     AND m.period_month > fn_month_shift(p_month, -p_w) AND m.period_month <= p_month
$$;

-- 5th signal for one period (Karin 30.10): team rate (events of the last 3 months ÷ team employees) ≥ 1.5 ×
-- organization average AND ≥ 2 events AND a team of ≥ 10 employees. Parameters from agent_settings.
CREATE OR REPLACE FUNCTION fn_movement_period(p_company uuid, p_group varchar, p_month date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_w      int := fn_agent_setting_num(p_company, 'movement_window_months')::int;
  v_events int := fn_movement_events(p_company, p_group, p_month, v_w);
  v_team   int := fn_team_month_members(p_company, p_group, p_month);
  v_org_ev int := fn_movement_events(p_company, NULL, p_month, v_w);
  v_org_n  int := fn_team_month_members(p_company, NULL, p_month);
  v_rate   numeric; v_org numeric;
BEGIN
  v_rate := CASE WHEN v_team > 0 THEN round(v_events::numeric / v_team, 4) END;
  v_org  := CASE WHEN v_org_n > 0 THEN round(v_org_ev::numeric / v_org_n, 4) END;
  RETURN jsonb_build_object(
    'team_rate', v_rate, 'organization_rate', v_org, 'enough_events',
    v_events >= fn_agent_setting_num(p_company, 'movement_min_events'),
    'team_size_ok', v_team >= fn_agent_setting_num(p_company, 'movement_min_team_size'),
    'alert', COALESCE(v_team >= fn_agent_setting_num(p_company, 'movement_min_team_size')
                      AND v_events >= fn_agent_setting_num(p_company, 'movement_min_events')
                      AND v_org > 0
                      AND v_rate >= fn_agent_setting_num(p_company, 'movement_rate_multiplier') * v_org, false));
END;
$$;

-- The caller may read a team's agent figures: cfo / vp_hr, or a manager whose solid subtree holds a team member.
CREATE OR REPLACE FUNCTION fn_may_read_team_agent(p_company uuid, p_group varchar)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT NOT fn_is_client_call()
      OR fn_is_finance_viewer(p_company)
      OR (fn_is_org_manager(p_company) AND EXISTS (
            SELECT 1 FROM users u WHERE u.company_id = p_company AND u.department = p_group
                                    AND fn_in_solid_subtree(auth.uid(), u.user_id)))
$$;

-- get_burnout_trend(team) — coverage full (≥ 10 מדווחים בפועל) / partial (5–9: PCQ-12 + absences only) /
-- none (< 5). "סיכון עולה" = ≥ 1 indicator crosses its threshold in 2 consecutive periods of the 3-month
-- moving average. 12 כפיות are never read. Output is group level only — never an employee identifier, and
-- never an input to any employee evaluation.
CREATE OR REPLACE FUNCTION rpc_get_burnout_trend(p_company_id uuid, p_team_id varchar, p_month date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_month date := COALESCE(fn_month_of(p_month), fn_agent_month_start(p_company_id, clock_timestamp()));
  v_w int := fn_agent_setting_num(p_company_id, 'burnout_ma_months')::int;
  v_k int := fn_agent_setting_num(p_company_id, 'burnout_consecutive_periods')::int;
  v_n int;
  v_m date;
  v_pcq numeric[] := '{}'; v_rep int[] := '{}'; v_mem int[] := '{}';
  v_tax numeric[] := '{}'; v_debt numeric[] := '{}'; v_abs numeric[] := '{}';
  r record;
  v_cov text; v_r numeric; v_margin numeric; v_prev_r numeric;
  v_sig_pcq jsonb; v_sig_abs jsonb; v_sig_tax jsonb; v_sig_debt jsonb; v_sig_mov jsonb;
  v_mov_alerts boolean[] := '{}'; v_mov jsonb;
  v_na constant text := 'אין מספיק מדווחים בפועל להצגה';
  v_rising boolean;
BEGIN
  IF NOT fn_may_read_team_agent(p_company_id, p_team_id) THEN
    PERFORM fn_raise_business('insufficient_privilege');
  END IF;
  v_n := v_w + v_k;
  FOR i IN 1..v_n LOOP
    v_m := fn_month_shift(v_month, i - v_n);
    SELECT * INTO r FROM fn_team_month_pcq(p_company_id, p_team_id, v_m);
    v_pcq := v_pcq || r.avg_score; v_rep := v_rep || COALESCE(r.reporters, 0);
    v_mem := v_mem || fn_team_month_members(p_company_id, p_team_id, v_m);
    SELECT * INTO r FROM fn_team_month_tax_debt(p_company_id, p_team_id, v_m);
    v_tax := v_tax || r.deprivation_tax; v_debt := v_debt || r.happiness_debt;
    v_abs := v_abs || fn_team_month_absences(p_company_id, p_team_id, v_m);
  END LOOP;

  v_cov := CASE WHEN v_rep[v_n] >= fn_privacy_min_n('shadow_balance') THEN 'full'
                WHEN v_rep[v_n] >= fn_privacy_min_n('regular') THEN 'partial' ELSE 'none' END;
  IF v_cov = 'none' THEN
    RETURN jsonb_build_object('team', p_team_id, 'month', v_month, 'coverage', 'none', 'display_he', v_na,
                              'rising_risk', false, 'how_calculated_he', v_na);
  END IF;

  v_r := CASE WHEN v_mem[v_n] > 0 THEN least(1, round(v_rep[v_n]::numeric / v_mem[v_n], 4)) ELSE 0 END;
  v_prev_r := CASE WHEN v_mem[v_n - 1] > 0 THEN least(1, round(v_rep[v_n - 1]::numeric / v_mem[v_n - 1], 4)) ELSE 0 END;
  v_margin := fn_margin_of_error(p_company_id, v_r);
  v_sig_pcq := fn_burnout_signal(p_company_id, 'drop', v_pcq, v_w, v_k, fn_agent_setting_num(p_company_id, 'pcq_drop_pct'), v_rep, v_mem)
               || jsonb_build_object('score', v_pcq[v_n], 'margin', v_margin,
                                     'comparable_with_previous_month', fn_can_compare(p_company_id, v_pcq[v_n], v_r, v_pcq[v_n - 1], v_prev_r));
  IF NOT (v_sig_pcq->>'comparable_with_previous_month')::boolean THEN
    v_sig_pcq := v_sig_pcq || jsonb_build_object('display_he', 'אין הבדל שאפשר לקבוע');
  END IF;
  v_sig_abs := fn_burnout_signal(p_company_id, 'rise', v_abs, v_w, v_k, fn_agent_setting_num(p_company_id, 'rise_pct'))
               || jsonb_build_object('count', v_abs[v_n], 'aggregate_only', true);

  IF v_cov = 'full' THEN
    v_sig_tax := fn_burnout_signal(p_company_id, 'rise', v_tax, v_w, v_k, fn_agent_setting_num(p_company_id, 'rise_pct'));
    v_sig_debt := fn_burnout_signal(p_company_id, 'rise', v_debt, v_w, v_k, fn_agent_setting_num(p_company_id, 'rise_pct'));
  ELSE
    v_sig_tax := jsonb_build_object('display_he', v_na, 'rising', false);
    v_sig_debt := jsonb_build_object('display_he', v_na, 'rising', false);
  END IF;

  -- 5th signal: sensitive — only for full coverage AND a team of ≥ movement_min_team_size employees
  IF v_cov = 'full' AND v_mem[v_n] >= fn_agent_setting_num(p_company_id, 'movement_min_team_size') THEN
    FOR i IN (v_n - v_k + 1)..v_n LOOP
      v_mov := fn_movement_period(p_company_id, p_team_id, fn_month_shift(v_month, i - v_n));
      v_mov_alerts := v_mov_alerts || (v_mov->>'alert')::boolean;
    END LOOP;
    v_sig_mov := jsonb_build_object('shown', true, 'team_rate', v_mov->'team_rate',
                                    'organization_rate', v_mov->'organization_rate',
                                    'crossed_last_periods', to_jsonb(v_mov_alerts),
                                    'rising', (SELECT bool_and(a) FROM unnest(v_mov_alerts) a));
  ELSE
    v_sig_mov := jsonb_build_object('shown', false, 'rising', false,
      'display_he', format('לא מוצג: מדד רגיש, מוצג רק לצוות של %s עובדים ומעלה עם תצוגה מלאה',
                           fn_agent_setting_num(p_company_id, 'movement_min_team_size')::int));
  END IF;

  v_rising := COALESCE((v_sig_pcq->>'rising')::boolean, false) OR COALESCE((v_sig_abs->>'rising')::boolean, false)
           OR COALESCE((v_sig_tax->>'rising')::boolean, false) OR COALESCE((v_sig_debt->>'rising')::boolean, false)
           OR COALESCE((v_sig_mov->>'rising')::boolean, false);
  RETURN jsonb_build_object(
    'team', p_team_id, 'month', v_month, 'coverage', v_cov,
    'reporters_count', v_rep[v_n], 'response_rate', v_r, 'margin', v_margin,
    'comparable', (v_sig_pcq->>'comparable_with_previous_month')::boolean,
    'card_label_he', CASE WHEN v_cov = 'partial' THEN 'מגמה חלקית' END,
    'how_calculated_short_he', CASE WHEN v_cov = 'partial' THEN 'המגמה חלקית: מבוססת רק על PCQ-12 והיעדרויות.' END,
    'signals', jsonb_build_object('pcq12', v_sig_pcq, 'approved_absences', v_sig_abs,
                                  'deprivation_tax', v_sig_tax, 'happiness_debt', v_sig_debt,
                                  'team_movements', v_sig_mov),
    'rising_risk', v_rising,
    'rising_risk_label_he', CASE WHEN v_rising THEN 'סיכון עולה' END,
    'how_calculated_he', CASE WHEN v_cov = 'partial'
      THEN 'המגמה חלקית. היא מבוססת רק על PCQ-12 והיעדרויות, כי יש בקבוצה פחות מ-10 מדווחים בפועל.'
      ELSE 'ממוצע נע של 3 חודשים; סיכון עולה כשסימן אחד לפחות חוצה את הסף בשתי תקופות רצופות. נכנסים: PCQ-12, מס קיפוח, חוב אושר, היעדרויות מאושרות (מספר מצטבר) ועזיבות רצוניות ובקשות מעבר ברמת צוות. לא נכנסים: 12 כפיות, נתון ברמת עובד ונתונים ביומטריים.' END);
END;
$$;

REVOKE ALL ON FUNCTION fn_team_month_members(uuid, varchar, date), fn_team_month_pcq(uuid, varchar, date),
                       fn_team_month_absences(uuid, varchar, date), fn_team_month_tax_debt(uuid, varchar, date),
                       fn_burnout_signal(uuid, text, numeric[], int, int, numeric, int[], int[]),
                       fn_movement_events(uuid, varchar, date, int), fn_movement_period(uuid, varchar, date),
                       fn_may_read_team_agent(uuid, varchar) FROM PUBLIC;
REVOKE ALL ON FUNCTION rpc_get_burnout_trend(uuid, varchar, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_get_burnout_trend(uuid, varchar, date) TO authenticated, service_role;

-- Team movements input (vp_hr / cfo): aggregate monthly counts per team, no names.
CREATE OR REPLACE FUNCTION rpc_put_team_movements(p_company_id uuid, p_team_id varchar, p_month date,
                                                  p_voluntary_exits int, p_transfer_requests int)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  PERFORM fn_assert_finance_viewer(p_company_id);
  IF p_month IS NULL OR p_team_id IS NULL OR COALESCE(p_voluntary_exits, -1) < 0 OR COALESCE(p_transfer_requests, -1) < 0 THEN
    PERFORM fn_raise_bad_request('invalid_amount');
  END IF;
  INSERT INTO team_movements (company_id, group_id, period_month, voluntary_exits, transfer_requests)
  VALUES (p_company_id, p_team_id, fn_month_of(p_month), p_voluntary_exits, p_transfer_requests)
  ON CONFLICT (company_id, group_id, period_month) DO UPDATE
    SET voluntary_exits = EXCLUDED.voluntary_exits, transfer_requests = EXCLUDED.transfer_requests, updated_at = clock_timestamp();
END;
$$;
REVOKE ALL ON FUNCTION rpc_put_team_movements(uuid, varchar, date, int, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_put_team_movements(uuid, varchar, date, int, int) TO authenticated, service_role;

-- Optional group-level EPWI inputs (v3 §6.1; stored only — the EPWI formula is unchanged).
CREATE OR REPLACE FUNCTION rpc_put_epwi_inputs(p_company_id uuid, p_team_id varchar, p_week_start_date date,
                                               p_after_hours_messages int DEFAULT NULL, p_schedule_volatility numeric DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  PERFORM fn_assert_finance_viewer(p_company_id);
  INSERT INTO epwi_inputs (company_id, group_id, week_start_date, after_hours_messages, schedule_volatility)
  VALUES (p_company_id, p_team_id, p_week_start_date, p_after_hours_messages, p_schedule_volatility)
  ON CONFLICT (company_id, group_id, week_start_date) DO UPDATE
    SET after_hours_messages = EXCLUDED.after_hours_messages, schedule_volatility = EXCLUDED.schedule_volatility;
END;
$$;
REVOKE ALL ON FUNCTION rpc_put_epwi_inputs(uuid, varchar, date, int, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_put_epwi_inputs(uuid, varchar, date, int, numeric) TO authenticated, service_role;

-- ---------- Happiness Debt on exit & documented remediation (v3 §5.3) ----------

-- AFTER employment ends: the leaver's Happiness Debt share moves to the memo line "יצא עם העוזבים"
-- (happiness_debt_events leaver_transfer + happiness_debt_ledger exported_on_exit). It is never deleted:
-- employee_value_asset.happiness_debt_liability is left as is. No person_id is written to the event.
CREATE OR REPLACE FUNCTION fn_users_leaver_debt_transfer()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_amount numeric;
  v_month  date;
  v_event  uuid;
BEGIN
  SELECT e.happiness_debt_liability INTO v_amount FROM employee_value_asset e WHERE e.user_id = NEW.user_id;
  IF COALESCE(v_amount, 0) > 0 AND NEW.company_id IS NOT NULL THEN
    v_month := fn_agent_month_start(NEW.company_id, NEW.employment_ended_at);
    INSERT INTO happiness_debt_events (company_id, group_id, period_month, event_type, amount)
    VALUES (NEW.company_id, NEW.department, v_month, 'leaver_transfer', v_amount)
    RETURNING event_id INTO v_event;
    -- v1.6.17 (A-8): internal, closed link so a reversed offboarding can find this transfer
    INSERT INTO happiness_debt_leaver_link (event_id, user_id) VALUES (v_event, NEW.user_id);
    INSERT INTO happiness_debt_ledger (company_id, group_id, period_month, obligation_class, amount, exported_on_exit)
    VALUES (NEW.company_id, NEW.department, v_month, NULL, v_amount, true);
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_leaver_debt_transfer ON users;
CREATE TRIGGER trg_users_leaver_debt_transfer
    AFTER UPDATE OF employment_ended_at ON users
    FOR EACH ROW WHEN (OLD.employment_ended_at IS NULL AND NEW.employment_ended_at IS NOT NULL)
    EXECUTE FUNCTION fn_users_leaver_debt_transfer();

-- v1.6.17 (A-8, Karin 31.10): an offboarding was reversed (marked by mistake or the employee returned) → the
-- latest not-yet-reversed leaver_transfer of this employee goes back to its team: a 'leaver_reversal' event
-- (same team, same amount, period = company month of the reversal; reverses_event_id = the transfer). The
-- memo line "יצא עם העוזבים" decreases by that amount; the original transfer stays (WORM, history intact).
-- Idempotent: a transfer is reversed at most once (unique index); a second call changes nothing.
-- Returns an id-free summary (no person_id / user_id / pseudonym). Only while the employment is active again.
CREATE OR REPLACE FUNCTION fn_reverse_leaver_transfer(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_t     happiness_debt_events;
  v_month date;
  v_rev   uuid;
BEGIN
  IF fn_employment_ended(p_user_id) THEN
    RETURN jsonb_build_object('status', 'still_offboarded');
  END IF;
  SELECT e.* INTO v_t
    FROM happiness_debt_leaver_link l
    JOIN happiness_debt_events e ON e.event_id = l.event_id AND e.event_type = 'leaver_transfer'
   WHERE l.user_id = p_user_id
     AND NOT EXISTS (SELECT 1 FROM happiness_debt_events r
                      WHERE r.event_type = 'leaver_reversal' AND r.reverses_event_id = e.event_id)
   ORDER BY e.created_at DESC
   LIMIT 1
   FOR UPDATE OF e;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'nothing_to_reverse');
  END IF;
  v_month := fn_agent_month_start(v_t.company_id, clock_timestamp());
  INSERT INTO happiness_debt_events (company_id, group_id, period_month, event_type, amount, reverses_event_id)
  VALUES (v_t.company_id, v_t.group_id, v_month, 'leaver_reversal', v_t.amount, v_t.event_id)
  ON CONFLICT (reverses_event_id) WHERE event_type = 'leaver_reversal' DO NOTHING
  RETURNING event_id INTO v_rev;
  IF v_rev IS NULL THEN
    RETURN jsonb_build_object('status', 'nothing_to_reverse');
  END IF;
  RETURN jsonb_build_object('status', 'reversed', 'reversal_event_id', v_rev, 'reverses_event_id', v_t.event_id,
                            'team', v_t.group_id, 'period_month', v_month, 'amount', v_t.amount,
                            'memo_after', fn_leaver_memo(v_t.company_id, v_month), 'label_he', 'יצא עם העוזבים');
END;
$$;
REVOKE ALL ON FUNCTION fn_reverse_leaver_transfer(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_reverse_leaver_transfer(uuid) TO service_role;

-- Trigger body: employment_ended_at cleared (rpc_revert_offboarding or the HR system) → reverse the transfer.
CREATE OR REPLACE FUNCTION fn_users_leaver_debt_reversal()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  PERFORM fn_reverse_leaver_transfer(NEW.user_id);
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_leaver_debt_reversal ON users;
CREATE TRIGGER trg_users_leaver_debt_reversal
    AFTER UPDATE OF employment_ended_at ON users
    FOR EACH ROW WHEN (OLD.employment_ended_at IS NOT NULL AND NEW.employment_ended_at IS NULL)
    EXECUTE FUNCTION fn_users_leaver_debt_reversal();

-- Record a documented fix (vp_hr / cfo): remediation_records row + happiness_debt_events 'remediation'.
CREATE OR REPLACE FUNCTION rpc_record_remediation(p_company_id uuid, p_team_id varchar, p_remediated_on date,
                                                  p_what_fixed text, p_reduction_amount numeric)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_id uuid;
BEGIN
  PERFORM fn_assert_finance_viewer(p_company_id);
  IF p_team_id IS NULL OR p_remediated_on IS NULL OR p_what_fixed IS NULL OR length(btrim(p_what_fixed)) = 0
     OR p_reduction_amount IS NULL OR p_reduction_amount <= 0 THEN
    PERFORM fn_raise_bad_request('invalid_remediation');
  END IF;
  INSERT INTO remediation_records (company_id, group_id, remediated_on, what_fixed, approved_by, reduction_amount)
  VALUES (p_company_id, p_team_id, p_remediated_on, btrim(p_what_fixed), auth.uid(), p_reduction_amount)
  RETURNING remediation_id INTO v_id;
  INSERT INTO happiness_debt_events (company_id, group_id, period_month, event_type, amount, remediation_id)
  VALUES (p_company_id, p_team_id, fn_month_of(p_remediated_on), 'remediation', p_reduction_amount, v_id);
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION rpc_record_remediation(uuid, varchar, date, text, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_record_remediation(uuid, varchar, date, text, numeric) TO authenticated, service_role;

-- Memo line "יצא עם העוזבים" through a month: Σ leaver_transfer − Σ remediation − Σ leaver_reversal (v1.6.17)
-- (never below 0).
CREATE OR REPLACE FUNCTION fn_leaver_memo(p_company uuid, p_month date)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT greatest(0, COALESCE(sum(CASE WHEN e.event_type = 'leaver_transfer' THEN e.amount
                                       WHEN e.event_type IN ('remediation', 'leaver_reversal') THEN -e.amount END), 0))
    FROM happiness_debt_events e WHERE e.company_id = p_company AND e.period_month <= p_month
$$;

-- ---------- Agent 3 · monthly board report ----------

-- Company Happiness Debt balance and מס קיפוח of a month = Σ over departments of the latest
-- shadow_balance_aggregate row calculated in that company month (NULL when none).
CREATE OR REPLACE FUNCTION fn_company_month_shadow(p_company uuid, p_month date)
RETURNS TABLE (happiness_debt_balance numeric, deprivation_tax numeric)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT sum(x.happiness_debt_balance), sum(x.deprivation_tax_amount)
    FROM (SELECT DISTINCT ON (s.department) s.happiness_debt_balance, s.deprivation_tax_amount
            FROM shadow_balance_aggregate s
           WHERE s.org_id = p_company
             AND s.calculated_at >= fn_agent_day_start(p_company, p_month)
             AND s.calculated_at <  fn_agent_day_start(p_company, fn_month_shift(p_month, 1))
           ORDER BY s.department, s.calculated_at DESC) x
$$;

-- Distinct מדווחים בפועל of a company month (questionnaires, spoon reports, weekly self-reports).
CREATE OR REPLACE FUNCTION fn_company_month_reporters(p_company uuid, p_month date)
RETURNS int
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT count(DISTINCT x.user_id)::int FROM (
    SELECT q.user_id FROM questionnaire_submission q WHERE q.local_date >= p_month AND q.local_date < fn_month_shift(p_month, 1)
    UNION SELECT sb.user_id FROM spoon_budget sb WHERE sb.reported_at IS NOT NULL
                  AND sb.budget_date >= p_month AND sb.budget_date < fn_month_shift(p_month, 1)
    UNION SELECT w.user_id FROM workload_self_report w WHERE w.week_start_date >= p_month AND w.week_start_date < fn_month_shift(p_month, 1)
  ) x JOIN users u ON u.user_id = x.user_id WHERE u.company_id = p_company
$$;

-- The 4-line Shadow Balance split of a month as jsonb (NULL when the split is incomplete).
CREATE OR REPLACE FUNCTION fn_debt_split(p_company uuid, p_month date)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT CASE WHEN count(*) = 4 THEN jsonb_agg(jsonb_build_object(
           'obligation_class', l.obligation_class, 'amount', l.amount,
           'label_he', CASE l.obligation_class WHEN 'dormant_legal' THEN 'התחייבות משפטית רדומה'
                                               WHEN 'constructive' THEN 'התחייבות משתמעת'
                                               WHEN 'statistical_accrued' THEN 'התחייבות סטטיסטית מצטברת'
                                               ELSE 'שחיקה כלכלית טהורה' END)
           ORDER BY array_position(ARRAY['dormant_legal', 'constructive', 'statistical_accrued', 'pure_economic_erosion'], l.obligation_class)) END
    FROM happiness_debt_ledger l
   WHERE l.company_id = p_company AND l.period_month = p_month AND NOT l.exported_on_exit
$$;

-- Sum of the 4-line split (NULL when incomplete).
CREATE OR REPLACE FUNCTION fn_debt_split_total(p_company uuid, p_month date)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT CASE WHEN count(*) = 4 THEN sum(l.amount) END FROM happiness_debt_ledger l
   WHERE l.company_id = p_company AND l.period_month = p_month AND NOT l.exported_on_exit
$$;

-- CFO / vp_hr enter the 4-line split of a month (management disclosure, not a book provision).
CREATE OR REPLACE FUNCTION rpc_put_happiness_debt_split(p_company_id uuid, p_month date, p_dormant_legal numeric,
                                                        p_constructive numeric, p_statistical_accrued numeric,
                                                        p_pure_economic_erosion numeric)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_month date := fn_month_of(p_month);
BEGIN
  PERFORM fn_assert_finance_viewer(p_company_id);
  IF least(p_dormant_legal, p_constructive, p_statistical_accrued, p_pure_economic_erosion) < 0
     OR p_dormant_legal IS NULL OR p_constructive IS NULL OR p_statistical_accrued IS NULL OR p_pure_economic_erosion IS NULL THEN
    PERFORM fn_raise_bad_request('invalid_amount');
  END IF;
  DELETE FROM happiness_debt_ledger l WHERE l.company_id = p_company_id AND l.period_month = v_month AND NOT l.exported_on_exit;
  INSERT INTO happiness_debt_ledger (company_id, period_month, obligation_class, amount) VALUES
    (p_company_id, v_month, 'dormant_legal', p_dormant_legal),
    (p_company_id, v_month, 'constructive', p_constructive),
    (p_company_id, v_month, 'statistical_accrued', p_statistical_accrued),
    (p_company_id, v_month, 'pure_economic_erosion', p_pure_economic_erosion);
  PERFORM fn_audit_view('happiness_debt_split_put', jsonb_build_object('company_id', p_company_id, 'month', v_month));
  RETURN fn_debt_split(p_company_id, v_month);
END;
$$;

-- CFO / vp_hr enter GAAP EBITDA (and optional payroll expense) of a month for the reconciliation table.
CREATE OR REPLACE FUNCTION rpc_put_board_reconciliation(p_company_id uuid, p_month date, p_gaap_ebitda numeric,
                                                        p_payroll_expense numeric DEFAULT NULL,
                                                        p_is_first_period boolean DEFAULT false)
RETURNS board_reconciliation
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_row board_reconciliation;
BEGIN
  PERFORM fn_assert_finance_viewer(p_company_id);
  IF p_month IS NULL OR p_gaap_ebitda IS NULL THEN
    PERFORM fn_raise_bad_request('invalid_amount');
  END IF;
  INSERT INTO board_reconciliation (company_id, period_month, gaap_ebitda, payroll_expense, is_first_period)
  VALUES (p_company_id, fn_month_of(p_month), p_gaap_ebitda, p_payroll_expense, COALESCE(p_is_first_period, false))
  ON CONFLICT (company_id, period_month) DO UPDATE
    SET gaap_ebitda = EXCLUDED.gaap_ebitda, payroll_expense = EXCLUDED.payroll_expense,
        is_first_period = EXCLUDED.is_first_period, entered_at = clock_timestamp()
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

-- Assurance tier 0–4 of a board metric (v3 §5.6), cfo / vp_hr.
CREATE OR REPLACE FUNCTION rpc_put_metric_assurance(p_company_id uuid, p_metric_key text, p_tier int, p_explanation_he text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  PERFORM fn_assert_finance_viewer(p_company_id);
  IF p_tier IS NULL OR p_tier NOT BETWEEN 0 AND 4 OR p_metric_key IS NULL THEN
    PERFORM fn_raise_bad_request('invalid_assurance_tier');
  END IF;
  INSERT INTO metric_assurance (company_id, metric_key, tier, explanation_he)
  VALUES (p_company_id, p_metric_key, p_tier, p_explanation_he)
  ON CONFLICT (company_id, metric_key) DO UPDATE
    SET tier = EXCLUDED.tier, explanation_he = EXCLUDED.explanation_he, updated_at = clock_timestamp();
END;
$$;

-- Hebrew label of an assurance tier (v3 §5.6).
CREATE OR REPLACE FUNCTION fn_assurance_label_he(p_tier int)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_tier WHEN 0 THEN 'לא מאומת' WHEN 1 THEN 'בקרה פנימית' WHEN 2 THEN 'בדיקה פנימית מתועדת'
                     WHEN 3 THEN 'סקירה חיצונית' WHEN 4 THEN 'ביקורת חיצונית מלאה' END
$$;

-- Monthly 15-question check (B1–B4, C1–C7, R1–R4). C6–C7 count only with independent approval.
-- ≥ 2/3 yes (10+) = "התחייבות אמינה"; ≤ 1/3 (5−) = "הוצאה לתצוגה"; in between v3 gives no label → "לא הוגדר".
CREATE OR REPLACE FUNCTION rpc_put_bcr_check(p_company_id uuid, p_month date, p_answers jsonb,
                                             p_independent_approved boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_keys text[] := ARRAY['B1','B2','B3','B4','C1','C2','C3','C4','C5','C6','C7','R1','R2','R3','R4'];
  v_yes  int;
  v_res  text;
BEGIN
  PERFORM fn_assert_finance_viewer(p_company_id);
  IF p_answers IS NULL OR jsonb_typeof(p_answers) <> 'object'
     OR (SELECT count(*) FROM jsonb_object_keys(p_answers)) <> 15
     OR EXISTS (SELECT 1 FROM unnest(v_keys) k WHERE jsonb_typeof(p_answers->k) IS DISTINCT FROM 'boolean') THEN
    PERFORM fn_raise_bad_request('invalid_bcr_answers');
  END IF;
  SELECT count(*) INTO v_yes FROM unnest(v_keys) k
   WHERE (p_answers->>k)::boolean AND (k NOT IN ('C6', 'C7') OR COALESCE(p_independent_approved, false));
  v_res := CASE WHEN v_yes >= 10 THEN 'התחייבות אמינה' WHEN v_yes <= 5 THEN 'הוצאה לתצוגה' ELSE 'לא הוגדר' END;
  INSERT INTO bcr_checks (company_id, check_month, answers, independent_approved, yes_count, result_he)
  VALUES (p_company_id, fn_month_of(p_month), p_answers, COALESCE(p_independent_approved, false), v_yes, v_res)
  ON CONFLICT (company_id, check_month) DO UPDATE
    SET answers = EXCLUDED.answers, independent_approved = EXCLUDED.independent_approved,
        yes_count = EXCLUDED.yes_count, result_he = EXCLUDED.result_he, created_at = clock_timestamp();
  RETURN jsonb_build_object('yes_count', v_yes, 'of', 15, 'result_he', v_res);
END;
$$;

-- Reconciliation lines of one month (GAAP − 4 debt lines − מס קיפוח = CHR Real EBITDA), or NULL when an
-- input is missing; raises 422 reconciliation_unbalanced when the lines do not balance.
CREATE OR REPLACE FUNCTION fn_reconciliation_month(p_company uuid, p_month date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_rec   board_reconciliation;
  v_sh    record;
  v_split jsonb := fn_debt_split(p_company, p_month);
  v_total numeric := fn_debt_split_total(p_company, p_month);
  v_chr   numeric;
BEGIN
  SELECT * INTO v_rec FROM board_reconciliation b WHERE b.company_id = p_company AND b.period_month = p_month;
  SELECT * INTO v_sh FROM fn_company_month_shadow(p_company, p_month);
  IF v_rec.company_id IS NULL OR v_split IS NULL OR v_sh.happiness_debt_balance IS NULL THEN
    RETURN NULL;
  END IF;
  -- v3 test 14: the 4 lines must add up to happiness_debt_balance
  IF v_total <> v_sh.happiness_debt_balance THEN
    PERFORM fn_raise_unprocessable('reconciliation_unbalanced');
  END IF;
  v_chr := round(v_rec.gaap_ebitda - v_total - COALESCE(v_sh.deprivation_tax, 0), 2);
  -- v3 test 15: GAAP − debt − מס קיפוח = CHR Real EBITDA (the locked O-18 formula)
  IF v_chr <> fn_chr_real_ebitda(v_rec.gaap_ebitda, v_sh.happiness_debt_balance, v_sh.deprivation_tax) THEN
    PERFORM fn_raise_unprocessable('reconciliation_unbalanced');
  END IF;
  RETURN jsonb_build_object('gaap_ebitda', v_rec.gaap_ebitda, 'debt_lines', v_split,
                            'happiness_debt_balance', v_sh.happiness_debt_balance,
                            'deprivation_tax', COALESCE(v_sh.deprivation_tax, 0), 'chr_real_ebitda', v_chr,
                            'payroll_expense', v_rec.payroll_expense, 'is_first_period', v_rec.is_first_period);
END;
$$;

-- Company PCQ-12 monthly average with its reporting rate (NULL score below the regular threshold of 5).
CREATE OR REPLACE FUNCTION fn_company_month_pcq(p_company uuid, p_month date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  r record;
  v_mem int := fn_team_month_members(p_company, NULL, p_month);
  v_r numeric;
BEGIN
  SELECT * INTO r FROM fn_team_month_pcq(p_company, NULL, p_month);
  IF COALESCE(r.reporters, 0) < fn_privacy_min_n('regular') THEN
    RETURN jsonb_build_object('score', NULL, 'display_he', 'אין מספיק מדווחים בפועל להצגה');
  END IF;
  v_r := CASE WHEN v_mem > 0 THEN least(1, round(r.reporters::numeric / v_mem, 4)) ELSE 0 END;
  RETURN jsonb_build_object('score', r.avg_score, 'reporters_count', r.reporters, 'response_rate', v_r,
                            'margin', fn_margin_of_error(p_company, v_r));
END;
$$;

-- Turnover replacement cost applied only to leavers ABOVE the per-tier baseline (v3 §5.5). Counts of leavers
-- are not returned; a missing baseline → "לא הוגדר" and no total.
CREATE OR REPLACE FUNCTION fn_turnover_above_baseline(p_company uuid, p_month date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  t text; v_leavers int; v_base numeric; v_cost numeric := 0; v_undefined boolean := false;
  v_tiers jsonb := '[]';
BEGIN
  FOREACH t IN ARRAY ARRAY['junior', 'mid', 'senior'] LOOP
    v_base := fn_agent_setting_num(p_company, 'turnover_baseline_' || t);
    SELECT count(*) INTO v_leavers FROM users u
     WHERE u.company_id = p_company AND u.employment_ended_at IS NOT NULL
       AND fn_month_of(fn_agent_local_ts(p_company, u.employment_ended_at)::date) = p_month
       AND fn_effective_turnover_tier(u.user_id) = t;
    IF v_base IS NULL THEN
      v_undefined := true;
    ELSE
      v_cost := v_cost + greatest(0, v_leavers - v_base)
                * COALESCE(fn_company_tier_avg_salary(p_company, t), 0) * fn_turnover_tier_midpoint_factor(t);
    END IF;
    v_tiers := v_tiers || jsonb_build_object('tier', t, 'baseline_status', CASE WHEN v_base IS NULL THEN 'not_defined' ELSE 'set' END,
                                             'display_he', CASE WHEN v_base IS NULL THEN 'לא הוגדר' END);
  END LOOP;
  RETURN jsonb_build_object('tiers', v_tiers, 'cost_above_baseline', CASE WHEN v_undefined THEN NULL ELSE round(v_cost, 2) END,
                            'display_he', CASE WHEN v_undefined THEN 'לא הוגדר' END);
END;
$$;

-- "שוליים מטעים" (v3 §5.5): payroll expense falls because of leavers while the well-being index (company
-- PCQ-12) falls in the same period. NULL when an input is missing.
CREATE OR REPLACE FUNCTION fn_misleading_margins(p_company uuid, p_month date)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_pay numeric; v_pay_prev numeric; v_w numeric; v_w_prev numeric; v_leavers int;
BEGIN
  SELECT b.payroll_expense INTO v_pay FROM board_reconciliation b WHERE b.company_id = p_company AND b.period_month = p_month;
  SELECT b.payroll_expense INTO v_pay_prev FROM board_reconciliation b WHERE b.company_id = p_company AND b.period_month = fn_month_shift(p_month, -1);
  v_w := (fn_company_month_pcq(p_company, p_month)->>'score')::numeric;
  v_w_prev := (fn_company_month_pcq(p_company, fn_month_shift(p_month, -1))->>'score')::numeric;
  SELECT count(*) INTO v_leavers FROM users u
   WHERE u.company_id = p_company AND u.employment_ended_at IS NOT NULL
     AND fn_month_of(fn_agent_local_ts(p_company, u.employment_ended_at)::date) = p_month;
  IF v_pay IS NULL OR v_pay_prev IS NULL OR v_w IS NULL OR v_w_prev IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN v_pay < v_pay_prev AND v_leavers > 0 AND v_w < v_w_prev;
END;
$$;

-- build_board_report(company, month) — publishes only with a balanced line-by-line reconciliation and the
-- prior-period figures (v3 §5.1, tests 15 + 18); else 422. The 10 % / 12 % switch changes the DISPLAY only.
CREATE OR REPLACE FUNCTION rpc_build_board_report(p_company_id uuid, p_month date,
                                                  p_display_deprivation_rate numeric DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_month  date := fn_month_of(p_month);
  v_cur    jsonb;
  v_prev   jsonb;
  v_rate   numeric := fn_agent_setting_num(p_company_id, 'deprivation_tax_rate');
  v_alt    numeric := fn_agent_setting_num(p_company_id, 'deprivation_tax_sensitivity');
  v_disp   numeric := COALESCE(p_display_deprivation_rate, v_rate);
  v_tax    numeric;
  v_memo   jsonb;
  v_assur  jsonb;
  v_bcr    bcr_checks;
  v_report jsonb;
BEGIN
  PERFORM fn_assert_finance_viewer(p_company_id);
  IF v_disp NOT IN (v_rate, v_alt) THEN
    PERFORM fn_raise_bad_request('invalid_sensitivity_rate');
  END IF;
  v_cur := fn_reconciliation_month(p_company_id, v_month);
  IF v_cur IS NULL THEN
    PERFORM fn_raise_unprocessable('reconciliation_missing');
  END IF;
  IF NOT (v_cur->>'is_first_period')::boolean THEN
    v_prev := fn_reconciliation_month(p_company_id, fn_month_shift(v_month, -1));
    IF v_prev IS NULL THEN
      PERFORM fn_raise_unprocessable('reconciliation_prior_period_missing');
    END IF;
  END IF;

  v_tax := (v_cur->>'deprivation_tax')::numeric;
  v_memo := CASE WHEN fn_company_month_reporters(p_company_id, v_month) >= fn_privacy_min_n('shadow_balance')
                 THEN jsonb_build_object('amount', fn_leaver_memo(p_company_id, v_month), 'label_he', 'יצא עם העוזבים',
                                         'evidence_he', 'בינוני')
                 ELSE jsonb_build_object('amount', NULL, 'label_he', 'יצא עם העוזבים', 'display_he', 'אין מספיק מדווחים בפועל להצגה') END;
  SELECT jsonb_object_agg(k, jsonb_build_object('tier', COALESCE(m.tier, 0), 'label_he', fn_assurance_label_he(COALESCE(m.tier, 0))))
    INTO v_assur
    FROM unnest(ARRAY['chr_real_ebitda', 'happiness_debt_balance', 'deprivation_tax', 'exported_on_exit',
                      'pcq12_company', 'turnover_above_baseline', 'bcr_score']) k
    LEFT JOIN metric_assurance m ON m.company_id = p_company_id AND m.metric_key = k;
  SELECT * INTO v_bcr FROM bcr_checks b WHERE b.company_id = p_company_id AND b.check_month = v_month;

  v_report := jsonb_build_object(
    'month', v_month,
    'chr_real_ebitda', jsonb_build_object('value', v_cur->'chr_real_ebitda', 'gaap_ebitda', v_cur->'gaap_ebitda',
                                          'definition_he', 'מדד ניהולי חלופי, לא רווח חשבונאי'),
    'reconciliation', jsonb_build_array(
      jsonb_build_object('line', 'gaap_ebitda', 'label_he', 'GAAP EBITDA', 'current', v_cur->'gaap_ebitda', 'prior', v_prev->'gaap_ebitda')) ||
      (SELECT jsonb_agg(jsonb_build_object('line', c->>'obligation_class', 'label_he', 'פחות: ' || (c->>'label_he'),
                                           'current', c->'amount',
                                           'prior', (SELECT p->'amount' FROM jsonb_array_elements(v_prev->'debt_lines') p
                                                      WHERE p->>'obligation_class' = c->>'obligation_class')))
         FROM jsonb_array_elements(v_cur->'debt_lines') c) ||
      jsonb_build_array(
        jsonb_build_object('line', 'deprivation_tax', 'label_he', 'פחות: מס קיפוח', 'current', v_cur->'deprivation_tax', 'prior', v_prev->'deprivation_tax'),
        jsonb_build_object('line', 'chr_real_ebitda', 'label_he', 'שווה: CHR Real EBITDA', 'current', v_cur->'chr_real_ebitda', 'prior', v_prev->'chr_real_ebitda')),
    'prior_period_note_he', CASE WHEN v_prev IS NULL THEN 'אין תקופה קודמת (דוח ראשון)' END,
    'shadow_balance', v_cur->'debt_lines',
    'shadow_balance_note_he', 'גילוי ניהולי, לא הפרשה בספרים',
    'happiness_debt_balance', v_cur->'happiness_debt_balance',
    'exported_on_exit', v_memo,
    'deprivation_tax', jsonb_build_object('stored_rate', v_rate, 'stored_amount', v_tax, 'display_rate', v_disp,
                                          'display_amount', round(v_tax * v_disp / v_rate, 2),
                                          'note_he', 'נמדד בתפקידים מול לקוחות (Oswald et al. 2015; Bellet et al. 2024)'),
    'turnover_above_baseline', fn_turnover_above_baseline(p_company_id, v_month),
    'misleading_margins_flag', fn_misleading_margins(p_company_id, v_month),
    'wellbeing_pcq12', fn_company_month_pcq(p_company_id, v_month),
    'assurance_tier', v_assur,
    'bcr_score', CASE WHEN v_bcr.company_id IS NULL THEN jsonb_build_object('display_he', 'לא בוצע')
                      ELSE jsonb_build_object('yes_count', v_bcr.yes_count, 'of', 15, 'result_he', v_bcr.result_he) END,
    'choices_he', 'שיעור מס קיפוח 12% (מתג רגישות 10%); חוב אושר לפי נקודת האמצע של דרג העלות (40% / 125% / 300%); עלות החלפה רק מעל קו הבסיס לכל דרג.',
    'sources', jsonb_build_array(jsonb_build_object('topic_he', 'המושג CHR', 'source', 'צבאן ושביט 2025',
                                                    'doi', '10.1080/13571516.2025.2599785', 'status_he', 'פורסם')),
    'sources_note_he', 'קישורי DOI והמתאם r=0.37 בנספח לא אומתו — לבדוק לפני הנספח לדירקטוריון.');
  INSERT INTO board_report (company_id, period_month, report) VALUES (p_company_id, v_month, v_report);
  PERFORM fn_audit_view('board_report_published', jsonb_build_object('company_id', p_company_id, 'month', v_month));
  RETURN v_report;
END;
$$;

-- Latest published board report of a month: cfo / vp_hr and the company's governance roles.
CREATE OR REPLACE FUNCTION rpc_get_board_report(p_company_id uuid, p_month date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_r jsonb;
BEGIN
  IF fn_is_client_call() AND NOT fn_is_finance_viewer(p_company_id) AND NOT EXISTS (
       SELECT 1 FROM users u WHERE u.user_id = auth.uid() AND u.company_id = p_company_id AND u.employment_ended_at IS NULL
          AND u.app_role IN ('board_chair', 'board_member', 'owner_shareholder')) THEN
    PERFORM fn_raise_business('insufficient_privilege');
  END IF;
  SELECT b.report INTO v_r FROM board_report b
   WHERE b.company_id = p_company_id AND b.period_month = fn_month_of(p_month)
   ORDER BY b.built_at DESC LIMIT 1;
  IF v_r IS NULL THEN
    PERFORM fn_raise_unprocessable('board_report_not_published');
  END IF;
  RETURN v_r;
END;
$$;

REVOKE ALL ON FUNCTION fn_leaver_memo(uuid, date), fn_company_month_shadow(uuid, date), fn_company_month_reporters(uuid, date),
                       fn_debt_split(uuid, date), fn_debt_split_total(uuid, date), fn_reconciliation_month(uuid, date),
                       fn_company_month_pcq(uuid, date), fn_turnover_above_baseline(uuid, date),
                       fn_misleading_margins(uuid, date), fn_users_leaver_debt_transfer() FROM PUBLIC;
REVOKE ALL ON FUNCTION rpc_put_happiness_debt_split(uuid, date, numeric, numeric, numeric, numeric),
                       rpc_put_board_reconciliation(uuid, date, numeric, numeric, boolean),
                       rpc_put_metric_assurance(uuid, text, int, text), rpc_put_bcr_check(uuid, date, jsonb, boolean),
                       rpc_build_board_report(uuid, date, numeric), rpc_get_board_report(uuid, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_put_happiness_debt_split(uuid, date, numeric, numeric, numeric, numeric),
                          rpc_put_board_reconciliation(uuid, date, numeric, numeric, boolean),
                          rpc_put_metric_assurance(uuid, text, int, text), rpc_put_bcr_check(uuid, date, jsonb, boolean),
                          rpc_build_board_report(uuid, date, numeric), rpc_get_board_report(uuid, date) TO authenticated, service_role;
