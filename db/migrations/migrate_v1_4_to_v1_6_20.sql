-- =============================================================================
-- CHR-ETRS MVP · migrations/migrate_v1_4_to_v1_6_20.sql
-- Version: 1.6.20-mvp r1 (2026-10-31; r1 = J-96 A) — supersedes migrate_v1_4_to_v1_6_19.sql (1.6.19-mvp, 2026-10-31), migrate_v1_4_to_v1_6_18.sql (1.6.18-mvp, 2026-10-31),
--          migrate_v1_4_to_v1_6_17.sql (1.6.17-mvp, 2026-10-31),
--          migrate_v1_4_to_v1_6_16.sql (1.6.16-mvp, 2026-10-30) and
--          migrate_v1_4_to_v1_6_13.sql (1.6.13-mvp, 2026-10-25).
-- v1.6.20: same steps; the pack it installs is v1.6.20 (adds the 'ללא מחלקה' absence row, J-92).
-- v1.6.20-r1 (J-96 = A): users.department_is_default added (false for every existing row — an existing 'General'
--   is not proven defaulted, J-101); the report counts them as users.general_department_ambiguous.
-- v1.6.19: same steps; the pack it installs is v1.6.19 (leaver batching of 10, aggregate leaver list, A-3
--          3-month ILS estimate, computed verification levels + 'תיק אימות', pay linkage, social events, report
--          layers + governance, the 5 sources). The pack's upgrade blocks also upgrade a v1.6.18 database in
--          place (run this same file on it; existing un-batched leavers form a first batch once ≥ 10).
--          File name and backup prefix change only.
-- v1.6.18: same steps; the pack it installs is v1.6.18 (A-12 per-transfer remediation attribution + net
--          reversal, A-13 cancel / refund of time benefits scheduled after exit, A-14 questionnaire Golden
--          Spoons per company 1–20, vp_hr only, history + submission snapshot). The pack's upgrade blocks also
--          upgrade a v1.6.17 database in place (run this same file on it). File name and backup prefix change only.
-- v1.6.17: same steps; the pack it installs is v1.6.17 (Cantril monthly 10, TPS-12 / IHS 10, J-15 guard,
--          A-8 leaver_reversal + happiness_debt_leaver_link). File name and backup prefix change only.
-- v1.6.16: same steps; the pack it installs is v1.6.16 (agents section, agent_settings, conversion blocked,
--          participation rewards); the users.app_role list gains 'cfo'.
--          (1.6.9-mvp, 2026-10-21), migrate_v1_4_to_v1_6_8.sql (1.6.8-mvp, 2026-10-21) and
--          migrate_v1_4_to_v1_6_7.sql (1.6.7-mvp, 2026-10-20).
--   Upgrades a v1.4 database (real v1.4 structure: Drive schema.20261013.sql + v1.4 rpc.sql, see
--   tests/fixtures/) to the v1.6.20 pack in ONE transaction.
-- New in 1.6.10 (Chief of Drive 21.10):
--   * timezone preflight (migrations/preflight_tz.sql): the source DB zone (SHOW timezone) must be UTC,
--     else the run STOPS unless -v source_tz=<zone> (runner --source-tz <zone>) is given; the trust rule
--     then compares dates in that zone. Users created within 1 hour of local midnight are audited
--     'tz_edge_review' (flag only, no behaviour change).
--   * after apply the runner installs the event-trigger guard, or — when refused (no superuser, e.g.
--     managed Supabase) — the ownership/REVOKE fallback (migrations/legacy_lockdown_fallback.sql).
-- New in 1.6.9 (Chief of Drive 21.10): O-50 — hire_date is the single source and users.start_date becomes
--   the generated read-only alias (schema fn_users_merge_start_date). The v1.4 start_date is copied into
--   hire_date UNLESS it equals the record's creation date (v1.4 users.created_at, date portion in UTC —
--   v1.6.10: in the preflight zone):
--   then it is unknown → hire_date NULL (TPS wait exempt), audited 'start_date_untrusted'.
--   After a successful apply the runner installs the superuser event trigger that blocks DROP / ALTER of
--   legacy_v1_4_* tables (migrations/legacy_ddl_guard.sql).
-- New in 1.6.8: hire_date ← v1.4 start_date (the only v1.4 employment-start field); team_joined_at
--   stays NULL (v1.4 has no team-join field; the 1.6.7 start_date / migration-day fallback is removed)
--   → TPS wait source audited per user (team_join / hire / exempt); v1.4 spoon days marked
--   row_source = 'legacy_v1_4' (reported_at unknown); legacy_v1_4_* tables read-only (trigger + no
--   write grants, schema fn_legacy_guard_all).
--
-- Usage (psql, run from the pack root or anywhere — paths are relative to this file):
--   apply   : psql -d <db> -v ON_ERROR_STOP=1 -f migrations/migrate_v1_4_to_v1_6_20.sql
--   dry run : psql -d <db> -v ON_ERROR_STOP=1 -v dry_run=1 -f migrations/migrate_v1_4_to_v1_6_20.sql
--             (prints the counts, then ROLLBACK — nothing is changed)
--   non-UTC source zone: add -v source_tz=<zone>   (runner: --source-tz <zone>)
--   runner  : migrations/run_migration.sh [--source-tz <zone>] {dry-run|apply|guard|rollback} <db>
--             (apply takes a backup first)
--
-- Scope (Karin 20.10): users, spoons history, projects (legacy → is_core = false) and company settings
-- (country / CLDR backfill, needs_review flags, reminder hold) — reusing the pack's backfill functions.
-- Idempotent: every step is conditional; a second run changes nothing (counts all 0).
-- On a v1.4 database the whole v1.4 code layer (public functions, triggers, RLS policies) is dropped
-- first and recreated by the v1.6.20 schema + rpc (step 1).
--
-- What happens to v1.4 tables whose 1.6.x structure is incompatible and that are OUT of scope
-- (team_aggregate, employee_value_asset, manager_ledger, cuckoo_alert, shop_item_catalog,
-- pcq12_monthly_reward, role_cost_config): they are NOT dropped and NOT converted. Each is frozen
-- and renamed legacy_v1_4_<name> (rows kept; triggers / policies removed; no client access; v1.6.8:
-- READ-ONLY for every role via trg_legacy_read_only_* and NEVER dropped — Chief of Drive 21.10, O-45)
-- and the 1.6.13 table is created empty.
--
-- ROLLBACK SECTION
--   1. Any error → the whole migration rolls back automatically (single transaction, ON_ERROR_STOP).
--   2. Dry run → always ROLLBACK.
--   3. After a successful apply: restore the pre-migration backup. run_migration.sh apply writes
--      migrations/backups/<db>_pre_v1_6_20_<timestamp>.dump (pg_dump -Fc) BEFORE migrating, and
--      run_migration.sh rollback <db> restores the newest one (drop + recreate + pg_restore).
--      Manually: dropdb <db> && createdb <db> && pg_restore -d <db> <dump>.
--   There is no in-place "down" script: the upgrade renames / reshapes tables and replaces every
--   function, so restoring the backup is the only exact rollback.
-- =============================================================================
\set ON_ERROR_STOP on
\if :{?dry_run}
\else
\set dry_run 0
\endif
BEGIN;
CREATE TEMP TABLE mig_report (step text PRIMARY KEY, n bigint NOT NULL DEFAULT 0) ON COMMIT DROP;
CREATE TEMP TABLE mig_before (k text PRIMARY KEY, n bigint NOT NULL) ON COMMIT DROP;

