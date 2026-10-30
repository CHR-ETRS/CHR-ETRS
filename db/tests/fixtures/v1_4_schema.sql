-- FIXTURE COPY (v1.6.7 migration tests) of the real CHR-ETRS v1.4 file schema.20261013.sql
-- Source: local /workspace/chr-etrs-drive-code-20261013/schema.20261013.sql (sha256 e1fd27cf75f9f0b7cec09099abee273db0df8a6afbc98754837f850f065cdf0f).
-- Only change: 5 occurrence(s) of the rejected salary literal in COMMENTS replaced by a token
-- (the pack-wide grep forbids it). Structure and code are unchanged.
-- =============================================================================
-- CHR-ETRS MVP v1.4 · schema.sql
-- SoT: ADR index v10 (2026-10-06) + Q-016/027/033 v3 Deprivation Tax. NLM ≠ SoT.
-- Locked: prior v1.3 locks + deprivation tax 12% (Oswald 2015 + Bellet/De Neve/Ward 2024);
--         replacement_cost = 1.5× annual_salary default, configurable 0.5×–2.0× per role;
--         NO hardcoded [rejected salary literal]; NO 13–14%.
-- Open ADR items marked TODO — do not invent numbers.
-- Version: 1.4.0-mvp
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ---------------------------------------------------------------------------
-- Auth / role stubs (no-op when Supabase already provides them)
-- ---------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS auth;

CREATE TABLE IF NOT EXISTS auth.users (
    id uuid PRIMARY KEY
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'auth' AND p.proname = 'uid' AND p.pronargs = 0
  ) THEN
    EXECUTE $fn$
      CREATE FUNCTION auth.uid()
      RETURNS uuid
      LANGUAGE sql
      STABLE
      AS $body$
        SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid
      $body$
    $fn$;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION auth.jwt_app_role()
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(current_setting('request.jwt.claim.app_role', true), '')
$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN BYPASSRLS;
  END IF;
END $$;

