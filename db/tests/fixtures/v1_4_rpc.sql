-- FIXTURE COPY (v1.6.7 migration tests) of the real CHR-ETRS v1.4 file rpc.sql
-- Source: local /workspace/chr-etrs-mvp-v1/rpc.sql (sha256 bff6344dbf32bebe596e326cbf54e6e878fbe8232402689fccf7f125de112f8f).
-- Only change: 0 occurrence(s) of the rejected salary literal in COMMENTS replaced by a token
-- (the pack-wide grep forbids it). Structure and code are unchanged.
-- =============================================================================
-- CHR-ETRS MVP v1.4 · rpc.sql
-- SoT: ADR index v10 + Q-016/027/033 v3. ALL writes via RPC.
-- Paths: POST /rpc/<function_name> with rpc_* names.
-- Deprivation tax system-computed (0.12 × salary × multiplier); not client-writable.
-- Version: 1.4.0-mvp
-- =============================================================================

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
-- Internal: Circuit Breaker v1 — spoons only (<3 OR <14% capacity)
-- NO HRV. Raises circuit_breaker_active (HTTP 403). Glass Box message.
-- Uses employee-local budget day (N-1).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_cb_check_spoons(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_spoons   int;
  v_capacity numeric(5, 2);
  v_local_date date;
BEGIN
  PERFORM fn_ensure_local_spoon_budget(p_user_id);
  v_local_date := fn_user_local_date(p_user_id);

  SELECT current_spoon_count, available_capacity_pct
    INTO v_spoons, v_capacity
    FROM spoon_budget
   WHERE user_id = p_user_id
     AND budget_date = v_local_date
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'circuit_breaker_active'
      USING ERRCODE = '42501',
            DETAIL = 'http_hint=403;code=circuit_breaker_active',
            HINT = 'circuit_breaker_active';
  END IF;

  -- Locked thresholds: <3 spoons OR <14% capacity (Q-008/032). No HRV.
  IF v_spoons < 3 OR COALESCE(v_capacity, 0) < 14 THEN
    RAISE EXCEPTION 'circuit_breaker_active'
      USING ERRCODE = '42501',
            DETAIL = 'http_hint=403;code=circuit_breaker_active',
            HINT = 'circuit_breaker_active';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION fn_cb_check_spoons(uuid) FROM PUBLIC;

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
-- rpc_assign_task — compute s_final path, CB spoons-only, debit, insert
-- Client does NOT send s_base for pricing — RPC computes from task_kind/flags.
-- Farming s_base=0 does NOT refill spoons (debit 0).
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
  v_budget_id  uuid;
  v_spoons     int;
  v_row        task;
  v_elem       jsonb;
  v_local_date date;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'anti_get_blocked'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=anti_get_blocked', HINT = 'anti_get_blocked';
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

  PERFORM fn_cb_check_spoons(p_assignee_id);
  v_local_date := fn_user_local_date(p_assignee_id);

  SELECT budget_id, current_spoon_count
    INTO v_budget_id, v_spoons
    FROM spoon_budget
   WHERE user_id = p_assignee_id
     AND budget_date = v_local_date
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'circuit_breaker_active'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=circuit_breaker_active', HINT = 'circuit_breaker_active';
  END IF;

  IF v_cost > v_spoons THEN
    -- Distinct from CB: anti_get_blocked (Q-001 / N-1–N-3 API v2) → HTTP 403
    RAISE EXCEPTION 'anti_get_blocked'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=anti_get_blocked', HINT = 'anti_get_blocked';
  END IF;

  IF v_cost > 0 THEN
    UPDATE spoon_budget
       SET current_spoon_count = current_spoon_count - v_cost,
           updated_at = clock_timestamp()
     WHERE budget_id = v_budget_id;
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

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION rpc_assign_task(uuid, varchar, task_kind_enum, boolean, boolean, jsonb, boolean, varchar, varchar) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_assign_task(uuid, varchar, task_kind_enum, boolean, boolean, jsonb, boolean, varchar, varchar) TO authenticated;

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
-- rpc_cuckoo_veto — employee sovereign veto within window
-- ---------------------------------------------------------------------------
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
    RAISE EXCEPTION 'anti_get_blocked'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=anti_get_blocked', HINT = 'anti_get_blocked';
  END IF;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION rpc_cuckoo_veto(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_cuckoo_veto(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- rpc_ledger_append — WORM insert only; UPDATE/DELETE → ledger_immutable 403
-- deprivation_tax_cost is SYSTEM-computed from subject EVA (Q-027); client cannot supply it.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_ledger_append(
  p_event_type       varchar,
  p_logic_hash       varchar,
  p_previous_hash    varchar DEFAULT NULL,
  p_amount_a         numeric DEFAULT NULL,
  p_amount_b         numeric DEFAULT NULL,
  p_subject_user_id  uuid DEFAULT NULL,  -- optional: tax snapshot from their EVA.deprivation_tax
  p_org_id           uuid DEFAULT NULL
)
RETURNS manager_ledger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row manager_ledger;
  v_tax numeric(12, 2);
BEGIN
  IF v_uid IS NULL OR fn_app_role() NOT IN ('manager', 'vp_hr', 'legal_ethics') THEN
    RAISE EXCEPTION 'anti_get_blocked'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=anti_get_blocked', HINT = 'anti_get_blocked';
  END IF;

  IF p_subject_user_id IS NOT NULL THEN
    SELECT e.deprivation_tax INTO v_tax
      FROM employee_value_asset e
     WHERE e.user_id = p_subject_user_id;
  END IF;

  -- TODO ADR Q-037: SHA-256 not locked — accept opaque logic_hash string
  INSERT INTO manager_ledger (
    manager_id, org_id, event_type, amount_a, amount_b,
    deprivation_tax_cost, logic_hash, previous_hash
  ) VALUES (
    v_uid, p_org_id, p_event_type, p_amount_a, p_amount_b,
    v_tax, p_logic_hash, p_previous_hash
  )
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION rpc_ledger_append(varchar, varchar, varchar, numeric, numeric, uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_ledger_append(varchar, varchar, varchar, numeric, numeric, uuid, uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- rpc_everstore_purchase — one RPC; client does NOT send price; CB does NOT block
-- Server looks up tier 10/20 golden_spoons (N-2 / 070 v5). No coin exchange.
-- Dutch auction event items: TODO numbers open — refuse until locked.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_everstore_purchase(
  p_item_id         varchar,
  p_idempotency_key varchar
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
  v_price    int;
  v_prior    jsonb;
  v_inv      jsonb;
BEGIN
  IF v_uid IS NULL OR fn_app_role() <> 'employee' THEN
    RAISE EXCEPTION 'anti_get_blocked'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=anti_get_blocked', HINT = 'anti_get_blocked';
  END IF;

  IF p_idempotency_key IS NULL OR length(trim(p_idempotency_key)) = 0 THEN
    RAISE EXCEPTION 'anti_get_blocked'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=anti_get_blocked', HINT = 'anti_get_blocked';
  END IF;

  INSERT INTO avatar_state (user_id)
  VALUES (v_uid)
  ON CONFLICT (user_id) DO NOTHING;

  SELECT * INTO v_state FROM avatar_state WHERE user_id = v_uid FOR UPDATE;

  v_prior := v_state.shop_idempotency -> p_idempotency_key;
  IF v_prior IS NOT NULL AND (v_prior->>'status') = 'ok' THEN
    RETURN v_state;
  END IF;

  SELECT * INTO v_item FROM shop_item_catalog WHERE item_id = p_item_id AND is_active;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'anti_get_blocked'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=anti_get_blocked', HINT = 'anti_get_blocked';
  END IF;

  IF v_item.tier = 'event_dutch' OR v_item.is_event THEN
    -- TODO ADR-070: Dutch auction numeric rules (start/floor/step) — open; no event seed in v1.1
    RAISE EXCEPTION 'anti_get_blocked'
      USING ERRCODE = '42501',
            DETAIL = 'http_hint=403;code=anti_get_blocked;TODO_dutch_auction',
            HINT = 'anti_get_blocked';
  END IF;

  v_price := v_item.price_coins;
  IF v_price IS NULL OR v_price NOT IN (10, 20) THEN
    RAISE EXCEPTION 'anti_get_blocked'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=anti_get_blocked', HINT = 'anti_get_blocked';
  END IF;

  -- N-2 seed uses golden_spoons; still support chr_coins rows if ever added — NO exchange
  IF v_item.currency = 'chr_coins' THEN
    IF v_state.chr_coins < v_price THEN
      RAISE EXCEPTION 'anti_get_blocked'
        USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=anti_get_blocked', HINT = 'anti_get_blocked';
    END IF;
    v_state.chr_coins := v_state.chr_coins - v_price;
  ELSE
    IF v_state.golden_spoons < v_price THEN
      RAISE EXCEPTION 'anti_get_blocked'
        USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=anti_get_blocked', HINT = 'anti_get_blocked';
    END IF;
    v_state.golden_spoons := v_state.golden_spoons - v_price;
  END IF;

  v_inv := COALESCE(v_state.shop_inventory, '[]'::jsonb) || jsonb_build_array(
    jsonb_build_object(
      'item_id', p_item_id,
      'qty', 1,
      'acquired_at', clock_timestamp(),
      'cosmetic_only', COALESCE(v_item.cosmetic_only, true)
    )
  );

  UPDATE avatar_state
     SET chr_coins = v_state.chr_coins,
         golden_spoons = v_state.golden_spoons,
         shop_inventory = v_inv,
         shop_idempotency = COALESCE(shop_idempotency, '{}'::jsonb) || jsonb_build_object(
           p_idempotency_key, jsonb_build_object(
             'item_id', p_item_id,
             'status', 'ok',
             'ts', clock_timestamp()
           )
         ),
         updated_at = clock_timestamp()
   WHERE user_id = v_uid
  RETURNING * INTO v_state;

  RETURN v_state;
END;
$$;

REVOKE ALL ON FUNCTION rpc_everstore_purchase(varchar, varchar) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_everstore_purchase(varchar, varchar) TO authenticated;

-- ---------------------------------------------------------------------------
-- rpc_pcq12_claim_monthly_reward — N-3: +10 golden spoons once per calendar month
-- Month boundary = employee timezone (date_trunc month of local date).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_pcq12_claim_monthly_reward()
RETURNS avatar_state
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_month date;
  v_state avatar_state;
  v_claimed uuid;
BEGIN
  IF v_uid IS NULL OR fn_app_role() <> 'employee' THEN
    RAISE EXCEPTION 'anti_get_blocked'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=anti_get_blocked', HINT = 'anti_get_blocked';
  END IF;

  v_month := fn_user_local_month_start(v_uid);
  IF v_month IS NULL THEN
    RAISE EXCEPTION 'anti_get_blocked'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=anti_get_blocked', HINT = 'anti_get_blocked';
  END IF;

  INSERT INTO avatar_state (user_id)
  VALUES (v_uid)
  ON CONFLICT (user_id) DO NOTHING;

  -- Unique (user_id, reward_month) enforces at most once per calendar month in user TZ
  INSERT INTO pcq12_monthly_reward (user_id, reward_month, golden_spoons_awarded)
  VALUES (v_uid, v_month, 10)
  ON CONFLICT (user_id, reward_month) DO NOTHING
  RETURNING user_id INTO v_claimed;

  IF v_claimed IS NULL THEN
    -- Already claimed this local calendar month — opaque anti_get (Glass Box)
    RAISE EXCEPTION 'anti_get_blocked'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=anti_get_blocked', HINT = 'anti_get_blocked';
  END IF;

  UPDATE avatar_state
     SET golden_spoons = golden_spoons + 10,
         updated_at = clock_timestamp()
   WHERE user_id = v_uid
  RETURNING * INTO v_state;

  RETURN v_state;
END;
$$;

REVOKE ALL ON FUNCTION rpc_pcq12_claim_monthly_reward() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_pcq12_claim_monthly_reward() TO authenticated;

-- ---------------------------------------------------------------------------
-- rpc_team_aggregate_refresh — refuses N<5 with aggregation_privacy_threshold
-- deprivation_tax_sum = SUM(EVA.deprivation_tax) for dept employees (Q-027 system)
-- Happiness debt / shadow_balance beyond tax: TODO Q-033 / Q-016 (leave NULL)
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
  v_n     int;
  v_avg   numeric(4, 2);
  v_tax   numeric(12, 2);
  v_row   team_aggregate;
BEGIN
  IF auth.uid() IS NULL OR NOT fn_is_org_manager(p_org_id) THEN
    RAISE EXCEPTION 'aggregation_privacy_threshold'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=aggregation_privacy_threshold', HINT = 'aggregation_privacy_threshold';
  END IF;

  SELECT count(*)::int
    INTO v_n
    FROM users u
   WHERE u.company_id = p_org_id
     AND u.department = p_department
     AND u.app_role = 'employee';

  IF v_n < 5 THEN
    RAISE EXCEPTION 'aggregation_privacy_threshold'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=aggregation_privacy_threshold', HINT = 'aggregation_privacy_threshold';
  END IF;

  SELECT round(avg(sb.current_spoon_count)::numeric, 2)
    INTO v_avg
    FROM spoon_budget sb
    JOIN users u ON u.user_id = sb.user_id
   WHERE u.company_id = p_org_id
     AND u.department = p_department
     AND sb.budget_date = (clock_timestamp() AT TIME ZONE u.timezone)::date;

  -- System SUM of GENERATED deprivation_tax (salary × multiplier × 0.12)
  SELECT round(COALESCE(sum(e.deprivation_tax), 0)::numeric, 2)
    INTO v_tax
    FROM employee_value_asset e
    JOIN users u ON u.user_id = e.user_id
   WHERE u.company_id = p_org_id
     AND u.department = p_department
     AND u.app_role = 'employee';

  INSERT INTO team_aggregate (
    org_id, department, member_count, team_spoon_avg,
    deprivation_tax_sum,
    happiness_debt_sum,    -- TODO Q-033 full formulas open
    shadow_balance_sum,    -- TODO Q-016 aggregate beyond tax open
    heat_map_bucket,
    psc12_team_avg,        -- TODO ADR-016 PSC-12 wording/frequency/storage
    dichotomous_alert_level,
    calculated_at
  ) VALUES (
    p_org_id, p_department, v_n, v_avg,
    v_tax, NULL, NULL,
    NULL,
    NULL,
    CASE WHEN v_avg IS NOT NULL AND v_avg < 3 THEN 'RED'::dichotomous_alert_enum
         ELSE 'GREEN'::dichotomous_alert_enum END,
    clock_timestamp()
  )
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION rpc_team_aggregate_refresh(uuid, varchar) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_team_aggregate_refresh(uuid, varchar) TO authenticated;


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
  v_tz  text;
  v_cc  char(2);
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
-- rpc_upsert_employee_value_asset — set annual_salary / sync multiplier (system path)
-- Client cannot write deprivation_tax (GENERATED). Multiplier from role_cost_config.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_upsert_employee_value_asset(
  p_user_id       uuid,
  p_annual_salary numeric DEFAULT NULL,
  p_direct_cost_opex numeric DEFAULT NULL,
  p_asset_value_capex numeric DEFAULT NULL
)
RETURNS employee_value_asset
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_role text;
  v_mult numeric(4, 2);
  v_row employee_value_asset;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'anti_get_blocked'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=anti_get_blocked', HINT = 'anti_get_blocked';
  END IF;

  -- Self or vp_hr/manager may set salary inputs; tax remains GENERATED
  IF v_uid <> p_user_id AND fn_app_role() NOT IN ('manager', 'vp_hr') THEN
    RAISE EXCEPTION 'anti_get_blocked'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=anti_get_blocked', HINT = 'anti_get_blocked';
  END IF;

  SELECT u.app_role INTO v_role FROM users u WHERE u.user_id = p_user_id;
  IF v_role IS NULL THEN
    RAISE EXCEPTION 'anti_get_blocked'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=anti_get_blocked', HINT = 'anti_get_blocked';
  END IF;

  SELECT r.replacement_cost_multiplier INTO v_mult
    FROM role_cost_config r WHERE r.role_key = v_role;
  IF v_mult IS NULL THEN
    v_mult := 1.50;
  END IF;

  INSERT INTO employee_value_asset (
    user_id, annual_salary, role_key, replacement_cost_multiplier,
    direct_cost_opex, asset_value_capex, updated_at
  ) VALUES (
    p_user_id, p_annual_salary, v_role, v_mult,
    COALESCE(p_direct_cost_opex, 0), p_asset_value_capex, clock_timestamp()
  )
  ON CONFLICT (user_id) DO UPDATE SET
    annual_salary = COALESCE(EXCLUDED.annual_salary, employee_value_asset.annual_salary),
    role_key = v_role,
    replacement_cost_multiplier = v_mult,
    direct_cost_opex = COALESCE(EXCLUDED.direct_cost_opex, employee_value_asset.direct_cost_opex),
    asset_value_capex = COALESCE(EXCLUDED.asset_value_capex, employee_value_asset.asset_value_capex),
    updated_at = clock_timestamp()
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION rpc_upsert_employee_value_asset(uuid, numeric, numeric, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_upsert_employee_value_asset(uuid, numeric, numeric, numeric) TO authenticated;

-- ---------------------------------------------------------------------------
-- rpc_set_role_cost_multiplier — vp_hr only; CHECK 0.5–2.0 enforced by table
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_set_role_cost_multiplier(
  p_role_key text,
  p_multiplier numeric
)
RETURNS role_cost_config
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_row role_cost_config;
BEGIN
  IF auth.uid() IS NULL OR fn_app_role() <> 'vp_hr' THEN
    RAISE EXCEPTION 'anti_get_blocked'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=anti_get_blocked', HINT = 'anti_get_blocked';
  END IF;

  UPDATE role_cost_config
     SET replacement_cost_multiplier = p_multiplier,
         updated_at = clock_timestamp()
   WHERE role_key = p_role_key
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'anti_get_blocked'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=anti_get_blocked', HINT = 'anti_get_blocked';
  END IF;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION rpc_set_role_cost_multiplier(text, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_set_role_cost_multiplier(text, numeric) TO authenticated;

-- ---------------------------------------------------------------------------
-- TODO stubs (not implemented — open ADR / not in 10 entities)
-- * rpc_dutch_auction_bid — Dutch auction numbers open (070)
-- * PSC-12 questionnaire wording/frequency/storage entity — open (016); not entity 11
-- * Happiness debt / diluted wage / shadow_balance full formulas — Q-033/Q-016 open
-- * Deprivation tax 12% + 1.5× salary LOCKED (Q-027 v3) — see GENERATED columns
-- * Contrast Nullification purchase rule — 070 open
-- * Avatar weight / immunity apply — Q-014 open
-- * Gold / CHR expiry rules — open (070)
-- ---------------------------------------------------------------------------