-- Count helper for the report (temp, never persisted).
CREATE FUNCTION pg_temp.mig_add(p_step text, p_n bigint) RETURNS void LANGUAGE sql AS $$
  INSERT INTO mig_report (step, n) VALUES (p_step, p_n) ON CONFLICT (step) DO UPDATE SET n = mig_report.n + EXCLUDED.n $$;
-- Does a column exist (public schema)?
CREATE FUNCTION pg_temp.mig_has_col(p_table text, p_col text) RETURNS boolean LANGUAGE sql AS $$
  SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = p_table AND column_name = p_col) $$;
-- Does a table exist (public schema)?
CREATE FUNCTION pg_temp.mig_has_table(p_table text) RETURNS boolean LANGUAGE sql AS $$
  SELECT to_regclass('public.' || p_table) IS NOT NULL $$;
-- Rows of a table (0 when missing).
CREATE FUNCTION pg_temp.mig_rows(p_table text) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v bigint := 0;
BEGIN
  IF pg_temp.mig_has_table(p_table) THEN EXECUTE format('SELECT count(*) FROM %I', p_table) INTO v; END IF;
  RETURN v;
END $$;
-- Freeze an out-of-scope v1.4 table under legacy_v1_4_<name>: drop its triggers + policies, rename its
-- indexes and CHECK / FK constraints, revoke client access, keep every row. Returns the rows kept.
CREATE FUNCTION pg_temp.mig_freeze_legacy(p_table text) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE r record; v_new text := 'legacy_v1_4_' || p_table; v_n bigint;
BEGIN
  v_n := pg_temp.mig_rows(p_table);
  FOR r IN SELECT tgname FROM pg_trigger WHERE tgrelid = ('public.' || p_table)::regclass AND NOT tgisinternal LOOP
    EXECUTE format('DROP TRIGGER %I ON %I', r.tgname, p_table);
  END LOOP;
  FOR r IN SELECT polname FROM pg_policy WHERE polrelid = ('public.' || p_table)::regclass LOOP
    EXECUTE format('DROP POLICY %I ON %I', r.polname, p_table);
  END LOOP;
  FOR r IN SELECT c.relname FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid WHERE i.indrelid = ('public.' || p_table)::regclass LOOP
    EXECUTE format('ALTER INDEX %I RENAME TO %I', r.relname, left('legacy_v1_4_' || r.relname, 63));
  END LOOP;
  FOR r IN SELECT conname FROM pg_constraint WHERE conrelid = ('public.' || p_table)::regclass AND contype IN ('c', 'f') LOOP
    EXECUTE format('ALTER TABLE %I RENAME CONSTRAINT %I TO %I', p_table, r.conname, left('legacy_v1_4_' || r.conname, 63));
  END LOOP;
  EXECUTE format('ALTER TABLE %I RENAME TO %I', p_table, v_new);
  EXECUTE format('REVOKE ALL ON TABLE %I FROM PUBLIC', v_new);
  FOR r IN SELECT rolname FROM pg_roles WHERE rolname IN ('anon', 'authenticated', 'service_role') LOOP
    EXECUTE format('REVOKE ALL ON TABLE %I FROM %I', v_new, r.rolname);
  END LOOP;
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', v_new);
  EXECUTE format('COMMENT ON TABLE %I IS %L', v_new, 'v1.4 rows kept by the v1.6.7+ migration; frozen and read-only, never dropped (Chief of Drive 21.10, O-45)');
  RETURN v_n;