GRANT USAGE ON SCHEMA public TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE exposure_gate_enum AS ENUM ('CLOSED', 'FILTERED', 'OPEN');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE energy_state_enum AS ENUM ('GREEN_OPTIMAL', 'YELLOW_WARNING', 'RED_BANKRUPT');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE pacing_status_enum AS ENUM (
    'ACTIVE',
    'PAUSED_COOLING_OFF',
    'BLOCKED_ANTI_GET',
    'BLOCKED_CIRCUIT_BREAKER'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE cuckoo_status_enum AS ENUM (
    'VETO_WINDOW_ACTIVE',
    'VETOED_BY_EMPLOYEE',
    'EXPIRED_COMMITTED'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE avatar_role_enum AS ENUM ('HOPE', 'NESS', 'SHAY');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE dichotomous_alert_enum AS ENUM ('GREEN', 'RED');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE task_kind_enum AS ENUM ('farming', 'fighting');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE shop_tier_enum AS ENUM ('basic', 'advanced', 'event_dutch');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ---------------------------------------------------------------------------
-- Scaffolding: companies + users (tenant_id / company_id; RBAC app_role)
-- No ROOT_ADMIN user role (ADR-068).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS companies (
    company_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id    uuid GENERATED ALWAYS AS (company_id) STORED,
    company_name varchar(255) NOT NULL UNIQUE,
    industry     varchar(255),
    company_size varchar(50),
    location     varchar(255),
    created_at   timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE IF NOT EXISTS users (
    user_id       uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id    uuid REFERENCES companies(company_id) ON DELETE SET NULL,
    manager_id    uuid REFERENCES users(user_id) ON DELETE SET NULL,
    email         varchar(255) NOT NULL UNIQUE,
    full_name     varchar(255) NOT NULL,
    department    varchar(255) NOT NULL DEFAULT 'General',
    -- ADR-068: employee | manager | vp_hr | legal_ethics — no ROOT_ADMIN
    app_role      text NOT NULL DEFAULT 'employee'
                  CHECK (app_role IN ('employee', 'manager', 'vp_hr', 'legal_ethics')),
    -- ADR-007 / Q-002: consent default FALSE
    consent_vault boolean NOT NULL DEFAULT FALSE,
    -- N-1 / N-4 revised / 051 v4: IANA timezone per employee — NOT NULL, NO DEFAULT
    -- Client auto-detects Intl zone at signup, or maps country(/region) → IANA on client.
    timezone      text NOT NULL,
    -- Optional ISO 3166-1 alpha-2; country→zone mapping is CLIENT-SIDE only (N-4 revised)
    country_code  char(2)
                  CHECK (country_code IS NULL OR country_code ~ '^[A-Z]{2}$'),
    start_date    date DEFAULT CURRENT_DATE,
    created_at    timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX IF NOT EXISTS idx_users_company_role ON users (company_id, app_role);
CREATE INDEX IF NOT EXISTS idx_users_timezone ON users (timezone);

-- N-4 revised timezone trigger (never coerces):
-- INSERT: missing/empty → timezone_required (22004); invalid → invalid_timezone (22023).
-- UPDATE OF timezone: empty → timezone_required; invalid → invalid_timezone; keep OLD on reject.
-- Omitting timezone on UPDATE does not fire this trigger (UPDATE OF timezone only).
CREATE OR REPLACE FUNCTION fn_is_valid_iana_timezone(p_tz text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  IF p_tz IS NULL OR btrim(p_tz) = '' THEN
    RETURN false;
  END IF;
  BEGIN
    PERFORM now() AT TIME ZONE p_tz;
  EXCEPTION WHEN others THEN
    RETURN false;
  END;
  RETURN EXISTS (SELECT 1 FROM pg_timezone_names t WHERE t.name = p_tz);
END;
$$;

CREATE OR REPLACE FUNCTION fn_validate_user_timezone()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_tz text;
BEGIN
  v_tz := NULLIF(btrim(COALESCE(NEW.timezone, '')), '');

  IF v_tz IS NULL THEN
    -- Missing / empty — distinct business code (N-4 revised)
    RAISE EXCEPTION 'timezone_required'
      USING ERRCODE = '22004',  -- null_value_not_allowed → map to HTTP 400
            DETAIL = 'http_hint=400;code=timezone_required',
            HINT = 'timezone_required';
  END IF;

  IF NOT fn_is_valid_iana_timezone(v_tz) THEN
    RAISE EXCEPTION 'invalid_timezone'
      USING ERRCODE = '22023',  -- invalid_parameter_value → map to HTTP 400
            DETAIL = 'http_hint=400;code=invalid_timezone',
            HINT = 'invalid_timezone';
  END IF;

  NEW.timezone := v_tz;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_timezone ON users;
CREATE TRIGGER trg_users_timezone
    BEFORE INSERT OR UPDATE OF timezone ON users
    FOR EACH ROW
    EXECUTE FUNCTION fn_validate_user_timezone();

-- ---------------------------------------------------------------------------
-- Deprivation Tax constants (Q-027 / Q-016 v3) — system-computed; NOT client-writable
-- productivity_factor = 0.12
--   Oswald, Proto & Sgroi, J. Labor Econ. 2015, doi:10.1086/681096
--   Bellet, De Neve & Ward, Management Science 70(3) 2024, doi:10.1287/mnsc.2023.4766
-- Reject 13–14% (not encoded). Reject hardcoded [rejected salary literal] (example only: 1.5×$70k).
-- Formula: deprivation_tax = annual_salary × replacement_cost_multiplier × 0.12
--          replacement_cost = annual_salary × replacement_cost_multiplier
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_chr_productivity_factor()
RETURNS numeric
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT 0.12::numeric
$$;

COMMENT ON FUNCTION fn_chr_productivity_factor() IS
  'Locked 12% happiness→productivity (Oswald 2015 doi:10.1086/681096; Bellet/De Neve/Ward 2024 doi:10.1287/mnsc.2023.4766). NOT 13–14%.';

-- Per-role replacement cost multiplier (default 1.5; range 0.5–2.0) — ADR Q-027 v3
CREATE TABLE IF NOT EXISTS role_cost_config (
    role_key                      text PRIMARY KEY
                                  CHECK (role_key IN ('employee', 'manager', 'vp_hr', 'legal_ethics')),
    replacement_cost_multiplier   numeric(4, 2) NOT NULL DEFAULT 1.50
                                  CHECK (replacement_cost_multiplier BETWEEN 0.50 AND 2.00),
    updated_at                    timestamptz NOT NULL DEFAULT clock_timestamp()
);

COMMENT ON TABLE role_cost_config IS
  'Per-role replacement_cost_multiplier. DEFAULT 1.5× annual_salary; CHECK 0.5–2.0. No hardcoded [rejected salary literal].';

INSERT INTO role_cost_config (role_key, replacement_cost_multiplier) VALUES
  ('employee', 1.50),
  ('manager', 1.50),
  ('vp_hr', 1.50),
  ('legal_ethics', 1.50)
ON CONFLICT (role_key) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 1. employee_value_asset — annual_salary input; deprivation_tax GENERATED (Q-027)
-- asset_value_capex remains optional CapEx (NOT a [rejected salary literal] default; NOT replacement cost)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS employee_value_asset (
    asset_id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                    uuid NOT NULL UNIQUE REFERENCES users(user_id) ON DELETE CASCADE,
    company_id                 uuid REFERENCES companies(company_id) ON DELETE SET NULL,
    direct_cost_opex           numeric(12, 2) NOT NULL DEFAULT 0 CHECK (direct_cost_opex >= 0),
    -- Optional CapEx placeholder — NEVER default to [rejected salary literal] (rejected by Q-027 v3)
    asset_value_capex          numeric(12, 2) CHECK (asset_value_capex IS NULL OR asset_value_capex >= 0),
    -- Input for deprivation tax (system uses this; no hardcoded salary)
    annual_salary              numeric(12, 2) CHECK (annual_salary IS NULL OR annual_salary >= 0),
    -- Role key for multiplier lookup / snapshot (synced from users.app_role by RPC)
    role_key                   text NOT NULL DEFAULT 'employee'
                               CHECK (role_key IN ('employee', 'manager', 'vp_hr', 'legal_ethics')),
    -- Snapshot of role_cost_config.multiplier (system-set; client cannot invent range)
    replacement_cost_multiplier numeric(4, 2) NOT NULL DEFAULT 1.50
                               CHECK (replacement_cost_multiplier BETWEEN 0.50 AND 2.00),
    -- GENERATED: replacement_cost = annual_salary × multiplier (NULL if no salary)
    replacement_cost           numeric(12, 2) GENERATED ALWAYS AS (
        CASE WHEN annual_salary IS NULL THEN NULL
             ELSE round(annual_salary * replacement_cost_multiplier, 2)
        END
    ) STORED,
    -- GENERATED: deprivation_tax = annual_salary × multiplier × 0.12 (Q-027; system-only)
    deprivation_tax            numeric(12, 2) GENERATED ALWAYS AS (
        CASE WHEN annual_salary IS NULL THEN NULL
             ELSE round(annual_salary * replacement_cost_multiplier * 0.12, 2)
        END
    ) STORED,
    productivity_alpha_factor  numeric(5, 4) NOT NULL DEFAULT 1.0000,
    -- TODO Q-033: happiness debt / diluted wage full formulas — open; liability placeholder
    happiness_debt_liability   numeric(12, 2) NOT NULL DEFAULT 0 CHECK (happiness_debt_liability >= 0),
    created_at                 timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at                 timestamptz NOT NULL DEFAULT clock_timestamp()
);

COMMENT ON COLUMN employee_value_asset.deprivation_tax IS
  'System GENERATED: annual_salary * replacement_cost_multiplier * 0.12. Not client-writable.';
COMMENT ON COLUMN employee_value_asset.replacement_cost IS
  'System GENERATED: annual_salary * replacement_cost_multiplier (default multiplier 1.5).';

-- ---------------------------------------------------------------------------
-- 2. anchor — client encrypts details (AES-256-GCM + PBKDF2); ciphertext only
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS anchor (
    anchor_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id            uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    lighting_type      varchar(50),
    territory_schema   varchar(50),
    exposure_gate      exposure_gate_enum NOT NULL DEFAULT 'FILTERED',
    encrypted_blob     bytea NOT NULL,
    encryption_iv      bytea NOT NULL,
    encryption_tag     bytea,
    encryption_version smallint NOT NULL DEFAULT 1,
    created_at         timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at         timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX IF NOT EXISTS idx_anchor_user ON anchor (user_id);

-- ---------------------------------------------------------------------------
-- 3. spoon_budget — 0..12; daily reset ALWAYS to 12 at employee local midnight (N-1)
-- budget_date = (now() AT TIME ZONE users.timezone)::date — not org UTC
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS spoon_budget (
    budget_id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                  uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    -- Set by RPC to employee-local date (N-1); do not rely on session CURRENT_DATE
    budget_date              date NOT NULL,
    current_spoon_count      int NOT NULL DEFAULT 12
                             CHECK (current_spoon_count BETWEEN 0 AND 12),
    daily_baseline_capacity  int NOT NULL DEFAULT 12
                             CHECK (daily_baseline_capacity = 12),
    available_capacity_pct   numeric(5, 2) GENERATED ALWAYS AS (
        (current_spoon_count::numeric / NULLIF(daily_baseline_capacity, 0)) * 100.0
    ) STORED,
    energy_state             energy_state_enum GENERATED ALWAYS AS (
        CASE
            WHEN current_spoon_count >= 6 THEN 'GREEN_OPTIMAL'::energy_state_enum
            WHEN current_spoon_count >= 3 THEN 'YELLOW_WARNING'::energy_state_enum
            ELSE 'RED_BANKRUPT'::energy_state_enum
        END
    ) STORED,
    updated_at               timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (user_id, budget_date)
);

CREATE INDEX IF NOT EXISTS idx_spoon_budget_user_date
    ON spoon_budget (user_id, budget_date DESC);

-- ---------------------------------------------------------------------------
-- 4. hrv_sample — v1 unused; CB does not read (ADR-003 → v2; 007 v2)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS hrv_sample (
    sample_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id            uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    hrv_baseline       numeric(6, 2) CHECK (hrv_baseline IS NULL OR hrv_baseline > 0),
    rmssd_ms           numeric(6, 2) CHECK (rmssd_ms IS NULL OR rmssd_ms >= 0),
    distal_skin_temp   numeric(4, 2),
    vagal_tone_index   numeric(5, 2),
    sample_timestamp   timestamptz NOT NULL DEFAULT clock_timestamp()
);

COMMENT ON TABLE hrv_sample IS
  'v1 unused; Circuit Breaker does not read HRV. Sensors deferred to v2 (Q-009).';

CREATE INDEX IF NOT EXISTS idx_hrv_user_ts
    ON hrv_sample (user_id, sample_timestamp DESC);

-- ---------------------------------------------------------------------------
-- 5. task — Task Cost Matrix 051 v4; Shadow Work flag (Q-011) — NOT entity 11
-- Farming s_base=0 (does NOT refill spoons); Fighting normal=1; high-friction=2
-- S_final=min(...,4); is_chunkable when cost>=3
-- Chronic pain: classification/pricing only — numeric formulas TODO
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS task (
    task_id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    assignee_id                    uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    assigner_id                    uuid REFERENCES users(user_id) ON DELETE SET NULL,
    task_name                      varchar(255) NOT NULL,
    task_kind                      task_kind_enum NOT NULL DEFAULT 'fighting',
    s_base                         smallint NOT NULL DEFAULT 1
                                   CHECK (s_base IN (0, 1, 2)),
    modifiers                      jsonb NOT NULL DEFAULT '[]'::jsonb,
    high_friction                  boolean NOT NULL DEFAULT false,
    -- TODO ADR-051: chronic pain numeric (NRS/VAS) formulas — open; flag only
    chronic_pain_flag              boolean NOT NULL DEFAULT false,
    s_modifier_sum                 smallint NOT NULL DEFAULT 0 CHECK (s_modifier_sum >= 0),
    s_final                        smallint GENERATED ALWAYS AS (
        LEAST(s_base + s_modifier_sum, 4)::smallint
    ) STORED,
    is_chunkable                   boolean GENERATED ALWAYS AS (
        (LEAST(s_base + s_modifier_sum, 4) >= 3)
    ) STORED,
    shadow_work_flag               boolean NOT NULL DEFAULT false,
    shadow_work_tag                varchar(64),
    pacing_status                  pacing_status_enum NOT NULL DEFAULT 'ACTIVE',
    is_blocked_by_circuit_breaker  boolean NOT NULL DEFAULT false,
    external_ref                   varchar(255),
    created_at                     timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX IF NOT EXISTS idx_task_assignee_created
    ON task (assignee_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- 6. journal_entry — ciphertext only; Shadow Work tag optional (Q-011)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS journal_entry (
    entry_id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id            uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    prompt_code        varchar(64),
    encrypted_blob     bytea NOT NULL,
    encryption_iv      bytea NOT NULL,
    encryption_tag     bytea,
    encryption_version smallint NOT NULL DEFAULT 1,
    shadow_work_flag   boolean NOT NULL DEFAULT false,
    shadow_work_tag    varchar(64),
    is_clinical        boolean NOT NULL DEFAULT false,
    created_at         timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX IF NOT EXISTS idx_journal_user_created
    ON journal_entry (user_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- 7. team_aggregate — Rule-of-5; deprivation_tax_sum = SUM(EVA.deprivation_tax) via RPC (Q-027)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS team_aggregate (
    aggregate_id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                    uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    department                varchar(100) NOT NULL,
    member_count              int NOT NULL CHECK (member_count >= 1),
    team_spoon_avg            numeric(4, 2),
    -- System-computed SUM of employee deprivation_tax (12% × salary × multiplier); N≥5 Glass Box
    deprivation_tax_sum       numeric(12, 2),
    -- TODO Q-033: happiness debt / diluted wage formulas — open (need verified source)
    happiness_debt_sum        numeric(12, 2),
    -- TODO Q-016: shadow_balance aggregate formula beyond tax sum — open
    shadow_balance_sum        numeric(12, 2),
    heat_map_bucket           varchar(32),
    -- TODO ADR-016: PSC-12 wording / frequency / storage entity open
    psc12_team_avg            numeric(5, 2),
    dichotomous_alert_level   dichotomous_alert_enum NOT NULL DEFAULT 'GREEN',
    calculated_at             timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX IF NOT EXISTS idx_team_agg_org_dept
    ON team_aggregate (org_id, department, calculated_at DESC);

-- ---------------------------------------------------------------------------
-- 8. cuckoo_alert
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cuckoo_alert (
    alert_id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    manager_id                     uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    target_user_id                 uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    org_id                         uuid REFERENCES companies(company_id) ON DELETE SET NULL,
    trigger_reason                 varchar(100) NOT NULL,
    nlp_flag_codes                 jsonb NOT NULL DEFAULT '[]'::jsonb,
    sovereign_veto_window_expiry   timestamptz NOT NULL
                                   DEFAULT (clock_timestamp() + interval '60 seconds'),
    status                         cuckoo_status_enum NOT NULL DEFAULT 'VETO_WINDOW_ACTIVE',
    -- TODO ADR Q-037: SHA-256 algorithm not locked — column holds opaque hash string
    logic_hash                     varchar(128) NOT NULL,
    created_at                     timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX IF NOT EXISTS idx_cuckoo_manager ON cuckoo_alert (manager_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_cuckoo_target ON cuckoo_alert (target_user_id, status);

-- ---------------------------------------------------------------------------
-- 9. avatar_state — separate golden_spoons + chr_coins (NO exchange, 070 v5)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS avatar_state (
    state_id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                        uuid NOT NULL UNIQUE REFERENCES users(user_id) ON DELETE CASCADE,
    role_state                     avatar_role_enum NOT NULL DEFAULT 'HOPE',
    golden_spoons                  int NOT NULL DEFAULT 0 CHECK (golden_spoons >= 0),
    chr_coins                      int NOT NULL DEFAULT 0 CHECK (chr_coins >= 0),
    shop_inventory                 jsonb NOT NULL DEFAULT '[]'::jsonb,
    shop_idempotency               jsonb NOT NULL DEFAULT '{}'::jsonb,
    -- TODO ADR Q-014: avatar weights + immunity values — open; placeholder only
    avatar_weights                 jsonb,
    -- TODO ADR-070: Contrast Nullification — open; flag retained but not locked behavior
    contrast_nullification_active  boolean NOT NULL DEFAULT false,
    bone_memory_latency_ms         int,
    updated_at                     timestamptz NOT NULL DEFAULT clock_timestamp()
);

-- ---------------------------------------------------------------------------
-- 10. manager_ledger — WORM append-only; NO free-text PII narrative (053/068)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS manager_ledger (
    ledger_id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    manager_id             uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    org_id                 uuid REFERENCES companies(company_id) ON DELETE SET NULL,
    event_type             varchar(100) NOT NULL,
    amount_a               numeric(12, 2),
    amount_b               numeric(12, 2),
    -- System-computed snapshot of subject EVA.deprivation_tax (Q-027); not client-supplied
    deprivation_tax_cost   numeric(12, 2),
    -- TODO ADR Q-037: hash algorithm (SHA-256) open — opaque string
    logic_hash             varchar(128) NOT NULL,
    previous_hash          varchar(128),
    restoration_status     varchar(100) NOT NULL DEFAULT 'Pending_Restoration',
    created_at             timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT uq_manager_ledger_logic_hash UNIQUE (logic_hash)
);

CREATE INDEX IF NOT EXISTS idx_ledger_manager_created
    ON manager_ledger (manager_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- Shop catalog (not entity 11) — EverStore N-2 / 070 v5
-- Currency: golden_spoons. Dutch auction only for event items (numerics TODO).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS shop_item_catalog (
    item_id        varchar(64) PRIMARY KEY,  -- sku
    display_name   varchar(255) NOT NULL,
    name_he        varchar(255) NOT NULL,
    tier           shop_tier_enum NOT NULL DEFAULT 'basic',
    price_coins    int,  -- locked basic=10 / advanced=20 for non-event
    currency       text NOT NULL DEFAULT 'golden_spoons'
                   CHECK (currency IN ('chr_coins', 'golden_spoons')),
    is_event       boolean NOT NULL DEFAULT false,
    cosmetic_only  boolean NOT NULL DEFAULT true,
    is_active      boolean NOT NULL DEFAULT true,
    -- TODO ADR-070: Dutch auction start/floor/step numbers — open (no event seed in v1.1)
    dutch_meta     jsonb,
    created_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT chk_regular_price CHECK (
      (is_event = false AND tier = 'basic' AND price_coins = 10)
      OR (is_event = false AND tier = 'advanced' AND price_coins = 20)
      OR (is_event = true AND tier = 'event_dutch')  -- price may be null / dynamic; TODO numbers
    ),
    CONSTRAINT chk_event_flag CHECK (
      (is_event = false AND tier IN ('basic', 'advanced'))
      OR (is_event = true AND tier = 'event_dutch')
    )
);

COMMENT ON TABLE shop_item_catalog IS
  'Server-side price lookup for rpc_everstore_purchase. N-2 catalog seed locked; Dutch event numerics TODO.';

-- N-2 locked EverStore catalog (8 cosmetic/narrative items; currency = golden_spoons)
INSERT INTO shop_item_catalog (
  item_id, display_name, name_he, tier, price_coins, currency, is_event, cosmetic_only
) VALUES
  ('theme_basement_office',       'Basement Office theme',           'רקע משרד המרתף',              'basic',    10, 'golden_spoons', false, true),
  ('theme_somatic_zone',          'Somatic regulation zone theme',   'רקע מתחם וויסות סומטי',       'basic',    10, 'golden_spoons', false, true),
  ('theme_coworking_floor',       'Co-Working floor theme',          'רקע קומת Co-Working',         'advanced', 20, 'golden_spoons', false, true),
  ('theme_penthouse',             'Penthouse theme',                 'רקע הפנטהאוז',                 'advanced', 20, 'golden_spoons', false, true),
  ('badge_passive_pilgrim',       'Passive Pilgrim badge',           'תג צליין פסיבי',              'basic',    10, 'golden_spoons', false, true),
  ('badge_corporate_cyborg',      'Corporate Cyborg badge',          'תג סייבורג תאגידי',            'advanced', 20, 'golden_spoons', false, true),
  ('badge_leading_entrepreneur',  'Leading Entrepreneur badge',      'תג יזם מוביל',                 'advanced', 20, 'golden_spoons', false, true),
  ('badge_focus_friday_noren',    'Focus Friday / Noren Pass badge', 'תג Focus Friday / Noren Pass', 'basic',    10, 'golden_spoons', false, true)
ON CONFLICT (item_id) DO UPDATE SET
  display_name  = EXCLUDED.display_name,
  name_he       = EXCLUDED.name_he,
  tier          = EXCLUDED.tier,
  price_coins   = EXCLUDED.price_coins,
  currency      = EXCLUDED.currency,
  is_event      = EXCLUDED.is_event,
  cosmetic_only = EXCLUDED.cosmetic_only,
  is_active     = true;

-- Deactivate legacy placeholders if present
UPDATE shop_item_catalog
   SET is_active = false
 WHERE item_id IN ('basic_placeholder', 'advanced_placeholder');

-- ---------------------------------------------------------------------------
-- PCQ-12 monthly reward ledger (N-3) — not entity 11; enforces once per calendar month in user TZ
-- reward_month = date_trunc('month', local_date)::date
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pcq12_monthly_reward (
    user_id                 uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    reward_month            date NOT NULL,  -- first day of calendar month in employee TZ
    golden_spoons_awarded   int NOT NULL DEFAULT 10 CHECK (golden_spoons_awarded = 10),
    awarded_at              timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (user_id, reward_month)
);

COMMENT ON TABLE pcq12_monthly_reward IS
  'N-3: PCQ-12 completion awards 10 golden spoons at most once per calendar month in employee timezone.';

CREATE INDEX IF NOT EXISTS idx_pcq12_reward_user ON pcq12_monthly_reward (user_id, reward_month DESC);

-- =============================================================================
-- Helper: business error raise (Glass Box — no spoon/HRV numbers in messages)
-- SQLSTATE 42501 (insufficient_privilege) → PostgREST HTTP 403
-- =============================================================================
CREATE OR REPLACE FUNCTION fn_raise_business(p_code text, p_http_hint int DEFAULT 403)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  -- Glass Box: NEVER interpolate spoon counts or HRV values into the message.
  -- ERRCODE 42501 maps to HTTP 403 in PostgREST; HINT/message carry business code.
  RAISE EXCEPTION '%', p_code
    USING ERRCODE = '42501',
          DETAIL = format('http_hint=%s;code=%s', p_http_hint, p_code),
          HINT = p_code;
END;
$$;

-- =============================================================================
-- Triggers: Rule of 5+, WORM ledger_immutable
-- CB / Anti-GET live in RPC. No HRV in CB.
-- =============================================================================

CREATE OR REPLACE FUNCTION enforce_rule_of_5()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.member_count < 5 THEN
    RAISE EXCEPTION 'aggregation_privacy_threshold'
      USING ERRCODE = '42501',
            DETAIL = 'http_hint=403;code=aggregation_privacy_threshold',
            HINT = 'aggregation_privacy_threshold';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_rule_of_5 ON team_aggregate;
CREATE TRIGGER trg_enforce_rule_of_5
    BEFORE INSERT OR UPDATE OF member_count ON team_aggregate
    FOR EACH ROW
    EXECUTE FUNCTION enforce_rule_of_5();

-- WORM: ledger_immutable → HTTP 403 (N-1–N-3 API v2 / Q-029)
CREATE OR REPLACE FUNCTION fn_ledger_immutable()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'ledger_immutable'
    USING ERRCODE = '42501',
          DETAIL = 'http_hint=403;code=ledger_immutable',
          HINT = 'ledger_immutable';
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_manager_ledger_worm ON manager_ledger;
CREATE TRIGGER trg_manager_ledger_worm
    BEFORE UPDATE OR DELETE ON manager_ledger
    FOR EACH ROW
    EXECUTE FUNCTION fn_ledger_immutable();

-- =============================================================================
-- fn_is_org_manager — SECURITY DEFINER; roles per ADR-068
-- =============================================================================
CREATE OR REPLACE FUNCTION fn_is_org_manager(p_org_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM users u
     WHERE u.user_id = auth.uid()
       AND u.company_id = p_org_id
       AND u.app_role IN ('manager', 'vp_hr')
  );
$$;

REVOKE ALL ON FUNCTION fn_is_org_manager(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_is_org_manager(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION fn_app_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT u.app_role FROM users u WHERE u.user_id = auth.uid()
$$;

REVOKE ALL ON FUNCTION fn_app_role() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_app_role() TO authenticated;

CREATE OR REPLACE FUNCTION fn_has_vault_consent(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT COALESCE((SELECT consent_vault FROM users WHERE user_id = p_user_id), false)
$$;

-- N-1 helpers: employee-local date from IANA timezone
CREATE OR REPLACE FUNCTION fn_user_timezone(p_user_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT u.timezone FROM users u WHERE u.user_id = p_user_id
$$;

CREATE OR REPLACE FUNCTION fn_user_local_date(p_user_id uuid)
RETURNS date
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT (clock_timestamp() AT TIME ZONE u.timezone)::date
    FROM users u
   WHERE u.user_id = p_user_id
$$;

CREATE OR REPLACE FUNCTION fn_user_local_month_start(p_user_id uuid)
RETURNS date
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT date_trunc('month', (clock_timestamp() AT TIME ZONE u.timezone)::timestamp)::date
    FROM users u
   WHERE u.user_id = p_user_id
$$;

REVOKE ALL ON FUNCTION fn_user_timezone(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_user_local_date(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_user_local_month_start(uuid) FROM PUBLIC;

-- =============================================================================
-- RLS + FORCE RLS + grants
-- Writes via RPC; reads via PostgREST.
-- =============================================================================
ALTER TABLE employee_value_asset ENABLE ROW LEVEL SECURITY;
ALTER TABLE anchor               ENABLE ROW LEVEL SECURITY;
ALTER TABLE spoon_budget         ENABLE ROW LEVEL SECURITY;
ALTER TABLE hrv_sample           ENABLE ROW LEVEL SECURITY;
ALTER TABLE task                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_entry        ENABLE ROW LEVEL SECURITY;
ALTER TABLE team_aggregate       ENABLE ROW LEVEL SECURITY;
ALTER TABLE cuckoo_alert         ENABLE ROW LEVEL SECURITY;
ALTER TABLE avatar_state         ENABLE ROW LEVEL SECURITY;
ALTER TABLE manager_ledger       ENABLE ROW LEVEL SECURITY;
ALTER TABLE shop_item_catalog    ENABLE ROW LEVEL SECURITY;
ALTER TABLE pcq12_monthly_reward ENABLE ROW LEVEL SECURITY;
ALTER TABLE role_cost_config     ENABLE ROW LEVEL SECURITY;
ALTER TABLE companies            ENABLE ROW LEVEL SECURITY;
ALTER TABLE users                ENABLE ROW LEVEL SECURITY;

ALTER TABLE employee_value_asset FORCE ROW LEVEL SECURITY;
ALTER TABLE anchor               FORCE ROW LEVEL SECURITY;
ALTER TABLE spoon_budget         FORCE ROW LEVEL SECURITY;
ALTER TABLE hrv_sample           FORCE ROW LEVEL SECURITY;
ALTER TABLE task                 FORCE ROW LEVEL SECURITY;
ALTER TABLE journal_entry        FORCE ROW LEVEL SECURITY;
ALTER TABLE team_aggregate       FORCE ROW LEVEL SECURITY;
ALTER TABLE cuckoo_alert         FORCE ROW LEVEL SECURITY;
ALTER TABLE avatar_state         FORCE ROW LEVEL SECURITY;
ALTER TABLE manager_ledger       FORCE ROW LEVEL SECURITY;
ALTER TABLE shop_item_catalog    FORCE ROW LEVEL SECURITY;
ALTER TABLE pcq12_monthly_reward FORCE ROW LEVEL SECURITY;
ALTER TABLE role_cost_config     FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE team_aggregate FROM PUBLIC, anon;
REVOKE ALL ON TABLE manager_ledger FROM PUBLIC, anon;
REVOKE ALL ON TABLE users FROM PUBLIC, anon;
REVOKE ALL ON TABLE companies FROM PUBLIC, anon;
REVOKE SELECT ON TABLE users FROM authenticated;

GRANT SELECT ON TABLE spoon_budget TO authenticated;
GRANT SELECT ON TABLE task TO authenticated;
GRANT SELECT ON TABLE avatar_state TO authenticated;
GRANT SELECT ON TABLE employee_value_asset TO authenticated;
GRANT SELECT ON TABLE cuckoo_alert TO authenticated;
GRANT SELECT ON TABLE shop_item_catalog TO authenticated;
GRANT SELECT ON TABLE role_cost_config TO authenticated;
GRANT SELECT ON TABLE journal_entry TO authenticated;
GRANT SELECT ON TABLE anchor TO authenticated;
GRANT SELECT ON TABLE hrv_sample TO authenticated;
GRANT SELECT ON TABLE team_aggregate TO authenticated;
GRANT SELECT ON TABLE pcq12_monthly_reward TO authenticated;

REVOKE ALL ON TABLE manager_ledger FROM authenticated;
GRANT SELECT, INSERT ON TABLE manager_ledger TO authenticated;
REVOKE UPDATE, DELETE, TRUNCATE ON TABLE manager_ledger FROM authenticated;
REVOKE UPDATE, DELETE ON TABLE manager_ledger FROM PUBLIC;

DROP POLICY IF EXISTS spoon_budget_private_vault ON spoon_budget;
CREATE POLICY spoon_budget_private_vault ON spoon_budget
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS hrv_sample_private_vault ON hrv_sample;
CREATE POLICY hrv_sample_private_vault ON hrv_sample
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS avatar_state_private_vault ON avatar_state;
CREATE POLICY avatar_state_private_vault ON avatar_state
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS employee_value_asset_own ON employee_value_asset;
CREATE POLICY employee_value_asset_own ON employee_value_asset
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS task_assignee_own ON task;
CREATE POLICY task_assignee_own ON task
    FOR SELECT TO authenticated
    USING (auth.uid() = assignee_id OR auth.uid() = assigner_id);

DROP POLICY IF EXISTS journal_entry_consent_vault ON journal_entry;
CREATE POLICY journal_entry_consent_vault ON journal_entry
    FOR SELECT TO authenticated
    USING (
        auth.uid() = user_id
        AND fn_has_vault_consent(user_id)
    );

DROP POLICY IF EXISTS anchor_consent_vault ON anchor;
CREATE POLICY anchor_consent_vault ON anchor
    FOR SELECT TO authenticated
    USING (
        auth.uid() = user_id
        AND fn_has_vault_consent(user_id)
    );

DROP POLICY IF EXISTS team_aggregate_manager_select ON team_aggregate;
CREATE POLICY team_aggregate_manager_select ON team_aggregate
    FOR SELECT TO authenticated
    USING (
        member_count >= 5
        AND fn_is_org_manager(org_id)
    );

DROP POLICY IF EXISTS manager_ledger_select_own ON manager_ledger;
CREATE POLICY manager_ledger_select_own ON manager_ledger
    FOR SELECT TO authenticated
    USING (auth.uid() = manager_id);

DROP POLICY IF EXISTS manager_ledger_insert_own ON manager_ledger;
CREATE POLICY manager_ledger_insert_own ON manager_ledger
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = manager_id);

DROP POLICY IF EXISTS cuckoo_select ON cuckoo_alert;
CREATE POLICY cuckoo_select ON cuckoo_alert
    FOR SELECT TO authenticated
    USING (auth.uid() = manager_id OR auth.uid() = target_user_id);

DROP POLICY IF EXISTS shop_catalog_select ON shop_item_catalog;
CREATE POLICY shop_catalog_select ON shop_item_catalog
    FOR SELECT TO authenticated
    USING (is_active = true);

DROP POLICY IF EXISTS pcq12_reward_own ON pcq12_monthly_reward;
CREATE POLICY pcq12_reward_own ON pcq12_monthly_reward
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS role_cost_config_select ON role_cost_config;
CREATE POLICY role_cost_config_select ON role_cost_config
    FOR SELECT TO authenticated
    USING (true);