END $$;

-- ---------------------------------------------------------------------------
-- 0. Guard: must be a CHR-ETRS database (v1.4, or already migrated → steps become no-ops).
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT pg_temp.mig_has_table('users') OR NOT pg_temp.mig_has_table('companies') THEN
    RAISE EXCEPTION 'not a CHR-ETRS database (users / companies missing)';
  END IF;
END $$;
-- v1.6.10 (rule 4): source timezone preflight — stops on a non-UTC source without -v source_tz.
\ir preflight_tz.sql
-- State before this run (for "counts of THIS run"); dynamic because v1.4 lacks these objects.
CREATE FUNCTION pg_temp.mig_count(p_sql text) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v bigint; BEGIN EXECUTE p_sql INTO v; RETURN COALESCE(v, 0); END $$;
DO $$
BEGIN
  INSERT INTO mig_before VALUES
    ('autofill', CASE WHEN pg_temp.mig_has_table('access_audit_log') THEN pg_temp.mig_count(
        $q$SELECT count(*) FROM access_audit_log WHERE action = 'company_calendar_autofill'$q$) ELSE 0 END),
    ('on_hold', CASE WHEN pg_temp.mig_has_col('companies', 'reminders_on_hold') THEN pg_temp.mig_count(
        'SELECT count(*) FROM companies WHERE reminders_on_hold') ELSE 0 END),
    ('needs_review', CASE WHEN pg_temp.mig_has_col('companies', 'timezone_status') THEN pg_temp.mig_count(
        $q$SELECT count(*) FROM companies WHERE timezone_status = 'needs_review'$q$) ELSE 0 END),
    ('project_legacy', CASE WHEN pg_temp.mig_has_col('project', 'is_core') THEN pg_temp.mig_count(
        'SELECT count(*) FROM project WHERE is_core IS NULL') ELSE 0 END);
  -- v1.6.8: TPS wait-source audit rows per source, and legacy tables already read-only
  INSERT INTO mig_before SELECT 'tps_' || x.src, CASE WHEN pg_temp.mig_has_table('access_audit_log') THEN pg_temp.mig_count(format(
        $q$SELECT count(*) FROM access_audit_log WHERE action = 'tps_wait_source' AND scope->>'source' = %L$q$, x.src)) ELSE 0 END
    FROM unnest(ARRAY['team_join', 'hire', 'exempt']) x(src);
  INSERT INTO mig_before VALUES ('legacy_guarded', (SELECT count(*) FROM pg_trigger WHERE tgname = 'trg_legacy_read_only_row'));
  -- v1.6.9 (O-50): is start_date still a plain column (→ merged by the schema in this run)? hire dates set,
  -- untrusted start dates audited so far
  INSERT INTO mig_before VALUES
    ('start_date_plain', (SELECT count(*) FROM pg_attribute WHERE attrelid = 'public.users'::regclass
                           AND attname = 'start_date' AND NOT attisdropped AND attgenerated = '')),
    ('hire_set', CASE WHEN pg_temp.mig_has_col('users', 'hire_date') THEN pg_temp.mig_count(
        'SELECT count(*) FROM users WHERE hire_date IS NOT NULL') ELSE 0 END),
    ('untrusted', CASE WHEN pg_temp.mig_has_table('access_audit_log') THEN pg_temp.mig_count(
        $q$SELECT count(*) FROM access_audit_log WHERE action = 'start_date_untrusted'$q$) ELSE 0 END),
    -- v1.6.10: users flagged near local midnight so far
    ('tz_edge', CASE WHEN pg_temp.mig_has_table('access_audit_log') THEN pg_temp.mig_count(
        $q$SELECT count(*) FROM access_audit_log WHERE action = 'tz_edge_review'$q$) ELSE 0 END);
END $$;

-- ---------------------------------------------------------------------------
-- 1. PRE (v1.4 shapes only): users, spoons history, golden spoons, out-of-scope tables.
-- ---------------------------------------------------------------------------
-- Drop the v1.4 code layer (only on a v1.4 database): every public function (not extension-owned), trigger and RLS policy.
-- Nothing else depends on them (checked: no column default / view / generated column uses a public
-- function in v1.4); the pack schema + rpc recreate the complete code layer. Returns objects dropped.
CREATE FUNCTION pg_temp.mig_drop_v1_4_code() RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE r record; v_n bigint := 0;
BEGIN
  FOR r IN SELECT t.tgname, c.relname FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND NOT t.tgisinternal LOOP
    EXECUTE format('DROP TRIGGER %I ON public.%I', r.tgname, r.relname); v_n := v_n + 1;
  END LOOP;
  FOR r IN SELECT p.polname, c.relname FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' LOOP
    EXECUTE format('DROP POLICY %I ON public.%I', r.polname, r.relname); v_n := v_n + 1;
  END LOOP;
  FOR r IN SELECT p.oid::regprocedure AS f FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND p.prokind IN ('f', 'p')
              AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e') LOOP
    EXECUTE format('DROP FUNCTION %s', r.f); v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END $$;

DO $$
BEGIN
  -- v1.4 detected by users.manager_id (renamed in v1.6.1): replace the whole code layer
  IF pg_temp.mig_has_col('users', 'manager_id') THEN
    PERFORM pg_temp.mig_add('code.v1_4_objects_replaced', pg_temp.mig_drop_v1_4_code());
  END IF;
  -- users: v1.6.1 renamed manager_id → reports_to (solid line). Values kept.
  IF pg_temp.mig_has_col('users', 'manager_id') AND NOT pg_temp.mig_has_col('users', 'reports_to') THEN
    PERFORM pg_temp.mig_add('users.manager_id_to_reports_to', (SELECT count(*) FROM users WHERE manager_id IS NOT NULL));
    ALTER TABLE users RENAME COLUMN manager_id TO reports_to;
    ALTER TABLE users RENAME CONSTRAINT users_manager_id_fkey TO users_reports_to_fkey;
  END IF;
  IF NOT pg_temp.mig_has_col('users', 'org_role_code') THEN
    PERFORM pg_temp.mig_add('users.org_role_needs_review', (SELECT count(*) FROM users WHERE app_role <> 'employee'));
    PERFORM pg_temp.mig_add('users.migrated', (SELECT count(*) FROM users));
  END IF;
  ALTER TABLE users ADD COLUMN IF NOT EXISTS dotted_line_to uuid;
  ALTER TABLE users ADD COLUMN IF NOT EXISTS org_role_code text DEFAULT 'employee';
  ALTER TABLE users ADD COLUMN IF NOT EXISTS phone varchar(32);
  ALTER TABLE users ADD COLUMN IF NOT EXISTS last_location text;
  ALTER TABLE users ADD COLUMN IF NOT EXISTS has_employee_profile boolean NOT NULL DEFAULT true;
  ALTER TABLE users ADD COLUMN IF NOT EXISTS employment_ended_at timestamptz;
  ALTER TABLE users ADD COLUMN IF NOT EXISTS display_pseudonym varchar(64);
  -- v1.6.8 (O-49): team_joined_at stays NULL — v1.4 has no team-join field (none is invented).
  ALTER TABLE users ADD COLUMN IF NOT EXISTS team_joined_at timestamptz;
  -- v1.6.8 (O-49) / v1.6.9 (O-50): hire_date ← v1.4 start_date (the only v1.4 employment-start field).
  -- Only the column is added here; the schema's fn_users_merge_start_date copies trusted values (v1.4
  -- DEFAULT CURRENT_DATE → a start_date equal to the creation date is untrusted) and turns start_date
  -- into the generated alias.
  ALTER TABLE users ADD COLUMN IF NOT EXISTS hire_date date;

  -- spoons history: rows kept; v1.4 generated energy_state / available_capacity_pct replaced by the
  -- v1.6 generated day_status (same count → status); reported_at unknown for v1.4 days (NULL).
  IF pg_temp.mig_has_col('spoon_budget', 'energy_state') THEN
    PERFORM pg_temp.mig_add('spoon_budget.rows_kept', (SELECT count(*) FROM spoon_budget));
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'day_status_enum') THEN
      CREATE TYPE day_status_enum AS ENUM ('OPEN', 'FIGHTING_BLOCKED', 'GO_HOME');
    END IF;
    ALTER TABLE spoon_budget DROP COLUMN energy_state, DROP COLUMN available_capacity_pct;
    ALTER TABLE spoon_budget ADD COLUMN day_status day_status_enum GENERATED ALWAYS AS (
        CASE
            WHEN current_spoon_count <= 3 THEN 'GO_HOME'::day_status_enum
            WHEN current_spoon_count <= 5 THEN 'FIGHTING_BLOCKED'::day_status_enum
            ELSE 'OPEN'::day_status_enum
        END
    ) STORED;
    ALTER TABLE spoon_budget ADD COLUMN IF NOT EXISTS reported_at timestamptz;
    -- v1.6.8 (O-48): mark the v1.4 days — their empty reported_at means "unknown", not "did not report"
    ALTER TABLE spoon_budget ADD COLUMN row_source text NOT NULL DEFAULT 'legacy_v1_4';
    ALTER TABLE spoon_budget ALTER COLUMN row_source SET DEFAULT 'app';
    PERFORM pg_temp.mig_add('spoon_budget.marked_legacy_v1_4', (SELECT count(*) FROM spoon_budget WHERE row_source = 'legacy_v1_4'));
    DROP TYPE IF EXISTS energy_state_enum;
  END IF;

  -- golden spoons became fractional in v1.5 (numeric(10,1)); integer values convert losslessly.
  IF (SELECT data_type FROM information_schema.columns WHERE table_name = 'avatar_state' AND column_name = 'golden_spoons') = 'integer' THEN
    PERFORM pg_temp.mig_add('avatar_state.golden_spoons_to_numeric', (SELECT count(*) FROM avatar_state));
    ALTER TABLE avatar_state ALTER COLUMN golden_spoons TYPE numeric(10, 1);
  END IF;

  -- out of scope, incompatible v1.4 shapes → frozen legacy copies (rows kept)
  IF pg_temp.mig_has_col('team_aggregate', 'member_count') THEN
    PERFORM pg_temp.mig_add('legacy.team_aggregate', pg_temp.mig_freeze_legacy('team_aggregate')); END IF;
  IF pg_temp.mig_has_col('employee_value_asset', 'role_key') THEN
    PERFORM pg_temp.mig_add('legacy.employee_value_asset', pg_temp.mig_freeze_legacy('employee_value_asset')); END IF;
  IF pg_temp.mig_has_col('manager_ledger', 'logic_hash') THEN
    PERFORM pg_temp.mig_add('legacy.manager_ledger', pg_temp.mig_freeze_legacy('manager_ledger')); END IF;
  IF pg_temp.mig_has_table('cuckoo_alert') AND NOT pg_temp.mig_has_col('cuckoo_alert', 'target_pseudonym') THEN
    PERFORM pg_temp.mig_add('legacy.cuckoo_alert', pg_temp.mig_freeze_legacy('cuckoo_alert')); END IF;
  IF pg_temp.mig_has_col('shop_item_catalog', 'is_event') THEN
    PERFORM pg_temp.mig_add('legacy.shop_item_catalog', pg_temp.mig_freeze_legacy('shop_item_catalog')); END IF;
  IF pg_temp.mig_has_table('pcq12_monthly_reward') THEN
    PERFORM pg_temp.mig_add('legacy.pcq12_monthly_reward', pg_temp.mig_freeze_legacy('pcq12_monthly_reward')); END IF;
  IF pg_temp.mig_has_table('role_cost_config') THEN
    PERFORM pg_temp.mig_add('legacy.role_cost_config', pg_temp.mig_freeze_legacy('role_cost_config')); END IF;
  IF EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid WHERE t.typname = 'shop_tier_enum' AND e.enumlabel = 'event_dutch') THEN
    ALTER TYPE shop_tier_enum RENAME TO legacy_v1_4_shop_tier_enum;
  END IF;
END $$;

-- Projects did not exist in v1.4 (the table is created by the schema); a later database's legacy
-- rows without a core choice are set non-core by fn_migrate_project_is_core (schema).
SELECT pg_temp.mig_add('project.legacy_set_non_core', (SELECT n FROM mig_before WHERE k = 'project_legacy'));

-- ---------------------------------------------------------------------------
-- 2. The v1.6.20 pack (idempotent): CLDR / tz reference, schema, RPCs. The schema runs the
--    project is_core migration, the company calendar backfill (holds / needs_review), the start_date →
--    hire_date merge (O-50), the TPS wait-source audit backfill and the legacy read-only guard.
-- ---------------------------------------------------------------------------
\ir ../ref_country_calendar.sql
\ir ../schema.sql
\ir ../rpc.sql

-- ---------------------------------------------------------------------------
-- 3. POST: user fields that need 1.6.x functions; constraints the skipped CREATE TABLE carried.
-- ---------------------------------------------------------------------------
DO $$
DECLARE r record; v_n int := 0;
BEGIN
  -- system pseudonym (lock #8) for every user without one; the immutability trigger is paused for this
  IF EXISTS (SELECT 1 FROM users WHERE display_pseudonym IS NULL) THEN
    ALTER TABLE users DISABLE TRIGGER trg_users_pseudonym;
    FOR r IN SELECT user_id, company_id FROM users WHERE display_pseudonym IS NULL ORDER BY created_at, user_id LOOP
      UPDATE users SET display_pseudonym = fn_generate_pseudonym(r.company_id) WHERE user_id = r.user_id;
      v_n := v_n + 1;
    END LOOP;
    ALTER TABLE users ENABLE TRIGGER trg_users_pseudonym;
    PERFORM pg_temp.mig_add('users.pseudonym_assigned', v_n);
  END IF;
  -- v1.6.8 (O-49): no team_joined_at fallback any more (1.6.7 used start_date / the migration day)
END $$;

-- users: the 1.6.x column rules (NOT NULL / FK / CHECK) for the columns added above.
DO $$
BEGIN
  ALTER TABLE users ALTER COLUMN display_pseudonym SET NOT NULL;
  ALTER TABLE users ALTER COLUMN org_role_code SET NOT NULL;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_org_role_code_fkey') THEN
    ALTER TABLE users ADD CONSTRAINT users_org_role_code_fkey FOREIGN KEY (org_role_code) REFERENCES org_role(role_code);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_dotted_line_to_fkey') THEN
    ALTER TABLE users ADD CONSTRAINT users_dotted_line_to_fkey FOREIGN KEY (dotted_line_to) REFERENCES users(user_id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_last_location_check') THEN
    ALTER TABLE users ADD CONSTRAINT users_last_location_check
      CHECK (last_location IS NULL OR last_location IN ('home', 'office', 'site'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_users_not_self_manager') THEN
    ALTER TABLE users ADD CONSTRAINT chk_users_not_self_manager
      CHECK (reports_to IS DISTINCT FROM user_id AND dotted_line_to IS DISTINCT FROM user_id);
  END IF;
  -- v1.6.16: the list gains 'cfo' (agents: finance viewer) — same order as schema.sql
  IF pg_get_constraintdef((SELECT oid FROM pg_constraint WHERE conname = 'users_app_role_check')) NOT LIKE '%''cfo''%' THEN
    ALTER TABLE users DROP CONSTRAINT users_app_role_check;
    ALTER TABLE users ADD CONSTRAINT users_app_role_check CHECK (app_role IN ('employee', 'manager', 'vp_hr', 'legal_ethics',
                                                                              'board_chair', 'board_member', 'owner_shareholder', 'cfo'));
  END IF;
END $$;

-- company calendar: counts of this run (the schema already ran fn_backfill_company_calendar)
SELECT pg_temp.mig_add('companies.values_autofilled',
  (SELECT count(*) FROM access_audit_log WHERE action = 'company_calendar_autofill') - (SELECT n FROM mig_before WHERE k = 'autofill'));
SELECT pg_temp.mig_add('companies.reminders_on_hold_no_country',
  (SELECT count(*) FROM companies WHERE reminders_on_hold) - (SELECT n FROM mig_before WHERE k = 'on_hold'));
-- v1.6.8: TPS wait source audited per user in this run (by source); legacy tables made read-only
SELECT pg_temp.mig_add('users.tps_wait_' || x.src,
  (SELECT count(*) FROM access_audit_log WHERE action = 'tps_wait_source' AND scope->>'source' = x.src)
  - (SELECT n FROM mig_before WHERE k = 'tps_' || x.src))
  FROM unnest(ARRAY['team_join', 'hire', 'exempt']) x(src);
-- v1.6.9 (O-50): hire dates taken from v1.4 start_date, untrusted ones (= creation date), still missing
SELECT pg_temp.mig_add('users.hire_date_from_v1_4_start_date',
  (SELECT count(*) FROM users WHERE hire_date IS NOT NULL) - (SELECT n FROM mig_before WHERE k = 'hire_set'));
SELECT pg_temp.mig_add('users.start_date_untrusted',
  (SELECT count(*) FROM access_audit_log WHERE action = 'start_date_untrusted') - (SELECT n FROM mig_before WHERE k = 'untrusted'));
SELECT pg_temp.mig_add('users.tz_edge_review',
  (SELECT count(*) FROM access_audit_log WHERE action = 'tz_edge_review') - (SELECT n FROM mig_before WHERE k = 'tz_edge'));
SELECT pg_temp.mig_add('users.hire_date_missing',
  CASE WHEN (SELECT n FROM mig_before WHERE k = 'start_date_plain') > 0 THEN (SELECT count(*) FROM users WHERE hire_date IS NULL) ELSE 0 END);
SELECT pg_temp.mig_add('legacy.tables_read_only',
  (SELECT count(*) FROM pg_trigger WHERE tgname = 'trg_legacy_read_only_row') - (SELECT n FROM mig_before WHERE k = 'legacy_guarded'));
SELECT pg_temp.mig_add('companies.timezone_needs_review',
  (SELECT count(*) FROM companies WHERE timezone_status = 'needs_review') - (SELECT n FROM mig_before WHERE k = 'needs_review'));
-- v1.6.20-r1 (J-96 = A, J-101): users whose department already reads 'General' cannot be proven defaulted → left
-- as a normal team (marker false), NOT reclassified; counted here for Karin's decision (no names).
SELECT pg_temp.mig_add('users.general_department_ambiguous', fn_general_department_ambiguous_count(NULL));

-- ---------------------------------------------------------------------------
-- 4. Report + commit (or roll back for a dry run).
-- ---------------------------------------------------------------------------
SELECT fn_mig_source_tz() AS mig_tz \gset
\echo 'CHR-ETRS migration v1.4 → v1.6.20 — counts of THIS run — v1.x dates compared in:' :mig_tz
SELECT step, n FROM mig_report ORDER BY step;
\if :dry_run
\echo 'DRY RUN — rolling back, nothing changed.'
ROLLBACK;
\else
COMMIT;
\echo 'MIGRATION COMMITTED.'
\endif
