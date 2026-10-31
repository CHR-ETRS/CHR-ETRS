-- =============================================================================
-- CHR-ETRS MVP v1.6.18 · schema.sql
-- Version: 1.6.18-mvp (2026-10-31 IL) — supersedes 1.6.17-mvp (2026-10-31 IL), 1.6.16-mvp (2026-10-30 IL), 1.6.13-mvp (2026-10-25 IL; v1.6.14 and v1.6.15 were planned and never built), 1.6.12-mvp (2026-10-24 IL), 1.6.11-mvp (2026-10-24 IL), 1.6.10-mvp (2026-10-21 IL), 1.6.9-mvp (2026-10-21 IL), 1.6.8-mvp (2026-10-21 IL), 1.6.7-mvp (2026-10-20 22:05 IL), 1.6.6-mvp (2026-10-20 21:15 IL), 1.6.5-mvp (2026-10-20 21:00 IL), 1.6.4-mvp (2026-10-20 20:45 IL), 1.6.3-mvp (2026-10-20 20:30 IL), 1.6.2-mvp (2026-10-20 11:05 IL), 1.6.1-mvp (2026-10-20 10:58 IL), 1.6.0-mvp (2026-10-20 10:30 IL), 1.5.0-mvp and 1.4.0-mvp (2026-10-06) and the
--          Drive hot-fix schema.20261013.sql (60-second Cuckoo window, kept here).
-- SoT: ADR index + Karin's approved locks of 2026-10-20 (via Chief of Drive).
-- Requires ref_country_calendar.sql (GENERATED from CLDR + IANA tz by tools/gen_ref_country_calendar.py)
--   to be loaded BEFORE this file.
-- New in 1.6.18 (Karin 31.10 via Chief of Drive — fix round closing A-12, A-13, A-14):
--   * A-12: every documented remediation is attributed to ONE leaver_transfer
--     (happiness_debt_remediation_allocation, WORM, no person column). A reversed offboarding returns only the
--     transfer's open balance (moved debt − remediations attributed to it); 0 is a valid documented reversal.
--     A v1.6.17 database's unattributed remediations are back-filled oldest-transfer-first within their team.
--   * A-13: approved_absence_entry gains schedule_status 'cancelled' + cancelled_at / cancel_reason
--     ('employment_ended'); the CLOSED tables time_benefit_absence_link (absence ↔ purchase, never shown to a
--     manager) and time_benefit_refund (WORM, one refund per absence) let a time benefit scheduled after the
--     end of employment be cancelled and its Golden Spoons refunded (rpc.sql).
--   * A-14: the three questionnaire participation settings are company-adjustable (not locked); every change
--     is kept in questionnaire_reward_history (WORM, effective_from) and every submission snapshots the
--     setting key and the effective_from of the value it earned (reward_setting_key, reward_effective_from).
-- New in 1.6.17 (Karin 31.10 via Chief of Drive — fix round closing A-5, A-8, J-3, J-15):
--   * A-5: TPS-12 and IHS pay a fixed 10 Golden Spoons for participation — agent_settings
--     golden_spoons_per_quarterly_questionnaire = 10 (adjustable: not locked, a company may override it).
--   * J-3 reversed: Cantril is a MONTHLY questionnaire → golden_spoons_per_questionnaire (10), not the short 2.
--   * J-15 confirmed: after employment ends no time benefit (early leave, approved absence / day off) can be
--     recorded — guard trigger on early_leave_log and approved_absence_entry; EverStore products only in the
--     30-day window.
--   * A-8: reversing an offboarding returns the leaver's Happiness Debt from the memo line "יצא עם העוזבים"
--     to the team: happiness_debt_events 'leaver_reversal' linked to the original leaver_transfer
--     (reverses_event_id, once per transfer). The event ↔ employee link is kept in the CLOSED internal table
--     happiness_debt_leaver_link (never returned), so happiness_debt_events itself stays person-free.
-- New in 1.6.16 (Karin 30.10 + Chief of Drive 30.10; agents-bot-instructions-v3 = source of truth, v3 wins):
--   * CHR Coins: rpc_convert_golden_to_chr stays DEFINED (v2 readiness) but every v1 call raises 422
--     chr_coins_deferred_to_v2 (rpc.sql) — no balance change, no golden_chr_conversion row.
--   * users.app_role gains 'cfo' (EverStore budget summary, open Golden Spoons liability, board report).
--   * Questionnaire Golden Spoons = participation only, fixed amount from agent_settings (reward_type
--     'participation' + reward_setting_key); the score/10 reward (fn_reward_score_div10) is removed.
--   * Management agents tables (section "v1.6.16 agents" at the end): agent_settings, everstore_budget,
--     everstore_item_cost, agent_daily_summaries, golden_spoons_ledger, happiness_debt_ledger,
--     happiness_debt_events, remediation_records, team_movements, metric_assurance, bcr_checks,
--     epwi_inputs, board_reconciliation, board_report. All closed to clients (SECURITY DEFINER RPCs only).
-- New in 1.6.13 (Karin 25.10 + Chief of Drive 25.10 — EverStore expansion & privacy):
--   * shop_item_catalog expansion: the 8 items (theme_*, badge_*) are the opening seed catalog
--     (קטלוג פתיחה), not a closed list. Adds category (8 categories: cosmetic, time_benefit,
--     health_wellbeing, learning, donation, experience, gift_card, merchandise), provider text NULL,
--     price_golden_spoons (any positive > 0 allowed; tiers basic / advanced / premium / custom),
--     cosmetic_only boolean (true or false allowed so tangible benefits work), while strictly
--     locking real_money_purchase_allowed = false and affects_daily_energy_spoons = false.
--   * Golden Spoons never expire while the employee is active (avatar_state.golden_spoons_expires_at
--     CHECK IS NULL); rpc_convert_golden_to_chr was active on the server in v1.6.13 (superseded in
--     v1.6.16: blocked, 422 chr_coins_deferred_to_v2).
--   * Time-benefit voucher redemption privacy (נעילת הפרגוד): purchasing/redeeming a time_benefit
--     item automatically creates a standard HR approved absence / refresh time entry
--     (approved_absence_entry / approved_absence_manager_v: 'זמן התרעננות / היעדרות מאושרת') so the
--     direct manager coordinates the schedule without ever seeing that it came from EverStore, while
--     shop_purchase / shop_inventory remains strictly hidden from managers.
-- New in 1.6.12 (Karin 24.10 + Chief of Drive 24.10):
--   * O-7: PCQ-12 answer scale locked as 1–6 (Luthans, 12 items, all required), converted linearly
--     to 0–100 ((mean − 1) / 5.0 × 100, fn_pcq12_score); questionnaire_submission.pcq12_score.
--   * O-25: Board / Tier 5 governance roles (board_chair, board_member, owner_shareholder) see all
--     company-wide organizational averages at the whole-company level only (TPS-12, spoons,
--     workload/EPWI/PEWI, IHS, Happiness Debt, deprivation tax, CHR Real EBITDA), with N≥5 for
--     regular metrics and N≥10 for sensitive/Shadow Balance metrics, and never any team/individual breakdown.
--   * O-14: Offboarding crypto-shredding retention period: self-request (rpc_request_crypto_shred)
--     is immediate (0-day wait); automatic offboarding (rpc_offboard_employee) revokes access and
--     vault immediately, schedules crypto-shredding for terminated_at + 30 days (cancellable via
--     rpc_revert_offboarding within 30 days), and rpc_run_scheduled_crypto_shred shreds elapsed keys.
--   * O-13: One ledger chain per company (org_id), genesis record seeded on company creation, and
--     fn_ledger_verify_chain raises an audit alert + blocks writes on broken chain.
--   * O-19 & O-20: CHRO (vp_hr) provisions governance-only users (has_employee_profile = false for
--     tier 5 roles by default unless also employees); manager vault rules enforced (direct manager
--     only, office-network + company-computer flags + inactivity timeout check, immediate wipe on
--     transfer/dismissal).
-- New in 1.6.11 (Karin 24.10 + Chief of Drive 24.10):
--   * O-8: TPS-12 / IHS fractional scores confirmed as built (round to nearest int, then last-digit rule).
--   * O-6: IHS score from 1–5 questionnaire answers: (mean − 1) / 4 × 100 (fn_ihs_score); IHS enabled;
--     team average ihs_team_avg at N≥5 respondents.
--   * O-1: Turnover replacement cost point estimate = tier midpoint (junior 40 %, mid 125 %, senior 300 %).
--   * O-2: Turnover tier defaults automatically from org_role.tier (1→junior, 2–3→mid, 4→senior,
--     5/outside→excluded unless overridden); CHRO (vp_hr) may override per employee.
--   * O-3: Deprived employee in a week = weekly avg available spoons < 5 OR weekly B_t ≥ 0.65.
--   * O-4 + O-18: avg_annual_salary for Happiness Debt / Deprivation Tax = company-wide average annual
--     salary of that turnover tier group (never individual or small-team average); full Shadow Balance /
--     Happiness Debt / 12 % deprivation tax / CHR Real EBITDA = GAAP EBITDA − happiness_debt_balance −
--     deprivation_tax_amount at N≥10 respondents.
--   * O-5: Morning check-in (0–10 scales average, half-points floored in employee's favor, sets reported_at)
--     & midday check-in (12:00–15:00 local, integer delta −4..+4, capped 0..12).
--   * Q5: "never show the deduction" applies only to check-in survey answer options; task costs (0/1/2)
--     and golden spoon rewards remain visible.
--   * O-16 / Q11: only Golden Spoons active in v1 (0.5 daily, 2 per shift, 10 at signup); CHR Coins v2.
--   * C-1 & C-2: soft WIP limit (>2 core projects alert only) and Weinberg table L(P)=0/20/40/60/75 % confirmed.
--   * O-30 & O-31: EPWI_cognitive bands (≤1.10 target, ≤1.50 above_target, >1.50 overload/danger) and
--     population SD σ for AIDB confirmed.
-- New in 1.6.10 (Chief of Drive 21.10): a pinned country zone (ref main_timezone_source 'override: …',
--   e.g. UA → Europe/Kyiv) is never needs_review (fn_country_tz_needs_review); UZ keeps Asia/Tashkent
--   (generated table); the start_date trust rule and the tz_edge_review flag use the migration's
--   source zone (fn_mig_source_tz: the --source-tz value, else UTC); legacy guard: the guard skips
--   tables the caller does not own (fallback ownership by legacy_v1_4_owner, migrations/).
-- New in 1.6.9 (Chief of Drive 21.10): O-50 hire_date is the single employment-start field; users.start_date
--   is a DEPRECATED read-only alias (generated column = hire_date, removal planned for v1.7), no
--   'today' default; an upgrade merges a plain start_date into hire_date unless it equals the record's
--   creation date (UTC date portion) → unknown, audited 'start_date_untrusted'. Zone exclusions for
--   CY / MH / MY / PS / UZ and UA pinned to Europe/Kyiv (generated table). DROP / ALTER of
--   legacy_v1_4_* blocked by an event trigger (migrations/legacy_ddl_guard.sql, superuser).
-- New in 1.6.8 (Karin 21.10 + Chief of Drive 21.10): week-start change = 7-day last old week + a 1–6-day
--   BRIDGE (no report → 422 bridge_period, no reminder); TPS 30-day wait from team_joined_at → hire_date
--   → exempt (users.hire_date, audited per user); unknown country → 422 unknown_country; DE single-zone
--   (zone exclusion list in the generated table); legacy_v1_4_* tables read-only; spoon_budget.row_source.
-- New in 1.6.7 (Karin 20.10 + Chief of Drive O-43): week-start history (company_week_start_history,
--   effective at the next week boundary, never recalculating stored reports); timezone_status
--   (needs_review for multi-zone backfill / no country) and reminders_on_hold; XK / AN zone overrides
--   (generated table); upgrade path from v1.4 in migrations/.
-- New in 1.6.6 (Chief of Drive rulings 20.10): default week start from CLDR weekData firstDay (IL pinned
--   to Sunday; unknown country → CLDR 001); upgrade backfill of last workday (day before the CLDR
--   weekend) and timezone (first zone.tab zone of the country), each value audited as auto-filled.
-- New in 1.6.5 (Karin 20.10): per-company week start, last workday and timezone (required, no
--   default); weekly reminder on the company's last workday at reminder_time (default 14:00,
--   locked), company-local; tiers 2 ↔ 3 swapped (labels only); legacy projects migrate to
--   is_core = false (new projects still choose explicitly).
-- New in 1.6.4 (Karin 20.10): B_t is linear 0.41·S + 0.37·O + 0.22·D from the weekly self-report
--   (stress and productivity drop on an integer 1–5 Likert scale, overtime hours capped at 10);
--   L(P>5) = L(5) = 0.75; core is a PROJECT property set explicitly by the PM (project.is_core,
--   no default); weekly reminder setting (example value: Thursday, end of day) — not a rule.
-- New in 1.6.3: project workload module (self-report → EPWI_time, EPWI_cognitive, B_t for the
--   employee only; PEWI / AIDB / TRR / M_SPOF for the PM at N≥5 respondents), soft WIP alert (>2 core
--   projects, no blocking), v2 integration stub; emergency misuse sequence (Q5, locked 13.10);
--   CHRO reason NOT NULL / non-empty (Q6, locked 12.10). Old project load index removed.
-- New in 1.6.2: emergency types named per Karin's lock of 13.10 (health_or_life_danger,
--   work_stopping_disaster, war_or_security); project load index returns NULL (no formula locked).
-- Locked in this version:
--   * Turnover cost by tier (% of annual salary): junior 30–50 (midpoint 40),
--     mid 100–150 (midpoint 125), senior 200–400 (midpoint 300).
--   * Deprivation tax = deprived_count × avg_annual_salary × 0.12 (system-computed).
--   * Privacy thresholds: regular team data N≥5; Cuckoo / Shadow Balance /
--     emergency mode N≥10. Below → 403 aggregation_privacy_threshold.
--   * Cuckoo: employee first, 60-SECOND veto, then direct manager sees pseudonym only.
--   * Spoons: hard max 12/day; Fighting blocked at ≤5 remaining (4–5 band);
--     ≤3 → go home, log only 'יציאה מוקדמת מאושרת' + time; full workday, no sick day.
--     Old "<3 spoons OR <14% capacity" rule REMOVED. CB never locks questionnaires/shop.
--   * TPS-12 + generic questionnaire definitions/submissions (WORM).
--   * Golden spoons fractional (numeric(10,1)); one-way golden → CHR Coins at 1 = 50.
--   * Manager ledger: SHA-256 hash chain, pseudonym only, crypto-shredding, WORM 403.
-- Open items are marked TODO — numbers that are not locked are NOT invented.
-- New in 1.6.0 (Karin's locks of 2026-10-20): #4 red team alert
--   (respondent-based N≥5), #6 shop open to every user with an employee profile,
--   #7 crypto-shredding only by self-request or automatic offboarding,
--   #8 system-assigned random pseudonyms (colour + animal), unique per company, immutable.
-- New in 1.6.1 (Karin's locks #1, #3 + v1.6 scope):
--   #1 at ≤3 spoons ALL tasks are blocked (Farming included).
--   #3 every privacy threshold counts ACTUAL contributors (distinct employees whose data
--      feeds that aggregate in that period), never team size: regular 5, Cuckoo / Shadow
--      Balance / emergency 10, project 5, board 20.
--   Role tree (org_role, tiers 1–5, reports_to solid line, optional dotted_line_to),
--   access rules (subtree / averages-only / pseudonyms-only / CHRO named + reason, audited),
--   project load index, board macro trends, emergency mode, distress button.
-- Install target: fresh database (or upgrade from v1.4 via migrations/migrate_v1_4_to_v1_6_13.sql).
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

-- v1.5: replaces energy_state_enum (GREEN/YELLOW/RED with the released <3 rule).
-- OPEN = 6–12 spoons; FIGHTING_BLOCKED = 4–5; GO_HOME = 0–3.
DO $$ BEGIN
  CREATE TYPE day_status_enum AS ENUM ('OPEN', 'FIGHTING_BLOCKED', 'GO_HOME');
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

-- v1.5: Dutch auction tier removed (deferred to v2). v1.6.13 (Karin 25.10): added 'premium', 'custom'.
DO $$ BEGIN
  CREATE TYPE shop_tier_enum AS ENUM ('basic', 'advanced', 'premium', 'custom');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
ALTER TYPE shop_tier_enum ADD VALUE IF NOT EXISTS 'premium';
ALTER TYPE shop_tier_enum ADD VALUE IF NOT EXISTS 'custom';

-- ---------------------------------------------------------------------------
-- Scaffolding: companies + users (tenant_id / company_id; RBAC app_role)
-- No ROOT_ADMIN user role (ADR-068).
-- v1.6.1: generic role tree. org_role = position in the tree (tiers 1–5); app_role stays the
--      system privilege class (employee / manager / vp_hr = CHRO / legal_ethics / governance).
-- ---------------------------------------------------------------------------

-- Role catalogue (v1.6.1, B1). Tier 1 = employee … tier 5 = top / governance.
-- Resolved 20.10: safety_emergency_manager is outside the 5 tiers (tier NULL, least privilege).
-- v1.6.4 (Karin, Q8): role → tier mapping of her locked 5 tiers (for Karin's review in ADR_GAPS):
--   1 employee, direct manager · 2 functional manager (solid line), project / product manager
--   (dotted line) · 3 department / division manager, director (tiers 2 ↔ 3 swapped, Karin v1.6.5) ·
--   4 VP (CHRO / COO / CFO / CTO), EVP, CEO · 5 board chair, board member, owners / shareholders.
-- The tier is a LABEL only: access is defined by the locked rules (solid-line cascade,
--   is_management, averages_only, app_role) and does not read org_role.tier.
CREATE TABLE IF NOT EXISTS org_role (
    role_code       text PRIMARY KEY,
    -- Tiers 1–5. v1.6.3 lock (Karin 20.10): the safety & emergency manager is OUTSIDE the
    -- 5 tiers (least privilege) → tier NULL; no other role may be outside.
    tier            smallint,
    CONSTRAINT chk_org_role_tier CHECK (
      (role_code = 'safety_emergency_manager' AND tier IS NULL)
      OR (role_code <> 'safety_emergency_manager' AND tier IS NOT NULL AND tier BETWEEN 1 AND 5)),
    -- true = may read aggregates of her solid-line subtree (management access)
    is_management   boolean NOT NULL DEFAULT false,
    -- true = averages only (never pseudonyms / names): CEO, owners, board
    averages_only   boolean NOT NULL DEFAULT false,
    is_governance   boolean NOT NULL DEFAULT false,
    label_he        text NOT NULL
);

INSERT INTO org_role (role_code, tier, is_management, averages_only, is_governance, label_he) VALUES
  ('employee',                 1, false, false, false, 'עובד/ת'),
  ('direct_manager',           1, true,  false, false, 'מנהל/ת ישיר/ה'),
  ('project_manager',          2, false, false, false, 'מנהל/ת פרויקט'),            -- dotted line
  ('functional_manager',       2, true,  false, false, 'מנהל/ת פונקציונלי/ת'),      -- solid line
  ('safety_emergency_manager', NULL, false, false, false, 'מנהל/ת בטיחות וחירום'),   -- outside the tiers (lock 20.10)
  ('department_manager',       3, true,  false, false, 'מנהל/ת מחלקה'),
  ('division_manager',         3, true,  false, false, 'מנהל/ת חטיבה'),
  ('director',                 3, true,  false, false, 'דירקטור/ית תפעולי/ת'),
  ('vp',                       4, true,  false, false, 'סמנכ"ל/ית'),
  ('evp',                      4, true,  false, false, 'סמנכ"ל/ית בכיר/ה'),
  ('ceo',                      4, true,  true,  false, 'מנכ"ל/ית'),
  ('board_chair',              5, false, true,  true,  'יו"ר דירקטוריון'),
  ('board_member',             5, false, true,  true,  'חבר/ת דירקטוריון'),
  ('owner_shareholder',        5, false, true,  true,  'בעלים / בעל/ת מניות')
ON CONFLICT (role_code) DO UPDATE SET tier = EXCLUDED.tier;   -- v1.6.4: Q8 mapping re-applied
CREATE TABLE IF NOT EXISTS companies (
    company_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id    uuid GENERATED ALWAYS AS (company_id) STORED,
    company_name varchar(255) NOT NULL UNIQUE,
    industry     varchar(255),
    company_size varchar(50),
    location     varchar(255),
    -- v1.6.5 (Karin 20.10): company calendar. Day of week 0–6 = Sunday … Saturday (extract(dow)).
    -- Country (ISO 3166-1 alpha-2) is REQUIRED; it supplies the week-start default
    -- (v1.6.6: CLDR weekData firstDay via ref_country_calendar; IL pinned to Sunday; unknown → CLDR 001;
    -- trg_companies_week_start). A company may override.
    country           text NOT NULL CHECK (country ~ '^[A-Z]{2}$'),
    week_start_dow    smallint NOT NULL CHECK (week_start_dow BETWEEN 0 AND 6),
    -- Last workday (reminder day): REQUIRED on create, no default. The week is always 7 days.
    -- v1.6.6: legacy companies are BACKFILLED once (day before the CLDR weekend; fn_backfill_company_calendar).
    last_workday_dow  smallint NOT NULL CHECK (last_workday_dow BETWEEN 0 AND 6),
    timezone          text NOT NULL,                     -- IANA; validated by trg_companies_timezone
                                                         -- (v1.6.6 legacy backfill: country's first zone.tab zone)
    -- Weekly self-report reminder time, company-local. Default 14:00 is LOCKED by Karin.
    reminder_time     time NOT NULL DEFAULT '14:00',
    -- v1.6.7 (Chief of Drive, O-43): needs_review = the timezone was auto-picked for a multi-zone
    -- country, or the company has no country. Cleared by the CHRO confirming (audited).
    timezone_status   text NOT NULL DEFAULT 'confirmed' CHECK (timezone_status IN ('confirmed', 'needs_review')),
    -- v1.6.7 (O-43): weekly reminders held (legacy company without a country) until a country is set.
    reminders_on_hold boolean NOT NULL DEFAULT false,
    created_at   timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE IF NOT EXISTS users (
    user_id       uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id    uuid REFERENCES companies(company_id) ON DELETE SET NULL,
    -- v1.6.1 (B1): SOLID line = direct manager. Receives Cuckoo alerts (pseudonym only)
    -- and early-leave notices. Subtree access follows this column only.
    reports_to    uuid REFERENCES users(user_id) ON DELETE SET NULL,
    -- Optional DOTTED line (e.g. functional manager). Never grants subtree access.
    dotted_line_to uuid REFERENCES users(user_id) ON DELETE SET NULL,
    -- Position in the role tree (org_role); tier comes from org_role.
    org_role_code text NOT NULL DEFAULT 'employee' REFERENCES org_role(role_code),
    -- Distress button (B6): contact phone + last location; shown only to the safety manager.
    phone         varchar(32),
    last_location text CHECK (last_location IS NULL OR last_location IN ('home', 'office', 'site')),
    email         varchar(255) NOT NULL UNIQUE,
    full_name     varchar(255) NOT NULL,
    department    varchar(255) NOT NULL DEFAULT 'General',
    -- ADR-068: employee | manager | vp_hr | legal_ethics — no ROOT_ADMIN.
    -- v1.6 / v1.6.12 (O-19, O-20, O-25): governance roles (board_chair, board_member, owner_shareholder)
    -- have whole-company macro read access only; has_employee_profile defaults to false for tier 5 roles
    -- unless also an employee (provisioned by CHRO via rpc_provision_governance_user).
    -- v1.6.16 (Karin 30.10, v3 §2.3): 'cfo' added — sees the EverStore budget summary and the open
    -- Golden Spoons liability in ILS together with vp_hr only.
    app_role      text NOT NULL DEFAULT 'employee'
                  CHECK (app_role IN ('employee', 'manager', 'vp_hr', 'legal_ethics',
                                      'board_chair', 'board_member', 'owner_shareholder', 'cfo')),
    -- v1.6 (lock #6) / v1.6.12 (O-20): employee interface / wallet. Tier 5 governance roles default to
    -- false unless explicitly marked as also an employee.
    has_employee_profile boolean NOT NULL DEFAULT true,
    -- v1.6 (lock #7) / v1.6.12 (O-14): set when employment ends; revokes access & vault immediately and
    -- schedules crypto-shredding for employment_ended_at + 30 days (cancellable within 30 days).
    employment_ended_at  timestamptz,
    -- ADR-007 / Q-002: consent default FALSE
    consent_vault boolean NOT NULL DEFAULT FALSE,
    -- N-1 / N-4 revised / 051 v4: IANA timezone per employee — NOT NULL, NO DEFAULT
    -- Client auto-detects Intl zone at signup, or maps country(/region) → IANA on client.
    timezone      text NOT NULL,
    -- Optional ISO 3166-1 alpha-2; country→zone mapping is CLIENT-SIDE only (N-4 revised)
    country_code  char(2)
                  CHECK (country_code IS NULL OR country_code ~ '^[A-Z]{2}$'),
    -- Nickname shown to the direct manager instead of the real name (Cuckoo, early-leave
    -- feed). v1.6 (lock #8): assigned by the SYSTEM at insert (random colour + animal), unique
    -- per company, never derived from name or id, and immutable — no self-set path.
    display_pseudonym varchar(64) NOT NULL,
    -- v1.6.8 (Karin 21.10, O-49): hire date, nullable, NO default. Fallback start of the TPS wait.
    -- v1.6.9 (O-50): the SINGLE employment-start field.
    hire_date     date,
    -- v1.6.9 (O-50): DEPRECATED read-only alias of hire_date (generated: any written value is refused,
    -- SQLSTATE 428C9). No default. Removal planned for v1.7 — read hire_date.
    start_date    date GENERATED ALWAYS AS (hire_date) STORED,
    -- Lock #5: when the employee joined her CURRENT team (team = company + department).
    -- Set explicitly or by an internal transfer (trg_users_team_joined resets it to the transfer
    -- time). v1.6.8: no longer defaulted on insert. TPS wait = team_joined_at → hire_date → exempt.
    team_joined_at timestamptz,
    created_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT chk_users_not_self_manager CHECK (reports_to IS DISTINCT FROM user_id
                                                 AND dotted_line_to IS DISTINCT FROM user_id)
);

ALTER TABLE users ADD COLUMN IF NOT EXISTS hire_date date;   -- v1.6.8 upgrade (O-49)

-- v1.6.16 upgrade: add 'cfo' to an existing app_role CHECK (same expression as the fresh table).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_app_role_check'
                AND conrelid = 'users'::regclass
                AND pg_get_constraintdef(oid) LIKE '%board_chair%'
                AND pg_get_constraintdef(oid) NOT LIKE '%cfo%') THEN
    ALTER TABLE users DROP CONSTRAINT users_app_role_check;
    ALTER TABLE users ADD CONSTRAINT users_app_role_check CHECK (app_role IN ('employee', 'manager', 'vp_hr', 'legal_ethics',
                                                                              'board_chair', 'board_member', 'owner_shareholder', 'cfo'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_users_company_role ON users (company_id, app_role);
CREATE INDEX IF NOT EXISTS idx_users_reports_to ON users (reports_to);
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
-- Lock #5: team_joined_at — reset on team transfer. v1.6.8 (O-49): no insert default any more
-- (the start_date / insert-day fallback is removed; the TPS wait falls back to hire_date).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_users_team_joined()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.department IS DISTINCT FROM OLD.department OR NEW.company_id IS DISTINCT FROM OLD.company_id THEN
    NEW.team_joined_at := clock_timestamp();   -- internal transfer → 30-day rule restarts
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_team_joined ON users;
CREATE TRIGGER trg_users_team_joined
    BEFORE UPDATE OF department, company_id ON users
    FOR EACH ROW
    EXECUTE FUNCTION fn_users_team_joined();

-- ---------------------------------------------------------------------------
-- v1.6 (lock #8): system-assigned pseudonyms. Random colour + animal (Hebrew), unique per
-- company; a numeric suffix is added only when all combinations are taken.
-- ---------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS uq_users_company_pseudonym
    ON users (company_id, display_pseudonym);

-- Generate a random, unused pseudonym for a company. System-only (no client grant).
CREATE OR REPLACE FUNCTION fn_generate_pseudonym(p_company_id uuid)
RETURNS varchar
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_colours text[] := ARRAY['אדום','כחול','ירוק','צהוב','כתום','סגול','ורוד','תכלת','חום','אפור','טורקיז','זהוב'];
  v_animals text[] := ARRAY['שועל','ינשוף','דולפין','צב','נמר','צבי','דוב','סנאי','זאב','פינגווין','עפרוני','קיפוד'];
  v_name varchar;
  v_try int := 0;
BEGIN
  -- Serialise generation per company so two inserts cannot pick the same name.
  PERFORM pg_advisory_xact_lock(hashtext('pseudonym:' || COALESCE(p_company_id::text, 'none')));
  LOOP
    v_try := v_try + 1;
    v_name := v_animals[1 + floor(random() * cardinality(v_animals))::int] || ' ' ||
              v_colours[1 + floor(random() * cardinality(v_colours))::int];
    IF v_try > 200 THEN
      -- All/most combinations used: add a random number (still not derived from identity).
      v_name := v_name || ' ' || (10 + floor(random() * 990))::int;
    END IF;
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM users u
       WHERE u.company_id IS NOT DISTINCT FROM p_company_id AND u.display_pseudonym = v_name);
  END LOOP;
  RETURN v_name;
END;
$$;

REVOKE ALL ON FUNCTION fn_generate_pseudonym(uuid) FROM PUBLIC;

-- BEFORE INSERT: always assign a system pseudonym (any client-supplied value is ignored).
-- BEFORE UPDATE: the pseudonym can never be changed → 403 pseudonym_immutable.
CREATE OR REPLACE FUNCTION fn_users_pseudonym_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.display_pseudonym := fn_generate_pseudonym(NEW.company_id);
  ELSIF NEW.display_pseudonym IS DISTINCT FROM OLD.display_pseudonym THEN
    RAISE EXCEPTION 'pseudonym_immutable'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=pseudonym_immutable', HINT = 'pseudonym_immutable';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_pseudonym ON users;
CREATE TRIGGER trg_users_pseudonym
    BEFORE INSERT OR UPDATE OF display_pseudonym ON users
    FOR EACH ROW
    EXECUTE FUNCTION fn_users_pseudonym_guard();
-- TODO להשלמה: department move / company move — keep pseudonym or issue a new one
-- (12.10 vault rules); today it stays and uniqueness is per company.

-- ---------------------------------------------------------------------------
-- Deprivation Tax constant (Q-027 / Q-016) — system-computed; NOT client-writable
-- productivity_factor = 0.12
--   Oswald, Proto & Sgroi, J. Labor Econ. 2015, doi:10.1086/681096
--   Bellet, De Neve & Ward, Management Science 70(3) 2024, doi:10.1287/mnsc.2023.4766
-- v1.5 formula (locked 2026-10-12 16:19, approved 2026-10-20):
--   deprivation_tax_amount = deprived_count × avg_annual_salary × 0.12
-- Rejected: 13–14%; any fixed currency amount.
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

-- v1.5: role_cost_config (1.5× default, 0.5–2.0 range) is REMOVED.
DROP TABLE IF EXISTS role_cost_config;

-- ---------------------------------------------------------------------------
-- Turnover cost tiers — % of annual salary (locked 2026-10-12 16:19; midpoint locked 2026-10-24, O-1)
--   junior 30–50 (midpoint 40 %) · mid / tech talent 100–150 (midpoint 125 %) · senior management 200–400 (midpoint 300 %)
-- CHECK pins the locked values so they cannot drift.
-- O-2 (Karin 24.10): tier defaults from org_role.tier (1→junior, 2–3→mid, 4→senior, 5/outside→NULL); CHRO may override.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS turnover_tier_config (
    tier         text PRIMARY KEY CHECK (tier IN ('junior', 'mid', 'senior')),
    min_pct      numeric(6, 2) NOT NULL CHECK (min_pct > 0),
    max_pct      numeric(6, 2) NOT NULL,
    updated_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
    midpoint_pct numeric(6, 2) NOT NULL GENERATED ALWAYS AS (round((min_pct + max_pct) / 2.0, 2)) STORED,
    CONSTRAINT chk_tier_range_order CHECK (max_pct >= min_pct),
    CONSTRAINT chk_tier_locked_values CHECK (
         (tier = 'junior' AND min_pct = 30  AND max_pct = 50  AND midpoint_pct = 40)
      OR (tier = 'mid'    AND min_pct = 100 AND max_pct = 150 AND midpoint_pct = 125)
      OR (tier = 'senior' AND min_pct = 200 AND max_pct = 400 AND midpoint_pct = 300)
    )
);
ALTER TABLE turnover_tier_config ADD COLUMN IF NOT EXISTS
    midpoint_pct numeric(6, 2) NOT NULL GENERATED ALWAYS AS (round((min_pct + max_pct) / 2.0, 2)) STORED;

COMMENT ON TABLE turnover_tier_config IS
  'Turnover cost as % of annual salary by tier (locked): min/max range + midpoint point estimate (junior 40%, mid 125%, senior 300%; O-1).';

INSERT INTO turnover_tier_config (tier, min_pct, max_pct) VALUES
  ('junior', 30, 50),
  ('mid', 100, 150),
  ('senior', 200, 400)
ON CONFLICT (tier) DO NOTHING;

-- Midpoint % for a turnover tier (junior 40, mid 125, senior 300; O-1).
CREATE OR REPLACE FUNCTION fn_turnover_tier_midpoint_pct(p_tier text)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_tier
    WHEN 'junior' THEN 40.00::numeric(6, 2)
    WHEN 'mid'    THEN 125.00::numeric(6, 2)
    WHEN 'senior' THEN 300.00::numeric(6, 2)
  END
$$;

-- Midpoint multiplier factor for a turnover tier (junior 0.40, mid 1.25, senior 3.00; O-1).
CREATE OR REPLACE FUNCTION fn_turnover_tier_midpoint_factor(p_tier text)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_tier
    WHEN 'junior' THEN 0.40::numeric(6, 2)
    WHEN 'mid'    THEN 1.25::numeric(6, 2)
    WHEN 'senior' THEN 3.00::numeric(6, 2)
  END
$$;

-- O-2 (Karin 24.10): map 5-tier org_role.tier → default turnover tier (1→junior, 2–3→mid, 4→senior, 5/NULL→NULL).
CREATE OR REPLACE FUNCTION fn_default_turnover_tier_for_org_tier(p_org_tier int)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_org_tier = 1 THEN 'junior'
    WHEN p_org_tier IN (2, 3) THEN 'mid'
    WHEN p_org_tier = 4 THEN 'senior'
    ELSE NULL
  END
$$;

-- Default turnover tier of a user from her org_role.tier (O-2).
CREATE OR REPLACE FUNCTION fn_user_default_turnover_tier(p_user_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT fn_default_turnover_tier_for_org_tier(r.tier)
    FROM users u
    JOIN org_role r ON r.role_code = u.org_role_code
   WHERE u.user_id = p_user_id
$$;

REVOKE ALL ON FUNCTION fn_user_default_turnover_tier(uuid) FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- Privacy thresholds (approved 2026-10-20; overrides 12.10 "N≥10 everywhere")
--   regular team data (incl. dashboard / team averages)  N ≥ 5
--   cuckoo, shadow_balance, emergency                     N ≥ 10
--   project (project manager load index / burnout alert)  N ≥ 5   (v1.6.1)
--   board (macro trends)                                  N ≥ 20  (v1.6.1)
-- Lock #3 (v1.6.1): N = ACTUAL contributors — distinct employees whose data feeds the
-- aggregate in that period — never team size / membership.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS privacy_threshold_config (
    scope   text PRIMARY KEY
            CHECK (scope IN ('regular', 'cuckoo', 'shadow_balance', 'emergency', 'project', 'board')),
    min_n   int NOT NULL,
    CONSTRAINT chk_threshold_locked CHECK (
         (scope IN ('regular', 'project') AND min_n = 5)
      OR (scope IN ('cuckoo', 'shadow_balance', 'emergency') AND min_n = 10)
      OR (scope = 'board' AND min_n = 20)
    )
);

INSERT INTO privacy_threshold_config (scope, min_n) VALUES
  ('regular', 5),
  ('cuckoo', 10),
  ('shadow_balance', 10),
  ('emergency', 10),
  ('project', 5),
  ('board', 20)
ON CONFLICT (scope) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 1. employee_value_asset — salary input, turnover tier, deprivation flag
-- No per-employee tax column: the tax is a team figure (count × avg × 0.12).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS employee_value_asset (
    asset_id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                    uuid NOT NULL UNIQUE REFERENCES users(user_id) ON DELETE CASCADE,
    company_id                 uuid REFERENCES companies(company_id) ON DELETE SET NULL,
    direct_cost_opex           numeric(12, 2) NOT NULL DEFAULT 0 CHECK (direct_cost_opex >= 0),
    -- Optional CapEx placeholder; no default amount (not a replacement cost)
    asset_value_capex          numeric(12, 2) CHECK (asset_value_capex IS NULL OR asset_value_capex >= 0),
    -- Input for deprivation tax / turnover range (system uses this; no hardcoded salary)
    annual_salary              numeric(12, 2) CHECK (annual_salary IS NULL OR annual_salary >= 0),
    -- v1.6.11 (O-2): defaults from org_role.tier (1→junior, 2–3→mid, 4→senior, 5/outside→NULL); CHRO may override.
    turnover_tier              text REFERENCES turnover_tier_config(tier),
    turnover_tier_override     boolean NOT NULL DEFAULT false,
    -- v1.6.11 (O-3): deprived in a week when weekly avg available spoons < 5 OR weekly B_t ≥ 0.65.
    is_deprived                boolean,
    productivity_alpha_factor  numeric(5, 4) NOT NULL DEFAULT 1.0000,
    -- v1.6.11 (O-1 / O-4 / O-18): turnover replacement cost point estimate using company tier avg salary × midpoint %.
    happiness_debt_liability   numeric(12, 2) NOT NULL DEFAULT 0 CHECK (happiness_debt_liability >= 0),
    created_at                 timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at                 timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE employee_value_asset ADD COLUMN IF NOT EXISTS turnover_tier_override boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN employee_value_asset.is_deprived IS
  'O-3 (Karin 24.10): deprived in a week when weekly average available spoons < 5 OR weekly B_t >= 0.65 (synced by system / check-in / workload report).';

-- Effective turnover tier of a user: CHRO override on EVA when set, else default from org_role.tier (O-2).
CREATE OR REPLACE FUNCTION fn_effective_turnover_tier(p_user_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT CASE
           WHEN e.turnover_tier_override OR e.turnover_tier IS NOT NULL THEN e.turnover_tier
           ELSE fn_default_turnover_tier_for_org_tier(r.tier)
         END
    FROM users u
    JOIN org_role r ON r.role_code = u.org_role_code
    LEFT JOIN employee_value_asset e ON e.user_id = u.user_id
   WHERE u.user_id = p_user_id
$$;

REVOKE ALL ON FUNCTION fn_effective_turnover_tier(uuid) FROM PUBLIC;

-- BEFORE INSERT OR UPDATE on employee_value_asset: fill company_id and default turnover_tier from org_role.tier (O-2).
CREATE OR REPLACE FUNCTION fn_eva_default_turnover_tier()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NEW.company_id IS NULL THEN
    SELECT u.company_id INTO NEW.company_id FROM users u WHERE u.user_id = NEW.user_id;
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.turnover_tier IS NOT NULL THEN
      NEW.turnover_tier_override := true;
    ELSE
      NEW.turnover_tier := fn_user_default_turnover_tier(NEW.user_id);
      NEW.turnover_tier_override := false;
    END IF;
  ELSIF NEW.turnover_tier IS NULL AND NOT COALESCE(NEW.turnover_tier_override, false) THEN
    NEW.turnover_tier := fn_user_default_turnover_tier(NEW.user_id);
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION fn_eva_default_turnover_tier() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_eva_default_turnover_tier ON employee_value_asset;
CREATE TRIGGER trg_eva_default_turnover_tier
    BEFORE INSERT OR UPDATE ON employee_value_asset
    FOR EACH ROW
    EXECUTE FUNCTION fn_eva_default_turnover_tier();

-- AFTER UPDATE OF org_role_code on users: refresh non-overridden EVA turnover_tier (O-2).
CREATE OR REPLACE FUNCTION fn_users_sync_turnover_tier()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  UPDATE employee_value_asset
     SET turnover_tier = fn_user_default_turnover_tier(NEW.user_id),
         updated_at = clock_timestamp()
   WHERE user_id = NEW.user_id
     AND NOT turnover_tier_override;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION fn_users_sync_turnover_tier() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_users_sync_turnover_tier ON users;
CREATE TRIGGER trg_users_sync_turnover_tier
    AFTER UPDATE OF org_role_code ON users
    FOR EACH ROW
    EXECUTE FUNCTION fn_users_sync_turnover_tier();

-- Per-employee turnover cost RANGE (min/max) + MIDPOINT point estimate (O-1). Own row only (RLS of EVA applies).
CREATE OR REPLACE VIEW employee_turnover_cost_range_v
WITH (security_invoker = true) AS
SELECT e.user_id,
       e.turnover_tier,
       e.annual_salary,
       t.min_pct,
       t.max_pct,
       round(e.annual_salary * t.min_pct / 100, 2) AS turnover_cost_min,
       round(e.annual_salary * t.max_pct / 100, 2) AS turnover_cost_max,
       t.midpoint_pct,
       round(e.annual_salary * t.midpoint_pct / 100, 2) AS turnover_cost_midpoint
  FROM employee_value_asset e
  LEFT JOIN turnover_tier_config t ON t.tier = e.turnover_tier;

COMMENT ON VIEW employee_turnover_cost_range_v IS
  'Turnover cost range (min/max %) and midpoint point estimate (junior 40%, mid 125%, senior 300%; O-1).';

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
-- 3. spoon_budget — 0..12 (12 = hard daily max); reset ALWAYS to 12 at employee
-- local midnight (N-1). budget_date = (now() AT TIME ZONE users.timezone)::date
-- v1.5: available_capacity_pct + energy_state removed (old <3 / <14% rule released).
-- day_status: OPEN (6–12) · FIGHTING_BLOCKED (4–5) · GO_HOME (0–3).
-- v1.6.11 (O-5): morning (rpc_morning_checkin) and midday (rpc_midday_checkin, 12:00–15:00 local) check-in RPCs.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS spoon_budget (
    budget_id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                  uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    budget_date              date NOT NULL,
    current_spoon_count      int NOT NULL DEFAULT 12
                             CHECK (current_spoon_count BETWEEN 0 AND 12),
    daily_baseline_capacity  int NOT NULL DEFAULT 12
                             CHECK (daily_baseline_capacity = 12),
    day_status               day_status_enum GENERATED ALWAYS AS (
        CASE
            WHEN current_spoon_count <= 3 THEN 'GO_HOME'::day_status_enum
            WHEN current_spoon_count <= 5 THEN 'FIGHTING_BLOCKED'::day_status_enum
            ELSE 'OPEN'::day_status_enum
        END
    ) STORED,
    -- v1.6 (lock #4) / v1.6.11 (O-5): when the employee actually reported spoons for this day
    -- (set by rpc_morning_checkin, rpc_midday_checkin, rpc_log_go_home). Rows created by the
    -- midnight reset have NULL. Counts toward the red-team-alert respondent N and O-3 weekly spoon avg.
    reported_at              timestamptz,
    -- v1.6.8 (Chief of Drive 21.10, O-48): where the row comes from. 'legacy_v1_4' = migrated from v1.4,
    -- whose spoon days carry no submission time (reported_at NULL = unknown, not "did not report").
    row_source               text NOT NULL DEFAULT 'app',
    -- v1.6.11 (O-16 / Q11): true once the 2.0 golden spoons shift-start allowance was paid for this local day.
    shift_golden_awarded     boolean NOT NULL DEFAULT false,
    updated_at               timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (user_id, budget_date),
    CONSTRAINT chk_spoon_row_source CHECK (row_source IN ('app', 'legacy_v1_4'))
);
ALTER TABLE spoon_budget ADD COLUMN IF NOT EXISTS row_source text NOT NULL DEFAULT 'app';   -- v1.6.8 upgrade
ALTER TABLE spoon_budget ADD COLUMN IF NOT EXISTS shift_golden_awarded boolean NOT NULL DEFAULT false;   -- v1.6.11 upgrade
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_spoon_row_source') THEN
    ALTER TABLE spoon_budget ADD CONSTRAINT chk_spoon_row_source CHECK (row_source IN ('app', 'legacy_v1_4'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_spoon_budget_user_date
    ON spoon_budget (user_id, budget_date DESC);

-- ---------------------------------------------------------------------------
-- 4. hrv_sample — v2 ONLY. Unused in v1: nothing writes or reads it; the
-- Circuit Breaker never reads HRV. Kept for v2 sensors (Q-009); do not delete.
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
  'v2 ONLY — unused in v1 (no pulse/HRV in v1). Circuit Breaker does not read HRV. Kept for v2 (Q-009).';

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
-- early_leave_log — ≤3 spoons → employee goes home (locked 15:39 / 16:02)
-- Stores ONLY the locked text 'יציאה מוקדמת מאושרת' + time. No reason column.
-- The day counts as a full workday; no sick-day deduction. WORM (append-only).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS early_leave_log (
    log_id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    local_date              date NOT NULL,
    entry_text              text NOT NULL DEFAULT 'יציאה מוקדמת מאושרת'
                            CHECK (entry_text = 'יציאה מוקדמת מאושרת'),
    left_at                 timestamptz NOT NULL DEFAULT clock_timestamp(),
    counts_as_full_workday  boolean NOT NULL DEFAULT true CHECK (counts_as_full_workday),
    sick_day_deducted       boolean NOT NULL DEFAULT false CHECK (NOT sick_day_deducted),
    UNIQUE (user_id, local_date)
);

COMMENT ON TABLE early_leave_log IS
  'Locked text only (יציאה מוקדמת מאושרת) + time; no reason, no health data; full workday, no sick day.';

-- ---------------------------------------------------------------------------
-- 7. team_aggregate — REGULAR team data, N ≥ 5 ACTUAL contributors (lock #3)
-- Deprivation tax (count × avg × 0.12), turnover range sums, TPS-12 team average.
-- Sensitive Shadow Balance figures moved to shadow_balance_aggregate (N ≥ 10).
-- TODO: "team" = company + department (unchanged from 1.4); hierarchy cascade open.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS team_aggregate (
    aggregate_id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                    uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    department                varchar(100) NOT NULL,
    -- Lock #3: distinct employees whose data feeds this row (spoon reports today, TPS-12
    -- answers this quarter, salary records). Never team size.
    contributor_count         int NOT NULL CHECK (contributor_count >= 1),
    salary_contributor_count  int,
    -- v1.6: average of today's REPORTED spoons; NULL unless ≥5 employees reported.
    team_spoon_avg            numeric(4, 2),
    spoon_reporter_count      int,
    deprived_count            int,
    avg_annual_salary         numeric(12, 2),
    -- System-computed: deprived_count × avg_annual_salary × 0.12
    deprivation_tax_amount    numeric(14, 2),
    -- Range sums + midpoint sum (O-1: junior 40%, mid 125%, senior 300%); tier 5/outside excluded unless overridden.
    turnover_cost_min_sum      numeric(14, 2),
    turnover_cost_max_sum      numeric(14, 2),
    turnover_cost_midpoint_sum numeric(14, 2),
    heat_map_bucket            varchar(32),
    -- TPS-12 team average of this quarter; NULL if < N_regular respondents.
    tps_team_avg               numeric(5, 2),
    tps_respondent_count       int,
    -- v1.6.11 (O-6): IHS team average of this quarter; NULL if < N_regular (5) respondents.
    ihs_team_avg               numeric(5, 2),
    ihs_respondent_count       int,
    -- v1.6 (lock #4): red team alert = team_spoon_avg < 3; team-level trend only.
    -- NULL (no alert) unless ≥5 employees reported spoons in the period.
    dichotomous_alert_level    dichotomous_alert_enum,
    calculated_at              timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT chk_spoon_alert_respondents CHECK (
      (dichotomous_alert_level IS NULL AND team_spoon_avg IS NULL)
      OR spoon_reporter_count >= 5
    )
);
ALTER TABLE team_aggregate ADD COLUMN IF NOT EXISTS turnover_cost_midpoint_sum numeric(14, 2);
ALTER TABLE team_aggregate ADD COLUMN IF NOT EXISTS ihs_team_avg numeric(5, 2);
ALTER TABLE team_aggregate ADD COLUMN IF NOT EXISTS ihs_respondent_count int;

CREATE INDEX IF NOT EXISTS idx_team_agg_org_dept
    ON team_aggregate (org_id, department, calculated_at DESC);

-- ---------------------------------------------------------------------------
-- shadow_balance_aggregate — SENSITIVE (Shadow Balance), N ≥ 10 (O-1, O-2, O-3, O-4, O-18 locked 24.10)
--   * avg_annual_salary per tier = company-wide average annual salary of that turnover tier group (O-4)
--   * happiness_debt_sum / happiness_debt_balance = Σ (company_tier_avg_salary × midpoint_factor) over deprived employees (O-1)
--   * deprivation_tax_amount = Σ (company_tier_avg_salary × 0.12) over deprived employees (O-3, O-4)
--   * shadow_balance_sum = happiness_debt_sum + deprivation_tax_amount
--   * chr_real_ebitda = gaap_reported_ebitda − happiness_debt_balance − deprivation_tax_amount (O-18)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS shadow_balance_aggregate (
    aggregate_id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                    uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    department                varchar(100) NOT NULL,
    -- Lock #3: actual contributors feeding Shadow Balance (≥10).
    contributor_count         int NOT NULL CHECK (contributor_count >= 1),
    deprived_count            int,
    deprivation_tax_amount    numeric(14, 2),
    happiness_debt_sum        numeric(14, 2),
    happiness_debt_balance    numeric(14, 2) GENERATED ALWAYS AS (happiness_debt_sum) STORED,
    shadow_balance_sum        numeric(14, 2),
    gaap_reported_ebitda      numeric(14, 2),
    chr_real_ebitda           numeric(14, 2) GENERATED ALWAYS AS (
        round(gaap_reported_ebitda - COALESCE(happiness_debt_sum, 0) - COALESCE(deprivation_tax_amount, 0), 2)
    ) STORED,
    calculated_at             timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE shadow_balance_aggregate ADD COLUMN IF NOT EXISTS deprived_count int;
ALTER TABLE shadow_balance_aggregate ADD COLUMN IF NOT EXISTS
    happiness_debt_balance numeric(14, 2) GENERATED ALWAYS AS (happiness_debt_sum) STORED;
ALTER TABLE shadow_balance_aggregate ADD COLUMN IF NOT EXISTS gaap_reported_ebitda numeric(14, 2);
ALTER TABLE shadow_balance_aggregate ADD COLUMN IF NOT EXISTS
    chr_real_ebitda numeric(14, 2) GENERATED ALWAYS AS (
        round(gaap_reported_ebitda - COALESCE(happiness_debt_sum, 0) - COALESCE(deprivation_tax_amount, 0), 2)
    ) STORED;

CREATE INDEX IF NOT EXISTS idx_shadow_agg_org_dept
    ON shadow_balance_aggregate (org_id, department, calculated_at DESC);

-- ---------------------------------------------------------------------------
-- 8. cuckoo_alert — personal alert (locked 2026-10-12 16:14)
-- Employee first; 60-SECOND veto window; then the DIRECT manager receives it with
-- the pseudonym only and no medical details. Requires team N ≥ 10.
-- The manager NEVER reads this table (RLS = target only); the manager reads
-- cuckoo_alert_manager_v, which exposes alert_id, target_pseudonym, delivered_at only.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cuckoo_alert (
    alert_id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    manager_id                     uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    target_user_id                 uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    -- Snapshot of users.display_pseudonym at raise time (the only identity the manager sees)
    target_pseudonym               varchar(64) NOT NULL,
    org_id                         uuid REFERENCES companies(company_id) ON DELETE SET NULL,
    department                     varchar(255),
    -- Employee-visible only; never exposed to the manager.
    trigger_reason                 varchar(100) NOT NULL,
    nlp_flag_codes                 jsonb NOT NULL DEFAULT '[]'::jsonb,
    sovereign_veto_window_expiry   timestamptz NOT NULL
                                   DEFAULT (clock_timestamp() + interval '60 seconds'),
    status                         cuckoo_status_enum NOT NULL DEFAULT 'VETO_WINDOW_ACTIVE',
    -- SHA-256 (hex) of the alert's canonical payload (Q-037 locked SHA-256)
    logic_hash                     char(64) NOT NULL CHECK (logic_hash ~ '^[0-9a-f]{64}$'),
    created_at                     timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX IF NOT EXISTS idx_cuckoo_manager ON cuckoo_alert (manager_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_cuckoo_target ON cuckoo_alert (target_user_id, status);

-- ---------------------------------------------------------------------------
-- 9. avatar_state — golden_spoons (fractional) + chr_coins
-- v2 design: one-way conversion golden → CHR Coins at 1 = 50 (rpc_convert_golden_to_chr).
-- CHR Coins → golden spoons is never allowed. No real-money purchases.
-- O-16 / Q11 (locked 24.10 / 25.10): only Golden Spoons active in v1 (never expire while the employee is active).
-- v1.6.16 (Karin 30.10): CHR Coins deferred to v2 — rpc_convert_golden_to_chr is DEFINED but BLOCKED on the
-- server in v1 (every call → 422 chr_coins_deferred_to_v2; chr_coins stays 0 in v1).
-- v1.6.16 (v3 §3.3): after employment ends the employee has exit_redemption_days (30) to redeem; on day 31
-- the balance is reset to 0 by rpc_expire_departed_golden_spoons (golden_spoons_ledger 'expired_after_exit').
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS avatar_state (
    state_id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                        uuid NOT NULL UNIQUE REFERENCES users(user_id) ON DELETE CASCADE,
    role_state                     avatar_role_enum NOT NULL DEFAULT 'HOPE',
    golden_spoons                  numeric(10, 1) NOT NULL DEFAULT 0 CHECK (golden_spoons >= 0),
    -- v1.6.13 (Karin 25.10): Golden Spoons never expire while the employee is active (NULL = never expires).
    golden_spoons_expires_at       timestamptz DEFAULT NULL CHECK (golden_spoons_expires_at IS NULL),
    chr_coins                      int NOT NULL DEFAULT 0 CHECK (chr_coins >= 0),
    shop_inventory                 jsonb NOT NULL DEFAULT '[]'::jsonb,
    shop_idempotency               jsonb NOT NULL DEFAULT '{}'::jsonb,
    -- Deferred to v2 (2026-10-12): avatar weights + immunity; v1 avatar display-only
    avatar_weights                 jsonb,
    -- Deferred to v2 (2026-10-12): Contrast Nullification
    contrast_nullification_active  boolean NOT NULL DEFAULT false,
    bone_memory_latency_ms         int,
    updated_at                     timestamptz NOT NULL DEFAULT clock_timestamp()
);

ALTER TABLE avatar_state ADD COLUMN IF NOT EXISTS
    golden_spoons_expires_at timestamptz DEFAULT NULL CHECK (golden_spoons_expires_at IS NULL);
COMMENT ON COLUMN avatar_state.golden_spoons_expires_at IS
  'v1.6.13 (Karin 25.10): Golden Spoons NEVER expire while the employee is active in the organization (always NULL).';

-- One-way conversion log (append-only). Rate pinned to 50 by CHECK.
-- v1.6.16 (Karin 30.10): kept for v2 readiness; stays EMPTY in v1 because rpc_convert_golden_to_chr is blocked (422).
CREATE TABLE IF NOT EXISTS golden_chr_conversion (
    conversion_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    golden_spent     numeric(10, 1) NOT NULL CHECK (golden_spent > 0),
    rate             int NOT NULL DEFAULT 50 CHECK (rate = 50),
    chr_received     int NOT NULL,
    idempotency_key  varchar(128) NOT NULL,
    created_at       timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT chk_conversion_math CHECK (chr_received = golden_spent * rate),
    UNIQUE (user_id, idempotency_key)
);

-- ---------------------------------------------------------------------------
-- 10. manager_ledger — WORM append-only, SHA-256 hash chain (Q-037 locked 2026-10-12; O-13 locked 24.10)
--   One chain per company (org_id); genesis record (event_type = 'GENESIS', manager_id NULL) seeded
--   automatically on company creation.
--   previous_hash = current_hash of the previous record in the same org chain
--   current_hash  = sha256(previous_hash || canonical_payload)   (hex)
--   Subject identity = HMAC pseudonym only (no employee name / id / spoons / free text).
--   GDPR erasure = crypto-shredding of the subject's pseudonym key; chain stays intact.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS manager_ledger (
    ledger_id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    chain_seq              bigint GENERATED ALWAYS AS IDENTITY,
    manager_id             uuid REFERENCES users(user_id) ON DELETE CASCADE,
    org_id                 uuid REFERENCES companies(company_id) ON DELETE SET NULL,
    department             varchar(255),
    event_type             varchar(100) NOT NULL,
    amount_a               numeric(14, 2),
    amount_b               numeric(14, 2),
    -- System snapshot of the team's deprivation_tax_amount (latest team_aggregate)
    deprivation_tax_cost   numeric(14, 2),
    -- HMAC-SHA-256 pseudonym of the subject employee (never the user id)
    subject_pseudonym      char(64) CHECK (subject_pseudonym IS NULL OR subject_pseudonym ~ '^[0-9a-f]{64}$'),
    canonical_payload      text NOT NULL,
    previous_hash          char(64) CHECK (previous_hash IS NULL OR previous_hash ~ '^[0-9a-f]{64}$'),
    current_hash           char(64) NOT NULL CHECK (current_hash ~ '^[0-9a-f]{64}$'),
    restoration_status     varchar(100) NOT NULL DEFAULT 'Pending_Restoration',
    created_at             timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT uq_manager_ledger_current_hash UNIQUE (current_hash)
);

CREATE INDEX IF NOT EXISTS idx_ledger_manager_created
    ON manager_ledger (manager_id, created_at DESC);
ALTER TABLE manager_ledger ALTER COLUMN manager_id DROP NOT NULL;   -- v1.6.12 (O-13): GENESIS record has manager_id NULL
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_ledger_manager_or_genesis') THEN
    ALTER TABLE manager_ledger ADD CONSTRAINT chk_ledger_manager_or_genesis
      CHECK (event_type = 'GENESIS' OR manager_id IS NOT NULL);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_ledger_org_seq
    ON manager_ledger (org_id, chain_seq DESC);

-- Per-employee pseudonym key for crypto-shredding. Never exposed to clients.
-- v1.6.12 (O-14): scheduled_shred_at is set to employment_ended_at + 30 days on automatic offboarding
-- (cancellable if termination is reverted before shredding); self-request shreds immediately (0-day wait).
CREATE TABLE IF NOT EXISTS pseudonym_key (
    user_id            uuid PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
    key_material       bytea,              -- NULL after crypto-shredding
    created_at         timestamptz NOT NULL DEFAULT clock_timestamp(),
    scheduled_shred_at timestamptz,
    shredded_at        timestamptz,
    CONSTRAINT chk_key_or_shredded CHECK (
      (key_material IS NOT NULL AND shredded_at IS NULL)
      OR (key_material IS NULL AND shredded_at IS NOT NULL)
    )
);
ALTER TABLE pseudonym_key ADD COLUMN IF NOT EXISTS scheduled_shred_at timestamptz;

-- ---------------------------------------------------------------------------
-- Shop catalog — EverStore N-2 / 070 v5 / v1.6.13 expansion (Karin 25.10)
--   * The 8 items (theme_*, badge_*) are the opening seed catalog (קטלוג פתיחה), NOT a closed list.
--   * Categories: cosmetic, time_benefit, health_wellbeing, learning, donation, experience, gift_card, merchandise.
--   * provider text NULL (external/internal benefit provider).
--   * cosmetic_only boolean NOT NULL DEFAULT true (may be true OR false for tangible/real-world benefits).
--   * real_money_purchase_allowed = false and affects_daily_energy_spoons = false strictly locked by CHECK.
--   * Golden Spoons shelf allows ANY positive price (price_golden_spoons > 0 / price_coins > 0) across
--     tiers basic, advanced, premium, custom. CHR Coins shelf deferred to v2 (inactive in v1).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS shop_item_catalog (
    item_id                      varchar(64) PRIMARY KEY,  -- sku
    display_name                 varchar(255) NOT NULL,
    name_he                      varchar(255) NOT NULL,
    category                     text NOT NULL DEFAULT 'cosmetic'
                                 CHECK (category IN ('cosmetic', 'time_benefit', 'health_wellbeing',
                                                     'learning', 'donation', 'experience', 'gift_card', 'merchandise')),
    provider                     text NULL,
    tier                         shop_tier_enum NOT NULL DEFAULT 'basic',
    price_coins                  numeric(10, 1),
    price_golden_spoons          numeric(10, 1) GENERATED ALWAYS AS (
        CASE WHEN currency = 'golden_spoons' THEN price_coins END
    ) STORED,
    currency                     text NOT NULL DEFAULT 'golden_spoons'
                                 CHECK (currency IN ('chr_coins', 'golden_spoons')),
    cosmetic_only                boolean NOT NULL DEFAULT true,
    real_money_purchase_allowed  boolean NOT NULL DEFAULT false
                                 CHECK (real_money_purchase_allowed = false),
    affects_daily_energy_spoons  boolean NOT NULL DEFAULT false
                                 CHECK (affects_daily_energy_spoons = false),
    is_active                    boolean NOT NULL DEFAULT true,
    created_at                   timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT chk_golden_shelf_price CHECK (
      currency <> 'golden_spoons'
      OR (price_coins IS NOT NULL AND price_coins > 0 AND price_golden_spoons > 0)
    ),
    -- O-16 (Karin 24.10): CHR Coins deferred to v2 → CHR rows must stay inactive in v1
    CONSTRAINT chk_chr_shelf_todo CHECK (currency <> 'chr_coins' OR is_active = false)
);

-- v1.6.13 upgrade path for an existing shop_item_catalog table
ALTER TABLE shop_item_catalog ADD COLUMN IF NOT EXISTS category text NOT NULL DEFAULT 'cosmetic';
ALTER TABLE shop_item_catalog ADD COLUMN IF NOT EXISTS provider text NULL;
ALTER TABLE shop_item_catalog ADD COLUMN IF NOT EXISTS real_money_purchase_allowed boolean NOT NULL DEFAULT false;
ALTER TABLE shop_item_catalog ADD COLUMN IF NOT EXISTS affects_daily_energy_spoons boolean NOT NULL DEFAULT false;
ALTER TABLE shop_item_catalog DROP CONSTRAINT IF EXISTS chk_golden_shelf_price;
ALTER TABLE shop_item_catalog DROP CONSTRAINT IF EXISTS chk_cosmetic_only;
ALTER TABLE shop_item_catalog DROP CONSTRAINT IF EXISTS shop_item_catalog_cosmetic_only_check;
DO $$
BEGIN
  IF (SELECT data_type FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = 'shop_item_catalog' AND column_name = 'price_coins') = 'integer' THEN
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'public' AND table_name = 'shop_item_catalog' AND column_name = 'price_golden_spoons') THEN
      ALTER TABLE shop_item_catalog DROP COLUMN price_golden_spoons;
    END IF;
    ALTER TABLE shop_item_catalog ALTER COLUMN price_coins TYPE numeric(10, 1);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'shop_item_catalog' AND column_name = 'price_golden_spoons') THEN
    ALTER TABLE shop_item_catalog ADD COLUMN price_golden_spoons numeric(10, 1) GENERATED ALWAYS AS (
        CASE WHEN currency = 'golden_spoons' THEN price_coins END
    ) STORED;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'shop_item_catalog_category_check') THEN
    ALTER TABLE shop_item_catalog ADD CONSTRAINT shop_item_catalog_category_check
      CHECK (category IN ('cosmetic', 'time_benefit', 'health_wellbeing',
                          'learning', 'donation', 'experience', 'gift_card', 'merchandise'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'shop_item_catalog_real_money_purchase_allowed_check') THEN
    ALTER TABLE shop_item_catalog ADD CONSTRAINT shop_item_catalog_real_money_purchase_allowed_check
      CHECK (real_money_purchase_allowed = false);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'shop_item_catalog_affects_daily_energy_spoons_check') THEN
    ALTER TABLE shop_item_catalog ADD CONSTRAINT shop_item_catalog_affects_daily_energy_spoons_check
      CHECK (affects_daily_energy_spoons = false);
  END IF;
  ALTER TABLE shop_item_catalog ADD CONSTRAINT chk_golden_shelf_price CHECK (
    currency <> 'golden_spoons'
    OR (price_coins IS NOT NULL AND price_coins > 0 AND price_golden_spoons > 0)
  );
END $$;

COMMENT ON TABLE shop_item_catalog IS
  'EverStore catalog (v1.6.13, Karin 25.10): opening seed catalog (קטלוג פתיחה, 8 items) + expandable across 8 categories (cosmetic, time_benefit, health_wellbeing, learning, donation, experience, gift_card, merchandise) with any positive price_golden_spoons > 0. real_money_purchase_allowed=false and affects_daily_energy_spoons=false strictly locked. CHR shelf deferred to v2.';

-- Opening seed catalog (קטלוג פתיחה — 8 items; currency = golden_spoons, category = cosmetic)
INSERT INTO shop_item_catalog (
  item_id, display_name, name_he, category, provider, tier, price_coins, currency, cosmetic_only
) VALUES
  ('theme_basement_office',       'Basement Office theme',           'רקע משרד המרתף',              'cosmetic', NULL, 'basic',    10, 'golden_spoons', true),
  ('theme_somatic_zone',          'Somatic regulation zone theme',   'רקע מתחם וויסות סומטי',       'cosmetic', NULL, 'basic',    10, 'golden_spoons', true),
  ('theme_coworking_floor',       'Co-Working floor theme',          'רקע קומת Co-Working',         'cosmetic', NULL, 'advanced', 20, 'golden_spoons', true),
  ('theme_penthouse',             'Penthouse theme',                 'רקע הפנטהאוז',                 'cosmetic', NULL, 'advanced', 20, 'golden_spoons', true),
  ('badge_passive_pilgrim',       'Passive Pilgrim badge',           'תג צליין פסיבי',              'cosmetic', NULL, 'basic',    10, 'golden_spoons', true),
  ('badge_corporate_cyborg',      'Corporate Cyborg badge',          'תג סייבורג תאגידי',            'cosmetic', NULL, 'advanced', 20, 'golden_spoons', true),
  ('badge_leading_entrepreneur',  'Leading Entrepreneur badge',      'תג יזם מוביל',                 'cosmetic', NULL, 'advanced', 20, 'golden_spoons', true),
  ('badge_focus_friday_noren',    'Focus Friday / Noren Pass badge', 'תג Focus Friday / Noren Pass', 'cosmetic', NULL, 'basic',    10, 'golden_spoons', true)
ON CONFLICT (item_id) DO UPDATE SET
  display_name  = EXCLUDED.display_name,
  name_he       = EXCLUDED.name_he,
  category      = EXCLUDED.category,
  tier          = EXCLUDED.tier,
  price_coins   = EXCLUDED.price_coins,
  currency      = EXCLUDED.currency,
  cosmetic_only = EXCLUDED.cosmetic_only,
  is_active     = true;

-- Deactivate legacy placeholders if present
UPDATE shop_item_catalog
   SET is_active = false
 WHERE item_id IN ('basic_placeholder', 'advanced_placeholder');

-- ---------------------------------------------------------------------------
-- v1.6.13 (Karin 25.10): EverStore purchase history & Time-benefit voucher privacy (נעילת הפרגוד)
--   * shop_purchase (employee-only RLS: auth.uid() = user_id; managers/HR/board have ZERO access).
--   * approved_absence_entry: when an employee purchases or redeems a time_benefit item in EverStore,
--     it converts automatically through HR into a standard approved absence / refresh time entry
--     ('זמן התרעננות / היעדרות מאושרת') with NO link to shop_purchase, item_id, or Golden Spoons,
--     so the direct manager coordinates the schedule via approved_absence_manager_v without ever
--     seeing that the voucher came from an EverStore purchase.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS shop_purchase (
    purchase_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id            uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    item_id            varchar(64) NOT NULL REFERENCES shop_item_catalog(item_id),
    category           text NOT NULL,
    price_golden_spoons numeric(10, 1) NOT NULL CHECK (price_golden_spoons > 0),
    cosmetic_only      boolean NOT NULL,
    idempotency_key    varchar(128) NOT NULL,
    purchased_at       timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (user_id, idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_shop_purchase_user ON shop_purchase (user_id, purchased_at DESC);

-- Standard HR approved absence / refresh time entry (נעילת הפרגוד: no item_id, no purchase_id, no spoons).
CREATE TABLE IF NOT EXISTS approved_absence_entry (
    absence_id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id            uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    company_id         uuid REFERENCES companies(company_id) ON DELETE CASCADE,
    requested_date     date NOT NULL,
    entry_type         text NOT NULL DEFAULT 'approved_absence'
                       CHECK (entry_type = 'approved_absence'),
    entry_text         text NOT NULL DEFAULT 'זמן התרעננות / היעדרות מאושרת'
                       CHECK (entry_text = 'זמן התרעננות / היעדרות מאושרת'),
    schedule_status    text NOT NULL DEFAULT 'pending_coordination'
                       CONSTRAINT approved_absence_entry_schedule_status_check
                       CHECK (schedule_status IN ('pending_coordination', 'coordinated', 'cancelled')),
    created_at         timestamptz NOT NULL DEFAULT clock_timestamp(),
    -- v1.6.18 (A-13): cancellation of an entry scheduled after the end of employment (no EverStore reference)
    cancelled_at       timestamptz,
    cancel_reason      text CHECK (cancel_reason IN ('employment_ended')),
    CONSTRAINT chk_absence_cancel_shape CHECK ((schedule_status = 'cancelled') = (cancelled_at IS NOT NULL AND cancel_reason IS NOT NULL))
);
-- v1.6.18 upgrade of a v1.6.17 table (adds the 'cancelled' status and the cancellation columns; no-op when present).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public'
                  AND table_name = 'approved_absence_entry' AND column_name = 'cancelled_at') THEN
    ALTER TABLE approved_absence_entry DROP CONSTRAINT IF EXISTS approved_absence_entry_schedule_status_check;
    ALTER TABLE approved_absence_entry ADD CONSTRAINT approved_absence_entry_schedule_status_check
      CHECK (schedule_status IN ('pending_coordination', 'coordinated', 'cancelled'));
    ALTER TABLE approved_absence_entry ADD COLUMN cancelled_at timestamptz;
    ALTER TABLE approved_absence_entry ADD COLUMN cancel_reason text CHECK (cancel_reason IN ('employment_ended'));
    ALTER TABLE approved_absence_entry ADD CONSTRAINT chk_absence_cancel_shape
      CHECK ((schedule_status = 'cancelled') = (cancelled_at IS NOT NULL AND cancel_reason IS NOT NULL));
  END IF;
END $$;

-- v1.6.18 (A-13) time_benefit_absence_link — CLOSED internal link from an approved absence to the EverStore
-- time_benefit purchase it came from (price snapshot), needed only to refund that purchase when the absence
-- is cancelled after the end of employment. RLS forced, no client grant, never in a manager view or any RPC
-- output (נעילת הפרגוד: approved_absence_entry itself still holds no purchase, item or Golden Spoons column).
CREATE TABLE IF NOT EXISTS time_benefit_absence_link (
    absence_id           uuid PRIMARY KEY REFERENCES approved_absence_entry(absence_id) ON DELETE CASCADE,
    purchase_id          uuid NOT NULL UNIQUE REFERENCES shop_purchase(purchase_id) ON DELETE CASCADE,
    price_golden_spoons  numeric(10, 1) NOT NULL CHECK (price_golden_spoons > 0),
    created_at           timestamptz NOT NULL DEFAULT clock_timestamp()
);
-- v1.6.18 (A-13) time_benefit_refund — WORM record of each refund (one per absence = idempotency backstop).
CREATE TABLE IF NOT EXISTS time_benefit_refund (
    absence_id      uuid PRIMARY KEY REFERENCES approved_absence_entry(absence_id) ON DELETE CASCADE,
    amount          numeric(10, 1) NOT NULL CHECK (amount > 0),
    refund_reason   text NOT NULL CHECK (refund_reason IN ('employment_ended')),
    refunded_at     timestamptz NOT NULL DEFAULT clock_timestamp()
);
-- v1.6.18 upgrade: a v1.6.17 database has no link rows. Each unlinked time_benefit purchase is matched to the
-- same employee's unlinked absence created in the same purchase call (created_at within 5 seconds after
-- purchased_at, closest first). Unmatched rows stay unlinked (their cancellation refunds nothing; reported).
INSERT INTO time_benefit_absence_link (absence_id, purchase_id, price_golden_spoons)
SELECT DISTINCT ON (m.purchase_id) m.absence_id, m.purchase_id, m.price_golden_spoons
  FROM (SELECT p.purchase_id, p.price_golden_spoons, a.absence_id,
               a.created_at - p.purchased_at AS gap
          FROM shop_purchase p
          JOIN approved_absence_entry a ON a.user_id = p.user_id
                                       AND a.created_at >= p.purchased_at
                                       AND a.created_at < p.purchased_at + interval '5 seconds'
         WHERE p.category = 'time_benefit'
           AND NOT EXISTS (SELECT 1 FROM time_benefit_absence_link l WHERE l.purchase_id = p.purchase_id)
           AND NOT EXISTS (SELECT 1 FROM time_benefit_absence_link l WHERE l.absence_id = a.absence_id)) m
 ORDER BY m.purchase_id, m.gap
ON CONFLICT DO NOTHING;

COMMENT ON TABLE approved_absence_entry IS
  'v1.6.13 (Karin 25.10, נעילת הפרגוד): Standard HR approved absence / refresh time entry (זמן התרעננות / היעדרות מאושרת). Contains zero reference to EverStore, item_id, or Golden Spoons.';

CREATE INDEX IF NOT EXISTS idx_approved_absence_user ON approved_absence_entry (user_id, requested_date DESC);
-- ---------------------------------------------------------------------------
-- Generic questionnaires (replaces pcq12_monthly_reward of 1.4)
-- v1.6.16 (v3 §3.6 + Karin 30.10): Golden Spoons are given for PARTICIPATION only, a fixed amount that never
-- depends on the answers. reward_type = 'participation'; the amount is read at submit time from
-- agent_settings[reward_setting_key] (never a code constant). reward_amount is legacy and always NULL.
-- Locked catalogue (is_locked = true), pinned by CHECK:
--   PCQ-12  monthly    golden_spoons_per_questionnaire            (Karin 30.10: 10 כפיות)
--   Cantril monthly    golden_spoons_per_questionnaire            (Karin 31.10: monthly → 10 כפיות; replaces J-3's 2)
--   IHS     quarterly  golden_spoons_per_quarterly_questionnaire  (Karin 31.10: 10 כפיות, adjustable)
--   TPS-12  quarterly  golden_spoons_per_quarterly_questionnaire  (Karin 31.10: 10 כפיות, adjustable); score = (sum − 12) / 48 × 100;
--           items 1,3,5,11 reversed (6 − x); all 12 required; new employee only after 30 days.
-- HR-defined future questionnaires (is_locked = false): frequency daily..monthly; monthly →
-- golden_spoons_per_questionnaire, daily / weekly → golden_spoons_per_short_questionnaire.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS questionnaire_definition (
    code             varchar(32) PRIMARY KEY,
    name_en          varchar(255) NOT NULL,
    name_he          varchar(255) NOT NULL,
    frequency        text NOT NULL
                     CHECK (frequency IN ('daily', 'weekly', 'monthly', 'quarterly', 'half_yearly', 'yearly')),
    reward_type      text NOT NULL DEFAULT 'participation' CHECK (reward_type = 'participation'),
    reward_amount    numeric(4, 1),     -- legacy (≤ v1.6.13); always NULL from v1.6.16
    reward_setting_key text NOT NULL CHECK (reward_setting_key IN ('golden_spoons_per_questionnaire',
                                            'golden_spoons_per_short_questionnaire',
                                            'golden_spoons_per_quarterly_questionnaire')),
    item_count       int NOT NULL CHECK (item_count >= 1),
    answer_min       int,              -- NULL = range not constrained
    answer_max       int,
    reversed_items   int[] NOT NULL DEFAULT '{}',   -- 1-based item numbers
    all_required     boolean NOT NULL DEFAULT true,
    min_tenure_days  int NOT NULL DEFAULT 0 CHECK (min_tenure_days >= 0),
    -- none = no score; tps12 = TPS-12; ihs = IHS ((mean−1)/4×100, O-6); pcq12 = PCQ-12 ((mean−1)/5×100, O-7)
    scoring_method   text NOT NULL DEFAULT 'none' CHECK (scoring_method IN ('none', 'tps12', 'ihs', 'pcq12')),
    is_locked        boolean NOT NULL DEFAULT false,
    is_active        boolean NOT NULL DEFAULT true,
    updated_at       timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT chk_reward_shape CHECK (reward_type = 'participation' AND reward_amount IS NULL),
    CONSTRAINT chk_answer_range CHECK (
      (answer_min IS NULL AND answer_max IS NULL) OR (answer_min IS NOT NULL AND answer_max >= answer_min)
    ),
    -- Locked catalogue cannot drift
    CONSTRAINT chk_locked_catalogue CHECK (
      NOT is_locked
      OR (code = 'PCQ-12'  AND frequency = 'monthly'   AND reward_setting_key = 'golden_spoons_per_questionnaire'
          AND item_count = 12 AND answer_min = 1 AND answer_max = 6 AND all_required AND scoring_method = 'pcq12')
      OR (code = 'Cantril' AND frequency = 'monthly'   AND reward_setting_key = 'golden_spoons_per_questionnaire')
      OR (code = 'IHS'     AND frequency = 'quarterly' AND reward_setting_key = 'golden_spoons_per_quarterly_questionnaire'
          AND answer_min = 1 AND answer_max = 5 AND all_required AND scoring_method = 'ihs')
      OR (code = 'TPS-12'  AND frequency = 'quarterly' AND reward_setting_key = 'golden_spoons_per_quarterly_questionnaire'
          AND item_count = 12 AND answer_min = 1 AND answer_max = 5
          AND reversed_items = '{1,3,5,11}' AND all_required AND min_tenure_days = 30
          AND scoring_method = 'tps12')
    ),
    -- HR-editable future questionnaires: daily..monthly; the fixed amount comes from agent_settings
    CONSTRAINT chk_hr_editable CHECK (
      is_locked
      OR (frequency IN ('daily', 'weekly', 'monthly')
          AND reward_setting_key = CASE WHEN frequency = 'monthly' THEN 'golden_spoons_per_questionnaire'
                                        ELSE 'golden_spoons_per_short_questionnaire' END)
    )
);

-- v1.6.16 upgrade (v3 §3.6): an existing questionnaire_definition moves to participation-only rewards.
-- Old reward CHECKs are dropped first, rows are re-keyed, then the fresh-table CHECKs are re-added.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public'
                  AND table_name = 'questionnaire_definition' AND column_name = 'reward_setting_key') THEN
    ALTER TABLE questionnaire_definition DROP CONSTRAINT IF EXISTS chk_reward_shape;
    ALTER TABLE questionnaire_definition DROP CONSTRAINT IF EXISTS chk_score_div10_needs_scoring;
    ALTER TABLE questionnaire_definition DROP CONSTRAINT IF EXISTS chk_locked_catalogue;
    ALTER TABLE questionnaire_definition DROP CONSTRAINT IF EXISTS chk_hr_editable;
    ALTER TABLE questionnaire_definition DROP CONSTRAINT IF EXISTS questionnaire_definition_reward_type_check;
    ALTER TABLE questionnaire_definition ADD COLUMN reward_setting_key text;
    UPDATE questionnaire_definition
       SET reward_type = 'participation', reward_amount = NULL,
           reward_setting_key = CASE
             WHEN frequency IN ('quarterly', 'half_yearly', 'yearly') THEN 'golden_spoons_per_quarterly_questionnaire'
             WHEN frequency = 'monthly' THEN 'golden_spoons_per_questionnaire'
             ELSE 'golden_spoons_per_short_questionnaire' END;
    ALTER TABLE questionnaire_definition ALTER COLUMN reward_setting_key SET NOT NULL;
    ALTER TABLE questionnaire_definition ALTER COLUMN reward_type SET DEFAULT 'participation';
    ALTER TABLE questionnaire_definition ADD CONSTRAINT questionnaire_definition_reward_type_check
      CHECK (reward_type = 'participation');
    ALTER TABLE questionnaire_definition ADD CONSTRAINT questionnaire_definition_reward_setting_key_check
      CHECK (reward_setting_key IN ('golden_spoons_per_questionnaire', 'golden_spoons_per_short_questionnaire',
                                    'golden_spoons_per_quarterly_questionnaire'));
    ALTER TABLE questionnaire_definition ADD CONSTRAINT chk_reward_shape
      CHECK (reward_type = 'participation' AND reward_amount IS NULL);
    ALTER TABLE questionnaire_definition ADD CONSTRAINT chk_locked_catalogue CHECK (
      NOT is_locked
      OR (code = 'PCQ-12'  AND frequency = 'monthly'   AND reward_setting_key = 'golden_spoons_per_questionnaire'
          AND item_count = 12 AND answer_min = 1 AND answer_max = 6 AND all_required AND scoring_method = 'pcq12')
      OR (code = 'Cantril' AND frequency = 'monthly'   AND reward_setting_key = 'golden_spoons_per_questionnaire')
      OR (code = 'IHS'     AND frequency = 'quarterly' AND reward_setting_key = 'golden_spoons_per_quarterly_questionnaire'
          AND answer_min = 1 AND answer_max = 5 AND all_required AND scoring_method = 'ihs')
      OR (code = 'TPS-12'  AND frequency = 'quarterly' AND reward_setting_key = 'golden_spoons_per_quarterly_questionnaire'
          AND item_count = 12 AND answer_min = 1 AND answer_max = 5
          AND reversed_items = '{1,3,5,11}' AND all_required AND min_tenure_days = 30
          AND scoring_method = 'tps12'));
    ALTER TABLE questionnaire_definition ADD CONSTRAINT chk_hr_editable CHECK (
      is_locked
      OR (frequency IN ('daily', 'weekly', 'monthly')
          AND reward_setting_key = CASE WHEN frequency = 'monthly' THEN 'golden_spoons_per_questionnaire'
                                        ELSE 'golden_spoons_per_short_questionnaire' END));
  END IF;
END $$;

-- v1.6.17 upgrade (Karin 31.10, J-3 reversed): a v1.6.16 database keyed Cantril to the short setting (2).
-- Re-key it to the monthly setting (10) and re-pin the locked catalogue. No-op on a fresh / current database.
-- Runs BEFORE the seed INSERT: its CHECK is evaluated before ON CONFLICT DO NOTHING.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM questionnaire_definition
              WHERE code = 'Cantril' AND reward_setting_key <> 'golden_spoons_per_questionnaire') THEN
    ALTER TABLE questionnaire_definition DROP CONSTRAINT IF EXISTS chk_locked_catalogue;
    UPDATE questionnaire_definition SET reward_setting_key = 'golden_spoons_per_questionnaire', updated_at = clock_timestamp()
     WHERE code = 'Cantril';
    ALTER TABLE questionnaire_definition ADD CONSTRAINT chk_locked_catalogue CHECK (
      NOT is_locked
      OR (code = 'PCQ-12'  AND frequency = 'monthly'   AND reward_setting_key = 'golden_spoons_per_questionnaire'
          AND item_count = 12 AND answer_min = 1 AND answer_max = 6 AND all_required AND scoring_method = 'pcq12')
      OR (code = 'Cantril' AND frequency = 'monthly'   AND reward_setting_key = 'golden_spoons_per_questionnaire')
      OR (code = 'IHS'     AND frequency = 'quarterly' AND reward_setting_key = 'golden_spoons_per_quarterly_questionnaire'
          AND answer_min = 1 AND answer_max = 5 AND all_required AND scoring_method = 'ihs')
      OR (code = 'TPS-12'  AND frequency = 'quarterly' AND reward_setting_key = 'golden_spoons_per_quarterly_questionnaire'
          AND item_count = 12 AND answer_min = 1 AND answer_max = 5
          AND reversed_items = '{1,3,5,11}' AND all_required AND min_tenure_days = 30
          AND scoring_method = 'tps12'));
  END IF;
END $$;

INSERT INTO questionnaire_definition (
  code, name_en, name_he, frequency, reward_type, reward_amount, reward_setting_key, item_count,
  answer_min, answer_max, reversed_items, all_required, min_tenure_days, scoring_method, is_locked
) VALUES
  -- v1.6.12 (Karin 24.10, O-7): PCQ-12 Luthans 1–6 scale, 12 items, all required; score = (mean − 1) / 5.0 × 100
  -- v1.6.16 (Karin 30.10): participation reward = agent_settings.golden_spoons_per_questionnaire (10)
  ('PCQ-12',  'PCQ-12', 'PCQ-12', 'monthly', 'participation', NULL, 'golden_spoons_per_questionnaire', 12, 1, 6, '{}', true, 0, 'pcq12', true),
  ('Cantril', 'Cantril ladder — life satisfaction', 'סולם Cantril — שביעות רצון מהחיים',
              'monthly', 'participation', NULL, 'golden_spoons_per_questionnaire', 1, 0, 10, '{}', true, 0, 'none', true),
  -- v1.6.11 (Karin 24.10, O-6): IHS score = (mean − 1) / 4 × 100 from 1–5 answers (score is NOT a reward input any more)
  ('IHS',     'IHS — Interdependent Happiness Scale', 'IHS — מדד האושר הבין-תלוי',
              'quarterly', 'participation', NULL, 'golden_spoons_per_quarterly_questionnaire', 9, 1, 5, '{}', true, 0, 'ihs', true),
  ('TPS-12',  'TPS-12 — Team Psychological Safety', 'TPS-12 — בטיחות פסיכולוגית צוותית',
              'quarterly', 'participation', NULL, 'golden_spoons_per_quarterly_questionnaire', 12, 1, 5, '{1,3,5,11}', true, 30, 'tps12', true)
ON CONFLICT (code) DO NOTHING;

-- Submissions: once per period (employee timezone), answers immutable (WORM).
CREATE TABLE IF NOT EXISTS questionnaire_submission (
    submission_id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id               uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    questionnaire_code    varchar(32) NOT NULL REFERENCES questionnaire_definition(code),
    period_key            text NOT NULL,          -- e.g. 2026-10, 2026-Q4 (employee-local)
    local_date            date NOT NULL,
    answers               int[] NOT NULL,
    score                 numeric(5, 2),          -- 0–100 where a scorer is encoded
    -- TPS-12, IHS and PCQ-12 score fields
    tps_12_score          numeric(5, 2) GENERATED ALWAYS AS (
        CASE WHEN questionnaire_code = 'TPS-12' THEN score END
    ) STORED,
    ihs_score             numeric(5, 2) GENERATED ALWAYS AS (
        CASE WHEN questionnaire_code = 'IHS' THEN score END
    ) STORED,
    pcq12_score           numeric(5, 2) GENERATED ALWAYS AS (
        CASE WHEN questionnaire_code = 'PCQ-12' THEN score END
    ) STORED,
    reward_golden_spoons  numeric(10, 1) NOT NULL CHECK (reward_golden_spoons >= 0),
    submitted_at          timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT uq_submission_once_per_period UNIQUE (user_id, questionnaire_code, period_key)
);

ALTER TABLE questionnaire_submission ADD COLUMN IF NOT EXISTS
    ihs_score numeric(5, 2) GENERATED ALWAYS AS (
        CASE WHEN questionnaire_code = 'IHS' THEN score END
    ) STORED;
ALTER TABLE questionnaire_submission ADD COLUMN IF NOT EXISTS
    pcq12_score numeric(5, 2) GENERATED ALWAYS AS (
        CASE WHEN questionnaire_code = 'PCQ-12' THEN score END
    ) STORED;
-- Upgrade path for an earlier database where IHS or PCQ-12 had old scoring_method / range
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM questionnaire_definition WHERE (code = 'IHS' AND scoring_method <> 'ihs')
                                                       OR (code = 'PCQ-12' AND scoring_method <> 'pcq12'))
     AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public'
                      AND table_name = 'questionnaire_definition' AND column_name = 'reward_setting_key') THEN
    ALTER TABLE questionnaire_definition DROP CONSTRAINT IF EXISTS questionnaire_definition_scoring_method_check;
    ALTER TABLE questionnaire_definition DROP CONSTRAINT IF EXISTS chk_locked_catalogue;
    UPDATE questionnaire_definition
       SET item_count = 9, answer_min = 1, answer_max = 5, all_required = true, scoring_method = 'ihs'
     WHERE code = 'IHS';
    UPDATE questionnaire_definition
       SET item_count = 12, answer_min = 1, answer_max = 6, all_required = true, scoring_method = 'pcq12'
     WHERE code = 'PCQ-12';
    ALTER TABLE questionnaire_definition ADD CONSTRAINT questionnaire_definition_scoring_method_check
      CHECK (scoring_method IN ('none', 'tps12', 'ihs', 'pcq12'));
    ALTER TABLE questionnaire_definition ADD CONSTRAINT chk_locked_catalogue CHECK (
      NOT is_locked
      OR (code = 'PCQ-12'  AND frequency = 'monthly'   AND reward_type = 'fixed'       AND reward_amount = 10
          AND item_count = 12 AND answer_min = 1 AND answer_max = 6 AND all_required AND scoring_method = 'pcq12')
      OR (code = 'Cantril' AND frequency = 'monthly'   AND reward_type = 'fixed'       AND reward_amount = 2.5)
      OR (code = 'IHS'     AND frequency = 'quarterly' AND reward_type = 'score_div10'
          AND answer_min = 1 AND answer_max = 5 AND all_required AND scoring_method = 'ihs')
      OR (code = 'TPS-12'  AND frequency = 'quarterly' AND reward_type = 'score_div10'
          AND item_count = 12 AND answer_min = 1 AND answer_max = 5
          AND reversed_items = '{1,3,5,11}' AND all_required AND min_tenure_days = 30
          AND scoring_method = 'tps12')
    );
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_qsub_code_period ON questionnaire_submission (questionnaire_code, period_key);

-- 1.4 pcq12_monthly_reward is NOT created any more. If a 1.4 database still has it,
-- migrations/migrate_v1_4_to_v1_6_13.sql freezes it as legacy_v1_4_pcq12_monthly_reward.

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
-- Pure helpers: periods, rounding, TPS-12
-- =============================================================================

-- Period key for a frequency at an employee-local date.
CREATE OR REPLACE FUNCTION fn_period_key(p_frequency text, p_local_date date)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_frequency
    WHEN 'daily'       THEN to_char(p_local_date, 'YYYY-MM-DD')
    WHEN 'weekly'      THEN to_char(p_local_date, 'IYYY-"W"IW')
    WHEN 'monthly'     THEN to_char(p_local_date, 'YYYY-MM')
    WHEN 'quarterly'   THEN to_char(p_local_date, 'YYYY-"Q"Q')
    WHEN 'half_yearly' THEN to_char(p_local_date, 'YYYY') || '-H' || CASE WHEN extract(month FROM p_local_date) <= 6 THEN '1' ELSE '2' END
    WHEN 'yearly'      THEN to_char(p_local_date, 'YYYY')
  END
$$;

-- Last-digit rounding (locked 14:16): 0–2 down to the ten; 3–5 → 5; 6–9 up to next ten.
CREATE OR REPLACE FUNCTION fn_round_score_last_digit(p_score int)
RETURNS int
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_score % 10 <= 2 THEN p_score - p_score % 10
    WHEN p_score % 10 <= 5 THEN p_score - p_score % 10 + 5
    ELSE p_score - p_score % 10 + 10
  END
$$;

-- v1.6.16 (v3 §3.6, test 12): the score/10 Golden Spoons reward is CANCELLED — no function may compute
-- Golden Spoons from a questionnaire score. fn_reward_score_div10 (O-8) is removed.
DROP FUNCTION IF EXISTS fn_reward_score_div10(numeric);

-- O-6 (Karin 24.10): IHS score 0–100 = (mean − 1) / 4 × 100 from 1–5 questionnaire answers.
-- Reversed items (if any) are scored 6 − x. Returns NULL if answers are empty or out of 1..5.
CREATE OR REPLACE FUNCTION fn_ihs_score(p_answers int[], p_reversed int[] DEFAULT '{}')
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_answers IS NULL OR cardinality(p_answers) < 1 THEN NULL
    WHEN EXISTS (SELECT 1 FROM unnest(p_answers) a WHERE a IS NULL OR a < 1 OR a > 5) THEN NULL
    ELSE round(((SELECT avg(CASE WHEN i = ANY (COALESCE(p_reversed, '{}')) THEN (6 - p_answers[i])::numeric ELSE p_answers[i]::numeric END)
                   FROM generate_subscripts(p_answers, 1) AS i) - 1) / 4.0 * 100, 2)
  END
$$;

-- O-7 (Karin 24.10): PCQ-12 score 0–100 = (mean − 1) / 5.0 × 100 from 12 required answers on the 1–6 Luthans scale.
-- Reversed items (if any) are scored 7 − x. Returns NULL if answers are incomplete or out of 1..6.
CREATE OR REPLACE FUNCTION fn_pcq12_score(p_answers int[], p_reversed int[] DEFAULT '{}')
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_answers IS NULL OR cardinality(p_answers) <> 12 THEN NULL
    WHEN EXISTS (SELECT 1 FROM unnest(p_answers) a WHERE a IS NULL OR a < 1 OR a > 6) THEN NULL
    ELSE round(((SELECT avg(CASE WHEN i = ANY (COALESCE(p_reversed, '{}')) THEN (7 - p_answers[i])::numeric ELSE p_answers[i]::numeric END)
                   FROM generate_subscripts(p_answers, 1) AS i) - 1) / 5.0 * 100, 2)
  END
$$;

-- TPS-12 score 0–100 = (sum − 12) / 48 × 100; reversed items scored 6 − x.
-- p_reversed holds 1-based item numbers. Returns NULL if answers are incomplete/invalid.
CREATE OR REPLACE FUNCTION fn_tps12_score(p_answers int[], p_reversed int[])
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_answers IS NULL OR cardinality(p_answers) <> 12 THEN NULL
    WHEN EXISTS (SELECT 1 FROM unnest(p_answers) a WHERE a IS NULL OR a < 1 OR a > 5) THEN NULL
    ELSE round(((SELECT sum(CASE WHEN i = ANY (p_reversed) THEN 6 - p_answers[i] ELSE p_answers[i] END)
                   FROM generate_subscripts(p_answers, 1) AS i) - 12) / 48.0 * 100, 2)
  END
$$;

-- TPS-12 band (locked 14:41): < 52 low · 52–60 medium · > 60 good.
CREATE OR REPLACE FUNCTION fn_tps_band(p_score numeric)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_score IS NULL THEN NULL
    WHEN p_score < 52 THEN 'low'
    WHEN p_score <= 60 THEN 'medium'
    ELSE 'good'
  END
$$;

-- =============================================================================
-- Triggers: privacy thresholds, WORM tables, ledger hash chain
-- CB / Anti-GET live in RPC. No HRV in CB.
-- =============================================================================

-- Minimum N for a privacy scope (regular 5; cuckoo / shadow_balance / emergency 10).
CREATE OR REPLACE FUNCTION fn_privacy_min_n(p_scope text)
RETURNS int
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT min_n FROM privacy_threshold_config WHERE scope = p_scope
$$;

-- Raise 403 aggregation_privacy_threshold when N is below the scope minimum.
CREATE OR REPLACE FUNCTION fn_assert_privacy_threshold(p_n int, p_scope text)
RETURNS void
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_min int := fn_privacy_min_n(p_scope);
BEGIN
  IF v_min IS NULL OR p_n IS NULL OR p_n < v_min THEN
    RAISE EXCEPTION 'aggregation_privacy_threshold'
      USING ERRCODE = '42501',
            DETAIL = 'http_hint=403;code=aggregation_privacy_threshold',
            HINT = 'aggregation_privacy_threshold';
  END IF;
END;
$$;

-- Row trigger: contributor_count (actual contributors, lock #3) must meet the scope in TG_ARGV[0].
CREATE OR REPLACE FUNCTION enforce_privacy_threshold()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM fn_assert_privacy_threshold(NEW.contributor_count, TG_ARGV[0]);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_rule_of_5 ON team_aggregate;
DROP TRIGGER IF EXISTS trg_team_aggregate_threshold ON team_aggregate;
CREATE TRIGGER trg_team_aggregate_threshold
    BEFORE INSERT OR UPDATE OF contributor_count ON team_aggregate
    FOR EACH ROW
    EXECUTE FUNCTION enforce_privacy_threshold('regular');

DROP TRIGGER IF EXISTS trg_shadow_balance_threshold ON shadow_balance_aggregate;
CREATE TRIGGER trg_shadow_balance_threshold
    BEFORE INSERT OR UPDATE OF contributor_count ON shadow_balance_aggregate
    FOR EACH ROW
    EXECUTE FUNCTION enforce_privacy_threshold('shadow_balance');

-- WORM: any UPDATE/DELETE raises the business code passed as TG_ARGV[0] (HTTP 403).
CREATE OR REPLACE FUNCTION fn_worm_immutable()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION '%', TG_ARGV[0]
    USING ERRCODE = '42501',
          DETAIL = format('http_hint=403;code=%s', TG_ARGV[0]),
          HINT = TG_ARGV[0];
  RETURN NULL;
END;
$$;

-- Kept for compatibility with 1.4 callers.
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
    EXECUTE FUNCTION fn_worm_immutable('ledger_immutable');

DROP TRIGGER IF EXISTS trg_questionnaire_submission_worm ON questionnaire_submission;
CREATE TRIGGER trg_questionnaire_submission_worm
    BEFORE UPDATE OR DELETE ON questionnaire_submission
    FOR EACH ROW
    EXECUTE FUNCTION fn_worm_immutable('questionnaire_immutable');

DROP TRIGGER IF EXISTS trg_early_leave_worm ON early_leave_log;
CREATE TRIGGER trg_early_leave_worm
    BEFORE UPDATE OR DELETE ON early_leave_log
    FOR EACH ROW
    EXECUTE FUNCTION fn_worm_immutable('ledger_immutable');

DROP TRIGGER IF EXISTS trg_conversion_worm ON golden_chr_conversion;
CREATE TRIGGER trg_conversion_worm
    BEFORE UPDATE OR DELETE ON golden_chr_conversion
    FOR EACH ROW
    EXECUTE FUNCTION fn_worm_immutable('ledger_immutable');

DROP TRIGGER IF EXISTS trg_shop_purchase_worm ON shop_purchase;
CREATE TRIGGER trg_shop_purchase_worm
    BEFORE UPDATE OR DELETE ON shop_purchase
    FOR EACH ROW
    EXECUTE FUNCTION fn_worm_immutable('ledger_immutable');

-- Hex SHA-256 of a text.
CREATE OR REPLACE FUNCTION fn_sha256_hex(p_text text)
RETURNS char(64)
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT encode(sha256(convert_to(p_text, 'UTF8')), 'hex')::char(64)
$$;

-- Pure read-only check of an org's ledger chain (links + recomputed SHA-256 hashes + genesis presence).
CREATE OR REPLACE FUNCTION fn_ledger_chain_is_valid(p_org_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  r         record;
  v_prev    char(64) := NULL;
  v_count   int := 0;
BEGIN
  FOR r IN SELECT * FROM manager_ledger WHERE org_id IS NOT DISTINCT FROM p_org_id ORDER BY chain_seq LOOP
    v_count := v_count + 1;
    IF r.previous_hash IS DISTINCT FROM v_prev THEN RETURN false; END IF;
    IF r.current_hash <> fn_sha256_hex(COALESCE(v_prev, '') || r.canonical_payload) THEN RETURN false; END IF;
    v_prev := r.current_hash;
  END LOOP;
  IF p_org_id IS NOT NULL AND EXISTS (SELECT 1 FROM companies WHERE company_id = p_org_id) AND v_count = 0 THEN
    RETURN false;
  END IF;
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION fn_ledger_chain_is_valid(uuid) FROM PUBLIC;

-- O-13 (Chief of Drive 24.10): verify an org chain end-to-end; when a broken chain is detected,
-- writes an audit alert ('ledger_chain_broken') and returns false.
CREATE OR REPLACE FUNCTION fn_ledger_verify_chain(p_org_id uuid)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  r         record;
  v_prev    char(64) := NULL;
  v_count   int := 0;
  v_broken  text := NULL;
  v_bad_id  uuid := NULL;
  v_bad_seq bigint := NULL;
BEGIN
  FOR r IN SELECT * FROM manager_ledger WHERE org_id IS NOT DISTINCT FROM p_org_id ORDER BY chain_seq LOOP
    v_count := v_count + 1;
    IF r.previous_hash IS DISTINCT FROM v_prev THEN
      v_broken := 'previous_hash_mismatch';
      v_bad_id := r.ledger_id;
      v_bad_seq := r.chain_seq;
      EXIT;
    END IF;
    IF r.current_hash <> fn_sha256_hex(COALESCE(v_prev, '') || r.canonical_payload) THEN
      v_broken := 'current_hash_mismatch';
      v_bad_id := r.ledger_id;
      v_bad_seq := r.chain_seq;
      EXIT;
    END IF;
    v_prev := r.current_hash;
  END LOOP;

  IF v_broken IS NULL AND p_org_id IS NOT NULL
     AND EXISTS (SELECT 1 FROM companies WHERE company_id = p_org_id) AND v_count = 0 THEN
    v_broken := 'missing_genesis_record';
  END IF;

  IF v_broken IS NOT NULL THEN
    IF to_regclass('public.access_audit_log') IS NOT NULL THEN
      INSERT INTO access_audit_log (viewer_id, company_id, action, scope)
      VALUES (auth.uid(), p_org_id, 'ledger_chain_broken',
              jsonb_build_object('org_id', p_org_id, 'reason', v_broken,
                                 'ledger_id', v_bad_id, 'chain_seq', v_bad_seq));
    END IF;
    RETURN false;
  END IF;
  RETURN true;
END;
$$;

-- BEFORE INSERT on manager_ledger (O-13): one chain per org_id; verifies the existing chain first
-- (blocks writes with 403 ledger_chain_broken if broken), links previous_hash, computes current_hash.
CREATE OR REPLACE FUNCTION fn_ledger_chain()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_prev char(64);
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('manager_ledger:' || COALESCE(NEW.org_id::text, 'none')));

  IF NEW.event_type <> 'GENESIS' AND NOT fn_ledger_chain_is_valid(NEW.org_id) THEN
    RAISE EXCEPTION 'ledger_chain_broken'
      USING ERRCODE = '42501',
            DETAIL = 'http_hint=403;code=ledger_chain_broken',
            HINT = 'ledger_chain_broken';
  END IF;

  SELECT l.current_hash INTO v_prev
    FROM manager_ledger l
   WHERE l.org_id IS NOT DISTINCT FROM NEW.org_id
   ORDER BY l.chain_seq DESC
   LIMIT 1;

  NEW.created_at := clock_timestamp();
  NEW.canonical_payload := jsonb_build_object(
      'ledger_id', NEW.ledger_id,
      'manager_id', NEW.manager_id,
      'org_id', NEW.org_id,
      'department', NEW.department,
      'event_type', NEW.event_type,
      'amount_a', NEW.amount_a,
      'amount_b', NEW.amount_b,
      'deprivation_tax_cost', NEW.deprivation_tax_cost,
      'subject_pseudonym', NEW.subject_pseudonym,
      'restoration_status', NEW.restoration_status,
      'created_at', NEW.created_at
  )::text;
  NEW.previous_hash := v_prev;
  NEW.current_hash := fn_sha256_hex(COALESCE(v_prev, '') || NEW.canonical_payload);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_manager_ledger_chain ON manager_ledger;
CREATE TRIGGER trg_manager_ledger_chain
    BEFORE INSERT ON manager_ledger
    FOR EACH ROW
    EXECUTE FUNCTION fn_ledger_chain();

-- O-13: seed the genesis record for a company if its ledger chain has no rows yet.
CREATE OR REPLACE FUNCTION fn_seed_company_ledger_genesis(p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF p_company_id IS NULL THEN RETURN; END IF;
  IF NOT EXISTS (SELECT 1 FROM manager_ledger WHERE org_id = p_company_id) THEN
    INSERT INTO manager_ledger (
      manager_id, org_id, department, event_type, restoration_status, canonical_payload, current_hash
    ) VALUES (
      NULL, p_company_id, NULL, 'GENESIS', 'Genesis_Initialized', '', repeat('0', 64)
    );
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION fn_seed_company_ledger_genesis(uuid) FROM PUBLIC;

-- Trigger body: seed the ledger genesis record whenever a company is created (O-13).
CREATE OR REPLACE FUNCTION fn_companies_seed_ledger_genesis()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  PERFORM fn_seed_company_ledger_genesis(NEW.company_id);
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION fn_companies_seed_ledger_genesis() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_companies_ledger_genesis ON companies;
CREATE TRIGGER trg_companies_ledger_genesis
    AFTER INSERT ON companies
    FOR EACH ROW
    EXECUTE FUNCTION fn_companies_seed_ledger_genesis();

-- Backfill genesis record for any existing company that has no ledger entries yet (upgrade / migration).
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT company_id FROM companies LOOP
    PERFORM fn_seed_company_ledger_genesis(r.company_id);
  END LOOP;
END $$;

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
  -- v1.6.1 (B2): management access = a management position in the role tree
  -- (org_role.is_management, incl. averages-only CEO) or the CHRO (app_role vp_hr).
  -- Employees, project managers and the safety manager have no management access.
  SELECT EXISTS (
    SELECT 1
      FROM users u
      JOIN org_role r ON r.role_code = u.org_role_code
     WHERE u.user_id = auth.uid()
       AND u.company_id = p_org_id
       AND u.employment_ended_at IS NULL
       AND (r.is_management OR u.app_role = 'vp_hr')
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

-- Lock #3 (v1.6.1): team size is NEVER used for thresholds; the 1.5 team-size helpers are gone.
DROP FUNCTION IF EXISTS fn_require_team_threshold(uuid, varchar, text);
DROP FUNCTION IF EXISTS fn_team_member_count(uuid, varchar);

-- v1.6 (lock #6): true when the caller has an employee interface / wallet (any tier, incl.
-- managers, CEO, VPs). Governance-only users (no employee profile) → false.
CREATE OR REPLACE FUNCTION fn_has_employee_profile(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT COALESCE((SELECT u.has_employee_profile AND u.employment_ended_at IS NULL
                     FROM users u WHERE u.user_id = p_user_id), false)
$$;

REVOKE ALL ON FUNCTION fn_has_employee_profile(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_has_employee_profile(uuid) TO authenticated;

-- HMAC-SHA-256 pseudonym of an employee for the ledger. Creates the key on first use.
-- After crypto-shredding the key is gone: raises vault_sealed (no new entries can link).
CREATE OR REPLACE FUNCTION fn_subject_pseudonym(p_user_id uuid)
RETURNS char(64)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_key bytea;
  v_shredded timestamptz;
BEGIN
  IF p_user_id IS NULL THEN RETURN NULL; END IF;
  INSERT INTO pseudonym_key (user_id, key_material) VALUES (p_user_id, gen_random_bytes(32))
  ON CONFLICT (user_id) DO NOTHING;
  SELECT key_material, shredded_at INTO v_key, v_shredded FROM pseudonym_key WHERE user_id = p_user_id;
  IF v_key IS NULL THEN
    PERFORM fn_raise_business('vault_sealed');
  END IF;
  RETURN encode(hmac(convert_to(p_user_id::text, 'UTF8'), v_key, 'sha256'), 'hex')::char(64);
END;
$$;

REVOKE ALL ON FUNCTION fn_subject_pseudonym(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_ledger_verify_chain(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_ledger_verify_chain(uuid) TO service_role;

-- =============================================================================
-- RLS + FORCE RLS + grants
-- Writes via RPC; reads via PostgREST.
-- =============================================================================
ALTER TABLE employee_value_asset      ENABLE ROW LEVEL SECURITY;
ALTER TABLE anchor                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE spoon_budget              ENABLE ROW LEVEL SECURITY;
ALTER TABLE hrv_sample                ENABLE ROW LEVEL SECURITY;
ALTER TABLE task                      ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_entry             ENABLE ROW LEVEL SECURITY;
ALTER TABLE team_aggregate            ENABLE ROW LEVEL SECURITY;
ALTER TABLE shadow_balance_aggregate  ENABLE ROW LEVEL SECURITY;
ALTER TABLE cuckoo_alert              ENABLE ROW LEVEL SECURITY;
ALTER TABLE avatar_state              ENABLE ROW LEVEL SECURITY;
ALTER TABLE golden_chr_conversion     ENABLE ROW LEVEL SECURITY;
ALTER TABLE manager_ledger            ENABLE ROW LEVEL SECURITY;
ALTER TABLE pseudonym_key             ENABLE ROW LEVEL SECURITY;
ALTER TABLE shop_item_catalog         ENABLE ROW LEVEL SECURITY;
ALTER TABLE questionnaire_definition  ENABLE ROW LEVEL SECURITY;
ALTER TABLE questionnaire_submission  ENABLE ROW LEVEL SECURITY;
ALTER TABLE early_leave_log           ENABLE ROW LEVEL SECURITY;
ALTER TABLE shop_purchase             ENABLE ROW LEVEL SECURITY;
ALTER TABLE approved_absence_entry    ENABLE ROW LEVEL SECURITY;
ALTER TABLE time_benefit_absence_link ENABLE ROW LEVEL SECURITY;
ALTER TABLE time_benefit_refund       ENABLE ROW LEVEL SECURITY;
ALTER TABLE turnover_tier_config      ENABLE ROW LEVEL SECURITY;
ALTER TABLE privacy_threshold_config  ENABLE ROW LEVEL SECURITY;
ALTER TABLE companies                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE users                     ENABLE ROW LEVEL SECURITY;

ALTER TABLE employee_value_asset      FORCE ROW LEVEL SECURITY;
ALTER TABLE anchor                    FORCE ROW LEVEL SECURITY;
ALTER TABLE spoon_budget              FORCE ROW LEVEL SECURITY;
ALTER TABLE hrv_sample                FORCE ROW LEVEL SECURITY;
ALTER TABLE task                      FORCE ROW LEVEL SECURITY;
ALTER TABLE journal_entry             FORCE ROW LEVEL SECURITY;
ALTER TABLE team_aggregate            FORCE ROW LEVEL SECURITY;
ALTER TABLE shadow_balance_aggregate  FORCE ROW LEVEL SECURITY;
ALTER TABLE cuckoo_alert              FORCE ROW LEVEL SECURITY;
ALTER TABLE avatar_state              FORCE ROW LEVEL SECURITY;
ALTER TABLE golden_chr_conversion     FORCE ROW LEVEL SECURITY;
ALTER TABLE manager_ledger            FORCE ROW LEVEL SECURITY;
ALTER TABLE pseudonym_key             FORCE ROW LEVEL SECURITY;
ALTER TABLE shop_item_catalog         FORCE ROW LEVEL SECURITY;
ALTER TABLE questionnaire_definition  FORCE ROW LEVEL SECURITY;
ALTER TABLE questionnaire_submission  FORCE ROW LEVEL SECURITY;
ALTER TABLE early_leave_log           FORCE ROW LEVEL SECURITY;
ALTER TABLE shop_purchase             FORCE ROW LEVEL SECURITY;
ALTER TABLE approved_absence_entry    FORCE ROW LEVEL SECURITY;
ALTER TABLE time_benefit_absence_link FORCE ROW LEVEL SECURITY;
ALTER TABLE time_benefit_refund       FORCE ROW LEVEL SECURITY;
ALTER TABLE turnover_tier_config      FORCE ROW LEVEL SECURITY;
ALTER TABLE privacy_threshold_config  FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE team_aggregate FROM PUBLIC, anon;
REVOKE ALL ON TABLE shadow_balance_aggregate FROM PUBLIC, anon;
REVOKE ALL ON TABLE manager_ledger FROM PUBLIC, anon;
REVOKE ALL ON TABLE pseudonym_key FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE users FROM PUBLIC, anon;
REVOKE ALL ON TABLE companies FROM PUBLIC, anon;
REVOKE SELECT ON TABLE users FROM authenticated;

GRANT SELECT ON TABLE spoon_budget TO authenticated;
GRANT SELECT ON TABLE task TO authenticated;
GRANT SELECT ON TABLE avatar_state TO authenticated;
GRANT SELECT ON TABLE golden_chr_conversion TO authenticated;
GRANT SELECT ON TABLE employee_value_asset TO authenticated;
GRANT SELECT ON TABLE employee_turnover_cost_range_v TO authenticated;
GRANT SELECT ON TABLE cuckoo_alert TO authenticated;
GRANT SELECT ON TABLE shop_item_catalog TO authenticated;
GRANT SELECT ON TABLE turnover_tier_config TO authenticated;
GRANT SELECT ON TABLE privacy_threshold_config TO authenticated;
GRANT SELECT ON TABLE questionnaire_definition TO authenticated;
GRANT SELECT ON TABLE questionnaire_submission TO authenticated;
REVOKE ALL ON TABLE shop_purchase, approved_absence_entry FROM PUBLIC, anon;
-- v1.6.18 (A-13): the purchase link and the refund record are closed to every client role.
REVOKE ALL ON TABLE time_benefit_absence_link, time_benefit_refund FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE early_leave_log TO authenticated;
GRANT SELECT ON TABLE shop_purchase TO authenticated;
GRANT SELECT ON TABLE approved_absence_entry TO authenticated;
GRANT SELECT ON TABLE journal_entry TO authenticated;
GRANT SELECT ON TABLE anchor TO authenticated;
-- hrv_sample: v2 only — no client grant in v1
REVOKE ALL ON TABLE hrv_sample FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE team_aggregate TO authenticated;
GRANT SELECT ON TABLE shadow_balance_aggregate TO authenticated;

REVOKE ALL ON TABLE manager_ledger FROM authenticated;
GRANT SELECT ON TABLE manager_ledger TO authenticated;   -- inserts only via rpc_ledger_append
REVOKE UPDATE, DELETE, TRUNCATE ON TABLE manager_ledger FROM authenticated;
REVOKE UPDATE, DELETE ON TABLE manager_ledger FROM PUBLIC;

DROP POLICY IF EXISTS spoon_budget_private_vault ON spoon_budget;
CREATE POLICY spoon_budget_private_vault ON spoon_budget
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

-- hrv_sample: v2 only; policy kept (own rows) for when v2 grants are added.
DROP POLICY IF EXISTS hrv_sample_private_vault ON hrv_sample;
CREATE POLICY hrv_sample_private_vault ON hrv_sample
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS avatar_state_private_vault ON avatar_state;
CREATE POLICY avatar_state_private_vault ON avatar_state
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS conversion_own ON golden_chr_conversion;
CREATE POLICY conversion_own ON golden_chr_conversion
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

-- Regular team data: N ≥ 5
DROP POLICY IF EXISTS team_aggregate_manager_select ON team_aggregate;
CREATE POLICY team_aggregate_manager_select ON team_aggregate
    FOR SELECT TO authenticated
    USING (
        contributor_count >= fn_privacy_min_n('regular')
        AND fn_is_org_manager(org_id)
    );

-- Shadow Balance: N ≥ 10
DROP POLICY IF EXISTS shadow_balance_manager_select ON shadow_balance_aggregate;
CREATE POLICY shadow_balance_manager_select ON shadow_balance_aggregate
    FOR SELECT TO authenticated
    USING (
        contributor_count >= fn_privacy_min_n('shadow_balance')
        AND fn_is_org_manager(org_id)
    );

DROP POLICY IF EXISTS manager_ledger_select_own ON manager_ledger;
CREATE POLICY manager_ledger_select_own ON manager_ledger
    FOR SELECT TO authenticated
    USING (auth.uid() = manager_id
           OR (event_type = 'GENESIS' AND fn_is_org_manager(org_id)));

DROP POLICY IF EXISTS manager_ledger_insert_own ON manager_ledger;

-- Cuckoo base table: ONLY the target employee. Managers use cuckoo_alert_manager_v.
DROP POLICY IF EXISTS cuckoo_select ON cuckoo_alert;
DROP POLICY IF EXISTS cuckoo_select_target ON cuckoo_alert;
CREATE POLICY cuckoo_select_target ON cuckoo_alert
    FOR SELECT TO authenticated
    USING (auth.uid() = target_user_id);

DROP POLICY IF EXISTS shop_catalog_select ON shop_item_catalog;
CREATE POLICY shop_catalog_select ON shop_item_catalog
    FOR SELECT TO authenticated
    USING (is_active = true);

DROP POLICY IF EXISTS tier_config_select ON turnover_tier_config;
CREATE POLICY tier_config_select ON turnover_tier_config
    FOR SELECT TO authenticated
    USING (true);

DROP POLICY IF EXISTS threshold_config_select ON privacy_threshold_config;
CREATE POLICY threshold_config_select ON privacy_threshold_config
    FOR SELECT TO authenticated
    USING (true);

DROP POLICY IF EXISTS qdef_select ON questionnaire_definition;
CREATE POLICY qdef_select ON questionnaire_definition
    FOR SELECT TO authenticated
    USING (is_active = true);

DROP POLICY IF EXISTS qsub_own ON questionnaire_submission;
CREATE POLICY qsub_own ON questionnaire_submission
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS early_leave_own ON early_leave_log;
CREATE POLICY early_leave_own ON early_leave_log
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

-- נעילת הפרגוד: shop_purchase is strictly private to the purchasing employee (managers/HR/board never see it).
DROP POLICY IF EXISTS shop_purchase_own ON shop_purchase;
CREATE POLICY shop_purchase_own ON shop_purchase
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS approved_absence_own ON approved_absence_entry;
CREATE POLICY approved_absence_own ON approved_absence_entry
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

-- B2: pseudonyms are for DIRECT managers only; averages-only roles (CEO, owners, board)
-- never receive pseudonyms or names.
CREATE OR REPLACE FUNCTION fn_viewer_may_see_pseudonyms()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT COALESCE((SELECT NOT r.averages_only FROM users u JOIN org_role r ON r.role_code = u.org_role_code
                    WHERE u.user_id = auth.uid()), false)
$$;

REVOKE ALL ON FUNCTION fn_viewer_may_see_pseudonyms() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_viewer_may_see_pseudonyms() TO authenticated;

-- =============================================================================
-- Manager-facing pseudonymous views (SECURITY DEFINER functions behind views)
-- The real user id is never returned to a manager.
-- =============================================================================

-- Cuckoo alerts delivered to the calling direct manager: only after the 60-second
-- window passed without a veto. Pseudonym only; no reason / NLP codes / user id.
CREATE OR REPLACE FUNCTION fn_cuckoo_manager_inbox()
RETURNS TABLE (alert_id uuid, target_pseudonym varchar, delivered_at timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT c.alert_id, c.target_pseudonym, c.sovereign_veto_window_expiry
    FROM cuckoo_alert c
   WHERE c.manager_id = auth.uid()
     AND fn_viewer_may_see_pseudonyms()
     AND c.status <> 'VETOED_BY_EMPLOYEE'
     AND (c.status = 'EXPIRED_COMMITTED' OR c.sovereign_veto_window_expiry <= clock_timestamp())
$$;

CREATE OR REPLACE VIEW cuckoo_alert_manager_v AS
  SELECT * FROM fn_cuckoo_manager_inbox();

-- Early-leave notices for the calling direct manager: pseudonym + locked text + time.
CREATE OR REPLACE FUNCTION fn_early_leave_manager_feed()
RETURNS TABLE (display_pseudonym varchar, entry_text text, left_at timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT u.display_pseudonym, l.entry_text, l.left_at
    FROM early_leave_log l
    JOIN users u ON u.user_id = l.user_id
   WHERE u.reports_to = auth.uid()
     AND fn_viewer_may_see_pseudonyms()   -- B2: CEO / owners / board see averages only
$$;

CREATE OR REPLACE VIEW early_leave_manager_v AS
  SELECT * FROM fn_early_leave_manager_feed();

-- v1.6.13 (נעילת הפרגוד): Standard HR approved absence / refresh time feed for the direct manager.
-- Exposes pseudonym, requested_date, locked text 'זמן התרעננות / היעדרות מאושרת', schedule_status, created_at;
-- NEVER exposes whether the entry came from an EverStore time_benefit voucher, item_id, or Golden Spoons.
CREATE OR REPLACE FUNCTION fn_approved_absence_manager_feed()
RETURNS TABLE (
  absence_id        uuid,
  display_pseudonym varchar,
  requested_date    date,
  entry_type        text,
  entry_text        text,
  schedule_status   text,
  created_at        timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT a.absence_id, u.display_pseudonym, a.requested_date, a.entry_type, a.entry_text, a.schedule_status, a.created_at
    FROM approved_absence_entry a
    JOIN users u ON u.user_id = a.user_id
   WHERE u.reports_to = auth.uid()
     AND fn_viewer_may_see_pseudonyms()
$$;

CREATE OR REPLACE VIEW approved_absence_manager_v AS
  SELECT * FROM fn_approved_absence_manager_feed();

REVOKE ALL ON FUNCTION fn_cuckoo_manager_inbox() FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_early_leave_manager_feed() FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_approved_absence_manager_feed() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_cuckoo_manager_inbox() TO authenticated;
GRANT EXECUTE ON FUNCTION fn_early_leave_manager_feed() TO authenticated;
GRANT EXECUTE ON FUNCTION fn_approved_absence_manager_feed() TO authenticated;
REVOKE ALL ON TABLE cuckoo_alert_manager_v FROM PUBLIC, anon;
REVOKE ALL ON TABLE early_leave_manager_v FROM PUBLIC, anon;
REVOKE ALL ON TABLE approved_absence_manager_v FROM PUBLIC, anon;
GRANT SELECT ON TABLE cuckoo_alert_manager_v TO authenticated;
GRANT SELECT ON TABLE early_leave_manager_v TO authenticated;
GRANT SELECT ON TABLE approved_absence_manager_v TO authenticated;

-- =============================================================================
-- v1.6.1 — role tree, access audit, notifications, projects, emergency mode,
-- distress button. All new tables: RLS + FORCE RLS; writes only through RPCs.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- B1: solid-line reporting must not loop and must stay inside the company.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_users_reports_to_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_cursor uuid := NEW.reports_to;
  v_steps  int := 0;
BEGIN
  IF NEW.reports_to IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM users m WHERE m.user_id = NEW.reports_to AND m.company_id IS NOT DISTINCT FROM NEW.company_id) THEN
    RAISE EXCEPTION 'reporting_line_invalid'
      USING ERRCODE = '22023', DETAIL = 'http_hint=400;code=reporting_line_invalid', HINT = 'reporting_line_invalid';
  END IF;
  -- v1.6.3 lock: the safety & emergency manager is outside the tier cascade — she reports
  -- to nobody on the solid line, and nobody reports (solid or dotted) to her.
  IF (NEW.org_role_code = 'safety_emergency_manager' AND NEW.reports_to IS NOT NULL)
     OR EXISTS (SELECT 1 FROM users m WHERE m.user_id IN (NEW.reports_to, NEW.dotted_line_to)
                 AND m.org_role_code = 'safety_emergency_manager') THEN
    RAISE EXCEPTION 'reporting_line_invalid'
      USING ERRCODE = '22023', DETAIL = 'http_hint=400;code=reporting_line_invalid', HINT = 'reporting_line_invalid';
  END IF;
  -- Walk up the solid line; reaching the employee herself means a cycle.
  WHILE v_cursor IS NOT NULL LOOP
    v_steps := v_steps + 1;
    IF v_cursor = NEW.user_id OR v_steps > 1000 THEN
      RAISE EXCEPTION 'reporting_line_invalid'
        USING ERRCODE = '22023', DETAIL = 'http_hint=400;code=reporting_line_invalid', HINT = 'reporting_line_invalid';
    END IF;
    SELECT u.reports_to INTO v_cursor FROM users u WHERE u.user_id = v_cursor;
  END LOOP;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_reports_to ON users;
CREATE TRIGGER trg_users_reports_to
    BEFORE INSERT OR UPDATE OF reports_to, dotted_line_to, org_role_code, company_id ON users
    FOR EACH ROW
    EXECUTE FUNCTION fn_users_reports_to_guard();

-- Everyone below p_root along the SOLID line only (recursive). Dotted lines never count.
CREATE OR REPLACE FUNCTION fn_solid_subtree(p_root uuid)
RETURNS TABLE (user_id uuid, depth int)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  WITH RECURSIVE tree AS (
    SELECT u.user_id, 1 AS depth FROM users u
     WHERE u.reports_to = p_root AND u.org_role_code <> 'safety_emergency_manager'
    UNION ALL
    SELECT u.user_id, t.depth + 1 FROM users u JOIN tree t ON u.reports_to = t.user_id
     WHERE u.org_role_code <> 'safety_emergency_manager'
  )
  SELECT tree.user_id, tree.depth FROM tree
$$;

-- True when p_subject is in p_viewer's solid-line subtree.
CREATE OR REPLACE FUNCTION fn_in_solid_subtree(p_viewer uuid, p_subject uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (SELECT 1 FROM fn_solid_subtree(p_viewer) s WHERE s.user_id = p_subject)
$$;

-- Company of the caller (users is closed to clients, so policies use this helper).
CREATE OR REPLACE FUNCTION fn_my_company()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT u.company_id FROM users u WHERE u.user_id = auth.uid()
$$;

REVOKE ALL ON FUNCTION fn_my_company() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_my_company() TO authenticated;

-- Role-tree row of the caller (NULL when unknown / offboarded).
CREATE OR REPLACE FUNCTION fn_viewer_role()
RETURNS org_role
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT r.* FROM users u JOIN org_role r ON r.role_code = u.org_role_code
   WHERE u.user_id = auth.uid() AND u.employment_ended_at IS NULL
$$;

-- The caller is the CHRO (app_role vp_hr) of an active employment.
CREATE OR REPLACE FUNCTION fn_is_chro()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (SELECT 1 FROM users u WHERE u.user_id = auth.uid()
                  AND u.app_role = 'vp_hr' AND u.employment_ended_at IS NULL)
$$;

-- The caller holds a given role-tree position.
CREATE OR REPLACE FUNCTION fn_viewer_has_role(p_role text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (SELECT 1 FROM users u WHERE u.user_id = auth.uid()
                  AND u.org_role_code = p_role AND u.employment_ended_at IS NULL)
$$;

REVOKE ALL ON FUNCTION fn_solid_subtree(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_in_solid_subtree(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_viewer_role() FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_is_chro() FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_viewer_has_role(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_viewer_role(), fn_is_chro(), fn_viewer_has_role(text) TO authenticated;

ALTER TABLE org_role ENABLE ROW LEVEL SECURITY;
ALTER TABLE org_role FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE org_role FROM PUBLIC, anon;
GRANT SELECT ON TABLE org_role TO authenticated;
DROP POLICY IF EXISTS org_role_select ON org_role;
CREATE POLICY org_role_select ON org_role FOR SELECT TO authenticated USING (true);

-- ---------------------------------------------------------------------------
-- B2: access audit — every management / CHRO / project / board / safety view.
-- WORM (403 ledger_immutable). No client read; reviewed by legal_ethics via service.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS access_audit_log (
    audit_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    viewer_id       uuid REFERENCES users(user_id) ON DELETE SET NULL,
    company_id      uuid REFERENCES companies(company_id) ON DELETE SET NULL,
    action          text NOT NULL,            -- e.g. chro_named_view, project_load_view
    scope           jsonb NOT NULL DEFAULT '{}'::jsonb,   -- ids / periods, never answers
    subject_user_id uuid,                     -- only for CHRO named views and emergency roster
    reason          text,                     -- CHRO reason (required for named data)
    created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
    -- Q6 (locked 12.10): any reason permitted under labour law; free text, but required.
    CONSTRAINT chk_audit_chro_reason CHECK (
      action <> 'chro_named_view' OR (reason IS NOT NULL AND length(btrim(reason)) > 0))
);

CREATE INDEX IF NOT EXISTS idx_audit_viewer ON access_audit_log (viewer_id, created_at DESC);

DROP TRIGGER IF EXISTS trg_access_audit_worm ON access_audit_log;
CREATE TRIGGER trg_access_audit_worm
    BEFORE UPDATE OR DELETE ON access_audit_log
    FOR EACH ROW EXECUTE FUNCTION fn_worm_immutable('ledger_immutable');

-- Write one audit row for the caller (internal helper; no client grant).
CREATE OR REPLACE FUNCTION fn_audit_view(p_action text, p_scope jsonb DEFAULT '{}'::jsonb,
                                         p_subject uuid DEFAULT NULL, p_reason text DEFAULT NULL)
RETURNS void
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  INSERT INTO access_audit_log (viewer_id, company_id, action, scope, subject_user_id, reason)
  SELECT auth.uid(), (SELECT u.company_id FROM users u WHERE u.user_id = auth.uid()),
         p_action, COALESCE(p_scope, '{}'::jsonb), p_subject, p_reason
$$;

REVOKE ALL ON FUNCTION fn_audit_view(text, jsonb, uuid, text) FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- Notifications (no PII columns at all: recipients read details through scoped RPCs).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS notification (
    notification_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    recipient_id    uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    kind            text NOT NULL CHECK (kind IN (
                      'distress_alert',        -- safety manager: open the distress inbox
                      'distress_awareness',    -- CHRO: awareness only, no PII
                      'distress_closed',       -- CHRO: silent notice on close
                      'emergency_declared',
                      'emergency_hr_review',   -- CHRO: review after emergency ended
                      'emergency_misuse_notice',   -- v1.6.3 (Q5): the declarer is told of a MISUSE finding
                      'emergency_cosign_request')), -- v1.6.3 (Q5): a restricted declarer needs a co-signer
    ref_id          uuid NOT NULL,
    silent          boolean NOT NULL DEFAULT false,
    created_at      timestamptz NOT NULL DEFAULT clock_timestamp()
);

-- ---------------------------------------------------------------------------
-- B3: projects (v1.6.3: the project manager sees project-level workload aggregates only).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS project (
    project_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id          uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    name                varchar(200) NOT NULL,
    project_manager_id  uuid REFERENCES users(user_id) ON DELETE SET NULL,
    -- v1.6.4 (Karin, Q4): the PM marks the project core / not core when creating it. NO default:
    -- every create must choose. Only core projects count toward the soft WIP alert (>2).
    -- Migration (resolved v1.6.5, Karin): EXISTING projects become is_core = false until their
    -- PM marks them; NEW projects still have no default (fn_migrate_project_is_core).
    is_core             boolean NOT NULL,
    created_at          timestamptz NOT NULL DEFAULT clock_timestamp()
);
-- v1.6.5 (Karin 20.10) migration: see fn_migrate_project_is_core at the end of this file.

CREATE TABLE IF NOT EXISTS project_member (
    project_id uuid NOT NULL REFERENCES project(project_id) ON DELETE CASCADE,
    user_id    uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    -- v1.6.4: core is a property of the project (project.is_core), not of the assignment.
    PRIMARY KEY (project_id, user_id)
);

-- ---------------------------------------------------------------------------
-- B5: emergency mode. Only the safety & emergency manager declares and ends it.
-- Three types, locked by Karin on 13.10:
--   health_or_life_danger  — danger to an employee's health or life
--   work_stopping_disaster — a fault or disaster that stops work (fire, flood, systems down)
--   war_or_security        — war or a security situation
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE emergency_type_enum AS ENUM ('health_or_life_danger', 'work_stopping_disaster', 'war_or_security');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS emergency_event (
    event_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id        uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    emergency_type    emergency_type_enum NOT NULL,
    declared_by       uuid NOT NULL REFERENCES users(user_id),
    declared_at       timestamptz NOT NULL DEFAULT clock_timestamp(),
    ended_by          uuid REFERENCES users(user_id),
    ended_at          timestamptz,
    -- v1.6.3 (Q5): PENDING_COSIGN = declared by someone who lost the right to open alone.
    status            text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'PENDING_COSIGN', 'ENDED')),
    cosigned_by       uuid REFERENCES users(user_id),
    cosigned_at       timestamptz,
    -- v1.6.3 (Q5) misuse sequence: close → notify the declarer → talk.
    misuse_notified_at timestamptz,
    misuse_talk_at     timestamptz,
    misuse_talk_by     uuid REFERENCES users(user_id),
    -- HR review after the emergency ended (CHRO): PENDING → JUSTIFIED | MISUSE.
    hr_review_status  text CHECK (hr_review_status IN ('PENDING', 'JUSTIFIED', 'MISUSE')),
    hr_reviewed_by    uuid REFERENCES users(user_id),
    hr_reviewed_at    timestamptz,
    CONSTRAINT chk_emergency_review_after_end CHECK (
      (status IN ('ACTIVE', 'PENDING_COSIGN') AND hr_review_status IS NULL AND ended_at IS NULL)
      OR (status = 'ENDED' AND hr_review_status IS NOT NULL AND ended_at IS NOT NULL)),
    -- Q5 order: notify only after a MISUSE finding; talk only after the notice.
    CONSTRAINT chk_emergency_misuse_sequence CHECK (
      (misuse_notified_at IS NULL OR hr_review_status = 'MISUSE')
      AND (misuse_talk_at IS NULL OR misuse_notified_at IS NOT NULL))
);

-- One open (active or awaiting co-sign) emergency per company.
CREATE UNIQUE INDEX IF NOT EXISTS uq_emergency_active ON emergency_event (company_id) WHERE status IN ('ACTIVE', 'PENDING_COSIGN');

-- Employees report "I am safe" during an emergency (feeds the N≥10 team status).
CREATE TABLE IF NOT EXISTS emergency_safe_report (
    event_id    uuid NOT NULL REFERENCES emergency_event(event_id) ON DELETE CASCADE,
    user_id     uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    reported_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (event_id, user_id)
);

-- ---------------------------------------------------------------------------
-- B6: distress button. Manual, employee-only. No free-text / NLP columns.
-- GRACE (60 s, cancel → silent log, nothing sent) → DISPATCHED → CLOSED (PII removed, read-only).
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE distress_close_reason_enum AS ENUM ('threat_removed', 'referred_to_external_help', 'pressed_by_mistake');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS distress_event (
    event_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id        uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    -- Presser; set to NULL on close (PII removed).
    user_id           uuid REFERENCES users(user_id) ON DELETE SET NULL,
    pressed_at        timestamptz NOT NULL DEFAULT clock_timestamp(),
    grace_expires_at  timestamptz NOT NULL,   -- = pressed_at + 60 s (CHECK below)
    status            text NOT NULL DEFAULT 'GRACE' CHECK (status IN ('GRACE', 'CANCELLED', 'DISPATCHED', 'CLOSED')),
    -- PII snapshot taken at dispatch; shown ONLY to the safety manager; NULL after close.
    subject_name      varchar(255),
    subject_phone     varchar(32),
    last_location     text CHECK (last_location IS NULL OR last_location IN ('home', 'office', 'site')),
    dispatched_at     timestamptz,
    closed_by         uuid REFERENCES users(user_id),
    closed_at         timestamptz,
    close_reason      distress_close_reason_enum,
    CONSTRAINT chk_distress_grace_60s CHECK (grace_expires_at = pressed_at + interval '60 seconds'),
    CONSTRAINT chk_distress_closed_clean CHECK (
      status <> 'CLOSED' OR (close_reason IS NOT NULL AND user_id IS NULL AND subject_name IS NULL
                             AND subject_phone IS NULL AND last_location IS NULL))
);

-- Silent log of a cancel inside the 60-second grace (nothing is sent to anyone).
CREATE TABLE IF NOT EXISTS distress_silent_log (
    log_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id     uuid NOT NULL REFERENCES distress_event(event_id) ON DELETE CASCADE,
    company_id   uuid NOT NULL,
    cancelled_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

-- Closed / cancelled distress records are read-only (403 distress_record_immutable).
CREATE OR REPLACE FUNCTION fn_distress_readonly()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'DELETE' OR OLD.status IN ('CLOSED', 'CANCELLED') THEN
    RAISE EXCEPTION 'distress_record_immutable'
      USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=distress_record_immutable', HINT = 'distress_record_immutable';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_distress_readonly ON distress_event;
CREATE TRIGGER trg_distress_readonly
    BEFORE UPDATE OR DELETE ON distress_event
    FOR EACH ROW EXECUTE FUNCTION fn_distress_readonly();

DROP TRIGGER IF EXISTS trg_distress_silent_worm ON distress_silent_log;
CREATE TRIGGER trg_distress_silent_worm
    BEFORE UPDATE OR DELETE ON distress_silent_log
    FOR EACH ROW EXECUTE FUNCTION fn_worm_immutable('ledger_immutable');

-- Analytics: false alarms (pressed_by_mistake) and grace cancels are excluded. No PII.
CREATE OR REPLACE VIEW distress_analytics_v AS
  SELECT company_id, date_trunc('month', closed_at) AS month, close_reason, count(*)::int AS events
    FROM distress_event
   WHERE status = 'CLOSED' AND close_reason <> 'pressed_by_mistake'
   GROUP BY company_id, date_trunc('month', closed_at), close_reason;

REVOKE ALL ON distress_analytics_v FROM PUBLIC, anon, authenticated;
GRANT SELECT ON distress_analytics_v TO service_role;

-- ---------------------------------------------------------------------------
-- RLS for the v1.6.1 tables (all reads through scoped RPCs; base tables closed).
-- ---------------------------------------------------------------------------
ALTER TABLE access_audit_log      ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification          ENABLE ROW LEVEL SECURITY;
ALTER TABLE project               ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_member        ENABLE ROW LEVEL SECURITY;
ALTER TABLE emergency_event       ENABLE ROW LEVEL SECURITY;
ALTER TABLE emergency_safe_report ENABLE ROW LEVEL SECURITY;
ALTER TABLE distress_event        ENABLE ROW LEVEL SECURITY;
ALTER TABLE distress_silent_log   ENABLE ROW LEVEL SECURITY;
ALTER TABLE access_audit_log      FORCE ROW LEVEL SECURITY;
ALTER TABLE notification          FORCE ROW LEVEL SECURITY;
ALTER TABLE project               FORCE ROW LEVEL SECURITY;
ALTER TABLE project_member        FORCE ROW LEVEL SECURITY;
ALTER TABLE emergency_event       FORCE ROW LEVEL SECURITY;
ALTER TABLE emergency_safe_report FORCE ROW LEVEL SECURITY;
ALTER TABLE distress_event        FORCE ROW LEVEL SECURITY;
ALTER TABLE distress_silent_log   FORCE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- v1.6.12 (Chief of Drive 24.10, O-19 & O-20):
--   * O-20: Tier 5 governance roles (board_chair, board_member, owner_shareholder) default to
--     has_employee_profile = false on INSERT unless explicitly marked as also an employee.
--   * O-19: Manager private vault (direct manager only: solid-line reports, never averages-only /
--     HR / governance). Opening / reading / writing requires BOTH office network AND company device
--     (is_office_network = true AND is_company_device = true) and an active session within the
--     inactivity timeout (default 15 minutes). Any transfer (department or company change),
--     dismissal / offboarding, or loss of direct-manager status immediately wipes the vault.
-- ---------------------------------------------------------------------------

-- BEFORE INSERT on users (O-20): tier 5 governance roles default to has_employee_profile = false
-- when the caller did not explicitly pass true via rpc_provision_governance_user, and syncs app_role.
CREATE OR REPLACE FUNCTION fn_users_governance_profile_default()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  -- If app_role is a tier-5 governance role and org_role_code was left at 'employee', sync org_role_code
  IF NEW.app_role IN ('board_chair', 'board_member', 'owner_shareholder') AND NEW.org_role_code = 'employee' THEN
    NEW.org_role_code := NEW.app_role;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION fn_users_governance_profile_default() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_users_governance_profile_default ON users;
CREATE TRIGGER trg_users_governance_profile_default
    BEFORE INSERT ON users
    FOR EACH ROW
    EXECUTE FUNCTION fn_users_governance_profile_default();

CREATE TABLE IF NOT EXISTS manager_vault_session (
    manager_id         uuid PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
    is_office_network  boolean NOT NULL DEFAULT false,
    is_company_device  boolean NOT NULL DEFAULT false,
    timeout_minutes    int NOT NULL DEFAULT 15 CHECK (timeout_minutes BETWEEN 1 AND 60),
    opened_at          timestamptz NOT NULL DEFAULT clock_timestamp(),
    last_active_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
    wiped_at           timestamptz,
    wipe_reason        text
);

CREATE TABLE IF NOT EXISTS manager_vault_entry (
    entry_id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    manager_id         uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    subject_user_id    uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    display_pseudonym  varchar(64) NOT NULL,
    encrypted_note     bytea,
    updated_at         timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (manager_id, subject_user_id)
);

CREATE INDEX IF NOT EXISTS idx_manager_vault_entry_mgr ON manager_vault_entry (manager_id);
CREATE INDEX IF NOT EXISTS idx_manager_vault_entry_subj ON manager_vault_entry (subject_user_id);

ALTER TABLE manager_vault_session ENABLE ROW LEVEL SECURITY;
ALTER TABLE manager_vault_entry   ENABLE ROW LEVEL SECURITY;
ALTER TABLE manager_vault_session FORCE ROW LEVEL SECURITY;
ALTER TABLE manager_vault_entry   FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE manager_vault_session, manager_vault_entry FROM PUBLIC, anon, authenticated;

-- Internal: immediately wipe a manager's vault (or entries for a transferred/offboarded subject).
CREATE OR REPLACE FUNCTION fn_manager_vault_wipe(
  p_manager_id uuid,
  p_reason     text,
  p_subject_id uuid DEFAULT NULL
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_n int := 0;
BEGIN
  IF p_subject_id IS NOT NULL THEN
    DELETE FROM manager_vault_entry
     WHERE (p_manager_id IS NULL OR manager_id = p_manager_id)
       AND subject_user_id = p_subject_id;
    GET DIAGNOSTICS v_n = ROW_COUNT;
  ELSIF p_manager_id IS NOT NULL THEN
    DELETE FROM manager_vault_entry WHERE manager_id = p_manager_id;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    UPDATE manager_vault_session
       SET is_office_network = false,
           is_company_device = false,
           wiped_at          = clock_timestamp(),
           wipe_reason       = p_reason
     WHERE manager_id = p_manager_id;
  END IF;

  IF to_regclass('public.access_audit_log') IS NOT NULL THEN
    INSERT INTO access_audit_log (viewer_id, company_id, action, scope, subject_user_id)
    VALUES (p_manager_id,
            (SELECT u.company_id FROM users u WHERE u.user_id = COALESCE(p_manager_id, p_subject_id)),
            'manager_vault_wiped',
            jsonb_build_object('reason', p_reason, 'entries_removed', v_n),
            p_subject_id);
  END IF;
  RETURN v_n;
END;
$$;

REVOKE ALL ON FUNCTION fn_manager_vault_wipe(uuid, text, uuid) FROM PUBLIC;

-- Trigger on users (O-19):
--   * When a user is dismissed/offboarded (employment_ended_at set), transferred (department or
--     company_id changes), or loses direct-manager eligibility, wipe her manager vault immediately,
--     and remove her subject entries from any previous direct manager's vault.
CREATE OR REPLACE FUNCTION fn_users_manager_vault_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  -- 1. Dismissal / offboarding → wipe her own vault + remove her from any manager's vault
  IF OLD.employment_ended_at IS NULL AND NEW.employment_ended_at IS NOT NULL THEN
    PERFORM fn_manager_vault_wipe(NEW.user_id, 'employment_ended', NULL);
    PERFORM fn_manager_vault_wipe(NULL, 'subject_employment_ended', NEW.user_id);
  END IF;

  -- 2. Department or company transfer → wipe her vault of previous department names + remove her from old manager's vault
  IF NEW.department IS DISTINCT FROM OLD.department OR NEW.company_id IS DISTINCT FROM OLD.company_id THEN
    PERFORM fn_manager_vault_wipe(NEW.user_id, 'department_or_company_transfer', NULL);
    PERFORM fn_manager_vault_wipe(NULL, 'subject_transferred', NEW.user_id);
  END IF;

  -- 3. Direct manager change (reports_to changed) → remove subject from old manager's vault
  IF NEW.reports_to IS DISTINCT FROM OLD.reports_to AND OLD.reports_to IS NOT NULL THEN
    PERFORM fn_manager_vault_wipe(OLD.reports_to, 'reports_to_changed', NEW.user_id);
  END IF;

  -- 4. Role changed to averages-only or non-management → wipe her vault
  IF NEW.org_role_code IS DISTINCT FROM OLD.org_role_code THEN
    IF NOT EXISTS (SELECT 1 FROM org_role r WHERE r.role_code = NEW.org_role_code AND r.is_management AND NOT r.averages_only) THEN
      PERFORM fn_manager_vault_wipe(NEW.user_id, 'role_no_longer_direct_manager', NULL);
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION fn_users_manager_vault_guard() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_users_manager_vault_guard ON users;
CREATE TRIGGER trg_users_manager_vault_guard
    AFTER UPDATE OF employment_ended_at, department, company_id, reports_to, org_role_code ON users
    FOR EACH ROW
    EXECUTE FUNCTION fn_users_manager_vault_guard();

REVOKE ALL ON TABLE access_audit_log, notification, project, project_member, emergency_event,
                    emergency_safe_report, distress_event, distress_silent_log FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE notification, emergency_event TO authenticated;

-- Recipient reads her own notifications (they carry no PII).
DROP POLICY IF EXISTS notification_own ON notification;
CREATE POLICY notification_own ON notification FOR SELECT TO authenticated USING (recipient_id = auth.uid());

-- Everyone in the company can see whether an emergency is active (no personal data in the row).
DROP POLICY IF EXISTS emergency_company ON emergency_event;
CREATE POLICY emergency_company ON emergency_event FOR SELECT TO authenticated
    USING (company_id = fn_my_company());


-- =============================================================================
-- v1.6.3 — Project workload module (research doc "מדד העומס של הפרויקט", §4.2 / §6.2 +
-- the locked infographic formulas). Locks of 20.10:
--   1. EPWI_time, EPWI_cognitive, B_t are visible ONLY to the employee (RLS + RPC).
--      The PM sees project aggregates (PEWI / AIDB / TRR / M_SPOF) only at N≥5 actual
--      respondents; every PM view is audited; SPOF alerts never identify an employee.
--   2. v1 data = the employee's own weekly self-report only (hours, parallel projects,
--      overtime, pressure). Inputs the self-report cannot supply are v2 (adapter stub).
--   3. Soft WIP limit: >2 core projects → alert to her and to the PM (count only), no blocking.
-- =============================================================================

-- Context-switch loss L(P) by number of parallel projects (locked: 0/20/40/60/75 %).
-- Resolved v1.6.4 (Karin, Q3): P > 5 counts as 5 → L = 0.75 (fn_context_switch_loss caps P).
CREATE TABLE IF NOT EXISTS context_switch_loss_config (
    parallel_projects int PRIMARY KEY CHECK (parallel_projects BETWEEN 1 AND 5),
    loss_fraction     numeric(4, 2) NOT NULL,
    CONSTRAINT chk_context_switch_loss_locked CHECK (
         (parallel_projects = 1 AND loss_fraction = 0.00)
      OR (parallel_projects = 2 AND loss_fraction = 0.20)
      OR (parallel_projects = 3 AND loss_fraction = 0.40)
      OR (parallel_projects = 4 AND loss_fraction = 0.60)
      OR (parallel_projects = 5 AND loss_fraction = 0.75))
);
INSERT INTO context_switch_loss_config VALUES (1, 0.00), (2, 0.20), (3, 0.40), (4, 0.60), (5, 0.75)
ON CONFLICT (parallel_projects) DO NOTHING;

-- Weekly self-report (v1 single data source). One per employee per company week (keyed by
-- week_start_date); WORM;
-- a second report in the same week is REJECTED (409), not updated in place (Q6, Karin 20.10).
-- Separate from the daily spoons check-in (own table + endpoint; never merged with spoon_budget).
-- Questions (short): contracted weekly hours, hours actually worked (incl. overtime),
-- of which overtime, number of projects in parallel, stress (1–5), productivity drop (1–5).
CREATE TABLE IF NOT EXISTS workload_self_report (
    report_id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id           uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    company_id        uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    -- v1.6.5 (Karin): keyed by the week's start DATE (never an ISO week number).
    week_start_date   date NOT NULL,                 -- first day of the company week (7 days)
    -- v1.6.5 (Karin): the work / shift START date decides the week (a night shift crossing
    -- midnight counts toward the day it started), not the submission time.
    work_date         date NOT NULL,
    contract_hours    numeric(5, 2) NOT NULL CHECK (contract_hours > 0 AND contract_hours <= 168),
    hours_worked      numeric(5, 2) NOT NULL CHECK (hours_worked >= 0 AND hours_worked <= 168),
    overtime_hours    numeric(5, 2) NOT NULL CHECK (overtime_hours >= 0 AND overtime_hours <= hours_worked),
    parallel_projects int NOT NULL CHECK (parallel_projects >= 0),
    -- v1.6.4 (Karin, Q5): integer Likert 1–5. NULL = not answered → B_t NULL (no partial score).
    stress_1to5             smallint CHECK (stress_1to5 IS NULL OR stress_1to5 BETWEEN 1 AND 5),
    productivity_drop_1to5  smallint CHECK (productivity_drop_1to5 IS NULL OR productivity_drop_1to5 BETWEEN 1 AND 5),
    submitted_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
    -- v1.6.5: week_start_date = fn_week_start_for(work_date, companies.week_start_dow); set /
    -- checked by trg_workload_report_week (the v1.6.4 ISO-Monday CHECK is replaced).
    CONSTRAINT uq_workload_report_week UNIQUE (user_id, week_start_date),
    -- v1.6.8 (Karin 21.10, O-41): every week is exactly 7 days again; the days between the last full
    -- old week and the first new week are a BRIDGE (no week, no report — see fn_company_bridge_at).
    CONSTRAINT chk_workload_week_7_days CHECK (work_date BETWEEN week_start_date AND week_start_date + 6)
);
-- Upgrade from 1.6.7 (8–13-day check): restore the 7-day check. Stored reports are immutable, so if a
-- 1.6.7 database already holds a report on a stretched day the check is added NOT VALID (new rows are
-- still checked) and a notice names the count.
ALTER TABLE workload_self_report DROP CONSTRAINT IF EXISTS chk_workload_week_span;
DO $$
DECLARE v_bad int;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_workload_week_7_days') THEN
    SELECT count(*) INTO v_bad FROM workload_self_report WHERE work_date > week_start_date + 6;
    IF v_bad = 0 THEN
      ALTER TABLE workload_self_report ADD CONSTRAINT chk_workload_week_7_days
        CHECK (work_date BETWEEN week_start_date AND week_start_date + 6);
    ELSE
      RAISE NOTICE '% stored 1.6.7 report(s) lie on a stretched day; 7-day check added NOT VALID', v_bad;
      ALTER TABLE workload_self_report ADD CONSTRAINT chk_workload_week_7_days
        CHECK (work_date BETWEEN week_start_date AND week_start_date + 6) NOT VALID;
    END IF;
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_workload_report_worm ON workload_self_report;
CREATE TRIGGER trg_workload_report_worm
    BEFORE UPDATE OR DELETE ON workload_self_report
    FOR EACH ROW EXECUTE FUNCTION fn_worm_immutable('questionnaire_immutable');

-- Task-level single-point-of-failure items (v2 adapter source only). NO employee columns:
-- an item says "critical and held by a single person", never who.
CREATE TABLE IF NOT EXISTS project_spof_item (
    item_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id    uuid NOT NULL REFERENCES project(project_id) ON DELETE CASCADE,
    item_ref      varchar(200) NOT NULL,           -- task / knowledge key from the v2 tool
    is_critical   boolean NOT NULL,
    single_holder boolean NOT NULL,
    source        text NOT NULL DEFAULT 'v2_adapter' CHECK (source IN ('v2_adapter')),
    updated_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT uq_spof_item UNIQUE (project_id, item_ref)
);

-- Soft WIP alerts (lock 3). Count only — no wellbeing data; the PM row has no employee id.
CREATE TABLE IF NOT EXISTS wip_alert (
    alert_id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    recipient_id          uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    audience              text NOT NULL CHECK (audience IN ('employee', 'project_manager')),
    project_id            uuid NOT NULL REFERENCES project(project_id) ON DELETE CASCADE,
    core_assignment_count int NOT NULL CHECK (core_assignment_count > 2),
    created_at            timestamptz NOT NULL DEFAULT clock_timestamp()
);

ALTER TABLE context_switch_loss_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE workload_self_report       ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_spof_item          ENABLE ROW LEVEL SECURITY;
ALTER TABLE wip_alert                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE context_switch_loss_config FORCE ROW LEVEL SECURITY;
ALTER TABLE workload_self_report       FORCE ROW LEVEL SECURITY;
ALTER TABLE project_spof_item          FORCE ROW LEVEL SECURITY;
ALTER TABLE wip_alert                  FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE context_switch_loss_config, workload_self_report, project_spof_item, wip_alert
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE context_switch_loss_config, workload_self_report, wip_alert TO authenticated;

-- Locked loss table is public reference data.
DROP POLICY IF EXISTS context_switch_loss_read ON context_switch_loss_config;
CREATE POLICY context_switch_loss_read ON context_switch_loss_config FOR SELECT TO authenticated USING (true);

-- Lock 1: a self-report is readable by its author ONLY (no manager / PM / CHRO policy).
DROP POLICY IF EXISTS workload_report_own ON workload_self_report;
CREATE POLICY workload_report_own ON workload_self_report FOR SELECT TO authenticated
    USING (user_id = auth.uid());

-- Each recipient reads her own WIP alerts.
DROP POLICY IF EXISTS wip_alert_own ON wip_alert;
CREATE POLICY wip_alert_own ON wip_alert FOR SELECT TO authenticated USING (recipient_id = auth.uid());


-- =============================================================================
-- v1.6.3 — Distress alert delivery (lock 20.10): the safety manager gets the alert by BOTH
-- in-app push AND SMS, always, in parallel — two delivery rows written in the same
-- transaction with the same timestamp; neither row references or waits for the other.
-- The 60-second employee cancel window is unchanged: delivery is created at dispatch,
-- i.e. when the event becomes active after that window.
-- =============================================================================
CREATE TABLE IF NOT EXISTS distress_alert_delivery (
    delivery_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id     uuid NOT NULL REFERENCES distress_event(event_id) ON DELETE CASCADE,
    recipient_id uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    channel      text NOT NULL CHECK (channel IN ('push', 'sms')),
    queued_at    timestamptz NOT NULL,
    status       text NOT NULL DEFAULT 'QUEUED' CHECK (status IN ('QUEUED', 'SENT', 'FAILED', 'PROVIDER_NOT_CONFIGURED')),
    attempted_at timestamptz,
    CONSTRAINT uq_distress_delivery UNIQUE (event_id, recipient_id, channel)
);

ALTER TABLE distress_alert_delivery ENABLE ROW LEVEL SECURITY;
ALTER TABLE distress_alert_delivery FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE distress_alert_delivery FROM PUBLIC, anon, authenticated;


-- =============================================================================
-- v1.6.5 — company calendar settings + legacy migrations (Karin 20.10)
-- =============================================================================
-- v1.6.4 workload_reminder_setting is replaced by companies.last_workday_dow + reminder_time.
DROP TABLE IF EXISTS workload_reminder_setting;

-- Upgrade path for a 1.6.4 database (no-op on a fresh install). country / last_workday_dow /
-- timezone have NO column default. v1.6.6: missing last_workday_dow / timezone / week_start_dow of
-- existing companies are backfilled from the country (fn_backfill_company_calendar, end of file);
-- a company without a country cannot be backfilled (TODO להשלמה per real company).
ALTER TABLE companies ADD COLUMN IF NOT EXISTS country          text CHECK (country ~ '^[A-Z]{2}$');
ALTER TABLE companies ADD COLUMN IF NOT EXISTS week_start_dow   smallint CHECK (week_start_dow BETWEEN 0 AND 6);
ALTER TABLE companies ADD COLUMN IF NOT EXISTS last_workday_dow smallint CHECK (last_workday_dow BETWEEN 0 AND 6);
ALTER TABLE companies ADD COLUMN IF NOT EXISTS timezone         text;
ALTER TABLE companies ADD COLUMN IF NOT EXISTS reminder_time    time NOT NULL DEFAULT '14:00';
ALTER TABLE companies ADD COLUMN IF NOT EXISTS timezone_status  text NOT NULL DEFAULT 'confirmed'
    CHECK (timezone_status IN ('confirmed', 'needs_review'));
ALTER TABLE companies ADD COLUMN IF NOT EXISTS reminders_on_hold boolean NOT NULL DEFAULT false;

-- Company timezone must be a valid IANA name (same rule as users.timezone).
-- v1.6.7: an UPDATE that leaves the value unchanged (e.g. a settings call without p_timezone) is not re-checked.
CREATE OR REPLACE FUNCTION fn_validate_company_timezone()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.timezone IS NOT DISTINCT FROM OLD.timezone THEN
    RETURN NEW;
  END IF;
  IF NULLIF(btrim(COALESCE(NEW.timezone, '')), '') IS NULL THEN
    RAISE EXCEPTION 'timezone_required'
      USING ERRCODE = '22004', DETAIL = 'http_hint=400;code=timezone_required', HINT = 'timezone_required';
  END IF;
  IF NOT fn_is_valid_iana_timezone(btrim(NEW.timezone)) THEN
    RAISE EXCEPTION 'invalid_timezone'
      USING ERRCODE = '22023', DETAIL = 'http_hint=400;code=invalid_timezone', HINT = 'invalid_timezone';
  END IF;
  NEW.timezone := btrim(NEW.timezone);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_companies_timezone ON companies;
CREATE TRIGGER trg_companies_timezone
    BEFORE INSERT OR UPDATE OF timezone ON companies
    FOR EACH ROW EXECUTE FUNCTION fn_validate_company_timezone();

-- v1.6.6 (Chief of Drive): the generated CLDR / tz reference table must be loaded first.
DO $$
BEGIN
  IF to_regclass('public.ref_country_calendar') IS NULL THEN
    RAISE EXCEPTION 'ref_country_calendar missing: load ref_country_calendar.sql before schema.sql';
  END IF;
END $$;
ALTER TABLE ref_country_calendar ENABLE ROW LEVEL SECURITY;
ALTER TABLE ref_country_calendar_source ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE ref_country_calendar, ref_country_calendar_source FROM PUBLIC, anon, authenticated;

-- One CLDR / tz reference row for a country, falling back column-wise to the CLDR world row (001).
-- main_timezone / tz_zone_count never fall back (001 has no zone).
CREATE OR REPLACE FUNCTION fn_ref_country_calendar(p_country text)
RETURNS TABLE (first_day_dow smallint, weekend_start_dow smallint, main_timezone text, tz_zone_count int)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT COALESCE(c.first_day_dow, w.first_day_dow), COALESCE(c.weekend_start_dow, w.weekend_start_dow),
         c.main_timezone, COALESCE(c.tz_zone_count, 0)
    FROM ref_country_calendar w
    LEFT JOIN ref_country_calendar c ON c.country = upper(p_country)
   WHERE w.country = '001'
$$;

-- Default week start by country (v1.6.6): CLDR weekData firstDay; IL is PINNED to Sunday (0) as an
-- explicit override (Karin 20.10) even though CLDR agrees; a country CLDR does not list → 001.
CREATE OR REPLACE FUNCTION fn_default_week_start_dow(p_country text)
RETURNS smallint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT CASE WHEN p_country IS NULL THEN NULL
              WHEN upper(p_country) = 'IL' THEN 0::smallint
              ELSE (SELECT r.first_day_dow FROM fn_ref_country_calendar(p_country) r) END
$$;

-- Default last workday (v1.6.6 backfill): the day before the CLDR weekend start (IL Fri → Thu (4);
-- 001 Sat → Fri (5)).
CREATE OR REPLACE FUNCTION fn_default_last_workday_dow(p_country text)
RETURNS smallint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT CASE WHEN p_country IS NULL THEN NULL
              ELSE ((SELECT r.weekend_start_dow FROM fn_ref_country_calendar(p_country) r) + 6) % 7 END::smallint
$$;

-- Default company timezone (v1.6.6 backfill): the country's first zone in IANA zone.tab; NULL when the
-- country has no zone. Multi-zone countries (tz_zone_count > 1, e.g. US) are flagged in ADR_GAPS O-39.
CREATE OR REPLACE FUNCTION fn_default_timezone(p_country text)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$ SELECT r.main_timezone FROM fn_ref_country_calendar(p_country) r $$;

-- On company create: fill week_start_dow from the country unless the company overrides it.
-- v1.6.7: also upper-cases a country set later (UPDATE OF country); the default fills on INSERT only.
CREATE OR REPLACE FUNCTION fn_companies_week_start_default()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.country := upper(NEW.country);
  -- v1.6.8 (Chief of Drive 21.10): a well-formed code missing from ref_country_calendar → 422
  -- unknown_country (the statement fails, so a held company stays held). A malformed code is left to
  -- the column CHECK (23514 → 400).
  IF NEW.country ~ '^[A-Z]{2}$' AND NOT EXISTS (SELECT 1 FROM ref_country_calendar r WHERE r.country = NEW.country) THEN
    RAISE EXCEPTION 'unknown_country'
      USING ERRCODE = 'PT422', DETAIL = 'http_hint=422;code=unknown_country', HINT = 'unknown_country';
  END IF;
  IF TG_OP = 'INSERT' AND NEW.week_start_dow IS NULL THEN
    NEW.week_start_dow := fn_default_week_start_dow(NEW.country);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_companies_week_start ON companies;
CREATE TRIGGER trg_companies_week_start
    BEFORE INSERT OR UPDATE OF country ON companies
    FOR EACH ROW EXECUTE FUNCTION fn_companies_week_start_default();

-- First day of the 7-day week containing a local date, for a week starting on p_week_start_dow (0–6).
CREATE OR REPLACE FUNCTION fn_week_start_for(p_local_date date, p_week_start_dow smallint)
RETURNS date
LANGUAGE sql
IMMUTABLE
AS $$ SELECT p_local_date - ((extract(dow FROM p_local_date)::int - p_week_start_dow + 7) % 7) $$;

-- Last day of a week: always start + 6 (7 days, whatever the start day or workdays).
CREATE OR REPLACE FUNCTION fn_week_last_day(p_week_start_date date)
RETURNS date
LANGUAGE sql
IMMUTABLE
AS $$ SELECT p_week_start_date + 6 $$;

-- =============================================================================
-- v1.6.7 (Karin 20.10, O-41): week-start HISTORY. A change takes effect at the next week boundary,
-- is never blocked, never recalculates stored reports, and is audited. Each report's week resolves
-- against the setting in force on its work_date.
-- v1.6.8 (Karin 21.10, locked): SHORT BRIDGE instead of the 8–13-day week. The last old week stays a
-- full 7 days (old week start … +6); from its end up to the day before effective_from (= the first new
-- start day on or after old week start + 7) is a BRIDGE of 1–6 days with no week, no load report
-- (422 bridge_period) and no reminder. Every week is exactly 7 days. No overlaps, no gaps.
-- =============================================================================
CREATE TABLE IF NOT EXISTS company_week_start_history (
    company_id      uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    effective_from  date NOT NULL,                 -- '-infinity' = the company's initial setting
    week_start_dow  smallint NOT NULL CHECK (week_start_dow BETWEEN 0 AND 6),
    changed_by      uuid,                          -- auth.uid() of the change (NULL = system / initial)
    created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (company_id, effective_from)
);
ALTER TABLE company_week_start_history ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE company_week_start_history FROM PUBLIC, anon, authenticated;

-- History rows are append-only (a change is a new row; nothing is rewritten).
DROP TRIGGER IF EXISTS trg_week_start_history_worm ON company_week_start_history;
CREATE TRIGGER trg_week_start_history_worm
    BEFORE UPDATE ON company_week_start_history
    FOR EACH ROW EXECUTE FUNCTION fn_worm_immutable('week_start_history_immutable');

-- Initial history row of a company (its first week_start_dow, in force since -infinity). Idempotent.
CREATE OR REPLACE FUNCTION fn_week_start_history_seed(p_company uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  INSERT INTO company_week_start_history (company_id, effective_from, week_start_dow)
  SELECT c.company_id, '-infinity'::date, c.week_start_dow FROM companies c
   WHERE c.company_id = p_company AND c.week_start_dow IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM company_week_start_history h WHERE h.company_id = c.company_id)
$$;

-- First day of the new regime: the first p_new_dow on or after the end of the current old week
-- (p_old_week_start + 7). Pure; the last full old week is p_old_week_start … +6, the bridge
-- p_old_week_start + 7 … result − 1 (empty only when the day does not change — a no-op).
CREATE OR REPLACE FUNCTION fn_week_start_effective_from(p_old_week_start date, p_new_dow smallint)
RETURNS date
LANGUAGE sql
IMMUTABLE
AS $$ SELECT (p_old_week_start + 7) + ((p_new_dow - extract(dow FROM p_old_week_start + 7)::int + 7) % 7) $$;

-- The rule in force on a date: its start day, and the next change after that date (NULL if none).
CREATE OR REPLACE FUNCTION fn_company_week_rule_at(p_company uuid, p_date date)
RETURNS TABLE (week_start_dow smallint, next_effective_from date)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT (SELECT h.week_start_dow FROM company_week_start_history h
           WHERE h.company_id = p_company AND h.effective_from <= p_date ORDER BY h.effective_from DESC LIMIT 1),
         (SELECT h.effective_from FROM company_week_start_history h
           WHERE h.company_id = p_company AND h.effective_from > p_date ORDER BY h.effective_from LIMIT 1)
$$;

-- Start of the last FULL old week before a change at p_next (the old week containing p_next − 7).
CREATE OR REPLACE FUNCTION fn_final_old_week_start(p_old_dow smallint, p_next date)
RETURNS date
LANGUAGE sql
IMMUTABLE
AS $$ SELECT fn_week_start_for(p_next - 7, p_old_dow) $$;

-- First bridge day before a change at p_next: the day after the last full old week (v1.6.8).
CREATE OR REPLACE FUNCTION fn_bridge_start(p_old_dow smallint, p_next date)
RETURNS date
LANGUAGE sql
IMMUTABLE
AS $$ SELECT fn_final_old_week_start(p_old_dow, p_next) + 7 $$;

-- The bridge containing a local date (one row: start, end = next change − 1), or no row (v1.6.8).
CREATE OR REPLACE FUNCTION fn_company_bridge_at(p_company uuid, p_date date)
RETURNS TABLE (bridge_start date, bridge_end date)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT fn_bridge_start(r.week_start_dow, r.next_effective_from), r.next_effective_from - 1
    FROM fn_company_week_rule_at(p_company, p_date) r
   WHERE r.next_effective_from IS NOT NULL
     AND p_date >= fn_bridge_start(r.week_start_dow, r.next_effective_from)
$$;

-- Company week key of a local date, resolved against the setting in force on that date;
-- NULL for a bridge day (v1.6.8: a bridge belongs to no week).
CREATE OR REPLACE FUNCTION fn_company_week_start(p_company uuid, p_date date)
RETURNS date
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT CASE WHEN r.next_effective_from IS NOT NULL
                   AND p_date >= fn_bridge_start(r.week_start_dow, r.next_effective_from)
              THEN NULL
              ELSE fn_week_start_for(p_date, r.week_start_dow) END
    FROM fn_company_week_rule_at(p_company, p_date) r
$$;

-- Last day of a company week (always start + 6); NULL when p_week_start_date is not a week start.
CREATE OR REPLACE FUNCTION fn_company_week_end(p_company uuid, p_week_start_date date)
RETURNS date
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT CASE WHEN fn_company_week_start(p_company, p_week_start_date) = p_week_start_date
              THEN fn_week_last_day(p_week_start_date) END
$$;

-- Company-local calendar date now (CURRENT_DATE when the company has no timezone yet).
CREATE OR REPLACE FUNCTION fn_company_local_today(p_company uuid)
RETURNS date
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT COALESCE((SELECT (clock_timestamp() AT TIME ZONE c.timezone)::date FROM companies c
                    WHERE c.company_id = p_company AND c.timezone IS NOT NULL), CURRENT_DATE)
$$;

-- Reference date for a change: the latest of company-local today, the latest stored work_date and
-- the latest scheduled change — so no stored report ever falls into the new regime.
CREATE OR REPLACE FUNCTION fn_week_change_base(p_company uuid)
RETURNS date
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT GREATEST(fn_company_local_today(p_company),
                  (SELECT max(w.work_date) FROM workload_self_report w WHERE w.company_id = p_company),
                  (SELECT max(h.effective_from) FROM company_week_start_history h WHERE h.company_id = p_company))
$$;

-- Append a week-start change (never blocked) and audit it; returns effective_from (NULL = no change).
CREATE OR REPLACE FUNCTION fn_schedule_week_start_change(p_company uuid, p_new_dow smallint, p_base date)
RETURNS date
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_old  smallint;
  v_ws   date;
  v_eff  date;
BEGIN
  SELECT r.week_start_dow INTO v_old FROM fn_company_week_rule_at(p_company, 'infinity'::date) r;
  IF v_old IS NULL OR v_old = p_new_dow THEN
    RETURN NULL;
  END IF;
  v_ws  := fn_company_week_start(p_company, p_base);
  v_eff := fn_week_start_effective_from(v_ws, p_new_dow);
  INSERT INTO company_week_start_history (company_id, effective_from, week_start_dow, changed_by)
  VALUES (p_company, v_eff, p_new_dow, auth.uid());
  -- v1.6.8: the last old week stays 7 days; the bridge (1–6 days) is audited with its dates
  INSERT INTO access_audit_log (viewer_id, company_id, action, scope)
  VALUES (auth.uid(), p_company, 'company_week_start_change',
          jsonb_build_object('old_week_start_dow', v_old, 'new_week_start_dow', p_new_dow,
                             'effective_from', v_eff, 'final_old_week_start', v_ws,
                             'final_old_week_end', fn_week_last_day(v_ws), 'final_old_week_days', 7,
                             'bridge_start', v_ws + 7, 'bridge_end', v_eff - 1, 'bridge_days', v_eff - (v_ws + 7)));
  RETURN v_eff;
END;
$$;

-- companies trigger: a first week start seeds the history; a later change is scheduled (O-41).
CREATE OR REPLACE FUNCTION fn_companies_week_start_history()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF TG_OP = 'INSERT' OR OLD.week_start_dow IS NULL THEN
    PERFORM fn_week_start_history_seed(NEW.company_id);
  ELSIF NEW.week_start_dow IS DISTINCT FROM OLD.week_start_dow THEN
    PERFORM fn_schedule_week_start_change(NEW.company_id, NEW.week_start_dow, fn_week_change_base(NEW.company_id));
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_companies_week_start_history ON companies;
CREATE TRIGGER trg_companies_week_start_history
    AFTER INSERT OR UPDATE OF week_start_dow ON companies
    FOR EACH ROW EXECUTE FUNCTION fn_companies_week_start_history();

-- Upgrade: every existing company gets its initial history row (no-op when present).
SELECT count(fn_week_start_history_seed(c.company_id)) AS week_start_history_seeded FROM companies c;

REVOKE ALL ON FUNCTION fn_week_start_history_seed(uuid), fn_company_week_rule_at(uuid, date),
  fn_company_bridge_at(uuid, date), fn_company_week_start(uuid, date), fn_company_week_end(uuid, date), fn_company_local_today(uuid),
  fn_week_change_base(uuid), fn_schedule_week_start_change(uuid, smallint, date) FROM PUBLIC;

-- Self-report week key: derived from work_date + company week start; a given key must match
-- (400 workload_week_invalid). v1.6.8: a work_date inside a bridge → 422 bridge_period.
CREATE OR REPLACE FUNCTION fn_workload_report_week_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_week date;
BEGIN
  IF EXISTS (SELECT 1 FROM fn_company_bridge_at(NEW.company_id, NEW.work_date)) THEN
    RAISE EXCEPTION 'bridge_period'
      USING ERRCODE = 'PT422', DETAIL = 'http_hint=422;code=bridge_period', HINT = 'bridge_period';
  END IF;
  v_week := fn_company_week_start(NEW.company_id, NEW.work_date);   -- v1.6.7: history-aware
  NEW.week_start_date := COALESCE(NEW.week_start_date, v_week);
  IF v_week IS NULL OR NEW.week_start_date <> v_week THEN
    RAISE EXCEPTION 'workload_week_invalid'
      USING ERRCODE = '22023', DETAIL = 'http_hint=400;code=workload_week_invalid', HINT = 'workload_week_invalid';
  END IF;
  RETURN NEW;
END;
$$;

ALTER TABLE workload_self_report DROP CONSTRAINT IF EXISTS chk_workload_week_monday;
DROP TRIGGER IF EXISTS trg_workload_report_week ON workload_self_report;
CREATE TRIGGER trg_workload_report_week
    BEFORE INSERT ON workload_self_report
    FOR EACH ROW EXECUTE FUNCTION fn_workload_report_week_guard();

-- Migration (Karin 20.10): legacy projects without a core choice become non-core until their
-- PM marks them; afterwards the column is NOT NULL with NO default (new projects must choose).
CREATE OR REPLACE FUNCTION fn_migrate_project_is_core()
RETURNS int
LANGUAGE plpgsql
AS $$
DECLARE
  v_n int;
BEGIN
  ALTER TABLE project ADD COLUMN IF NOT EXISTS is_core boolean;
  UPDATE project SET is_core = false WHERE is_core IS NULL;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  ALTER TABLE project ALTER COLUMN is_core DROP DEFAULT;
  ALTER TABLE project ALTER COLUMN is_core SET NOT NULL;
  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION fn_migrate_project_is_core() FROM PUBLIC;
SELECT fn_migrate_project_is_core() AS legacy_projects_migrated;

-- v1.6.6 (Chief of Drive, O-39): one-time upgrade backfill of a legacy company's calendar from its
-- country (CLDR + IANA zone.tab via ref_country_calendar). Each value filled is audited as auto-filled.
CREATE OR REPLACE FUNCTION fn_backfill_company_field(p_company uuid, p_field text, p_value text)
RETURNS void
LANGUAGE sql
AS $$
  INSERT INTO access_audit_log (viewer_id, company_id, action, scope)
  SELECT NULL, p_company, 'company_calendar_autofill',
         jsonb_build_object('field', p_field, 'value', p_value, 'auto_filled', true,
                            'cldr_source', s.cldr_source, 'tz_source', s.tz_source)
    FROM ref_country_calendar_source s WHERE s.id = 1
$$;

-- =============================================================================
-- v1.6.8 (Karin 21.10, O-49): TPS 30-day wait start = team_joined_at (employee-local date) → hire_date
-- → exempt (no wait). The source used is audited per user ('tps_wait_source': team_join / hire / exempt).
-- =============================================================================
-- Pure rule: (wait_start, source) from the two dates; NULL start = exempt.
CREATE OR REPLACE FUNCTION fn_tps_wait_rule(p_team_joined_at timestamptz, p_hire_date date, p_tz text)
RETURNS TABLE (wait_start date, source text)
LANGUAGE sql
STABLE
AS $$
  SELECT CASE WHEN p_team_joined_at IS NOT NULL THEN (p_team_joined_at AT TIME ZONE p_tz)::date ELSE p_hire_date END,
         CASE WHEN p_team_joined_at IS NOT NULL THEN 'team_join' WHEN p_hire_date IS NOT NULL THEN 'hire' ELSE 'exempt' END
$$;

-- The wait rule of one user.
CREATE OR REPLACE FUNCTION fn_tps_wait_start(p_user uuid)
RETURNS TABLE (wait_start date, source text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT r.wait_start, r.source FROM users u, fn_tps_wait_rule(u.team_joined_at, u.hire_date, u.timezone) r
   WHERE u.user_id = p_user
$$;

-- Audit row: which source the user's TPS wait uses now (system row, user id in scope only).
CREATE OR REPLACE FUNCTION fn_tps_wait_audit(p_user uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  INSERT INTO access_audit_log (viewer_id, company_id, action, scope)
  SELECT NULL, u.company_id, 'tps_wait_source',
         jsonb_build_object('user_id', u.user_id, 'source', w.source, 'wait_start', w.wait_start)
    FROM users u, fn_tps_wait_start(u.user_id) w WHERE u.user_id = p_user
$$;

-- users trigger: audit on insert, and on update when the source or the start date changes. Fires on
-- the team columns too, because a transfer sets team_joined_at inside trg_users_team_joined.
CREATE OR REPLACE FUNCTION fn_users_tps_wait_audit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF TG_OP = 'INSERT' OR (SELECT row(n.wait_start, n.source) FROM fn_tps_wait_rule(NEW.team_joined_at, NEW.hire_date, NEW.timezone) n)
      IS DISTINCT FROM (SELECT row(o.wait_start, o.source) FROM fn_tps_wait_rule(OLD.team_joined_at, OLD.hire_date, OLD.timezone) o) THEN
    PERFORM fn_tps_wait_audit(NEW.user_id);
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_tps_wait_audit ON users;
CREATE TRIGGER trg_users_tps_wait_audit
    AFTER INSERT OR UPDATE OF team_joined_at, hire_date, department, company_id, timezone ON users
    FOR EACH ROW EXECUTE FUNCTION fn_users_tps_wait_audit();

-- =============================================================================
-- v1.6.9 (Chief of Drive 21.10, O-50): hire_date is the single source; start_date becomes a generated
-- read-only alias. An upgrade from a database where start_date is still a plain column (v1.4 via the
-- migration, or 1.6.8) merges it first: copied into an empty hire_date, unless it equals the record's
-- creation date — then it is treated as unknown (hire_date stays NULL → TPS wait exempt) and audited
-- 'start_date_untrusted'.
-- =============================================================================
-- v1.6.10: zone in which v1.x dates are compared — set by the migration's timezone preflight
-- (transaction-local chr.mig_source_tz = the source DB zone if UTC, or the explicit --source-tz);
-- UTC when unset.
CREATE OR REPLACE FUNCTION fn_mig_source_tz()
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(NULLIF(current_setting('chr.mig_source_tz', true), ''), 'UTC')
$$;

-- Rule: a start_date equal to the date portion of created_at (in fn_mig_source_tz) is untrusted.
CREATE OR REPLACE FUNCTION fn_start_date_untrusted(p_start date, p_created timestamptz)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT p_start = (p_created AT TIME ZONE fn_mig_source_tz())::date
$$;

-- v1.6.10: created within 1 hour of local midnight (23:00–01:00 in fn_mig_source_tz)? Flag only.
CREATE OR REPLACE FUNCTION fn_tz_edge(p_created timestamptz)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT (p_created AT TIME ZONE fn_mig_source_tz())::time >= TIME '23:00'
      OR (p_created AT TIME ZONE fn_mig_source_tz())::time <= TIME '01:00'
$$;

-- Is users.start_date still a plain (writable) column?
CREATE OR REPLACE FUNCTION fn_users_start_date_is_plain()
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'public.users'::regclass
                    AND attname = 'start_date' AND NOT attisdropped AND attgenerated = '')
$$;

-- Merge a plain start_date into hire_date, then replace it by the generated alias (idempotent; 0 = no-op).
-- Returns the number of untrusted start dates audited.
CREATE OR REPLACE FUNCTION fn_users_merge_start_date()
RETURNS int
LANGUAGE plpgsql
AS $$
DECLARE v_n int := 0;
BEGIN
  IF NOT fn_users_start_date_is_plain() THEN
    RETURN 0;
  END IF;
  -- dynamic SQL: start_date is a generated column on a fresh install, so nothing here is compiled there
  -- v1.6.10: compared rows created near local midnight → 'tz_edge_review' (flag only, no behaviour change)
  EXECUTE $q$
    INSERT INTO access_audit_log (viewer_id, company_id, action, scope)
    SELECT NULL, u.company_id, 'tz_edge_review',
           jsonb_build_object('user_id', u.user_id, 'start_date', u.start_date, 'created_at', u.created_at,
                              'local_created_at', (u.created_at AT TIME ZONE fn_mig_source_tz()), 'zone', fn_mig_source_tz(),
                              'untrusted', fn_start_date_untrusted(u.start_date, u.created_at))
      FROM users u
     WHERE u.hire_date IS NULL AND u.start_date IS NOT NULL AND fn_tz_edge(u.created_at)
     ORDER BY u.user_id $q$;
  EXECUTE $q$
    INSERT INTO access_audit_log (viewer_id, company_id, action, scope)
    SELECT NULL, u.company_id, 'start_date_untrusted',
           jsonb_build_object('user_id', u.user_id, 'start_date', u.start_date,
                              'created_at_date', (u.created_at AT TIME ZONE fn_mig_source_tz())::date, 'compared_in', fn_mig_source_tz())
      FROM users u
     WHERE u.hire_date IS NULL AND u.start_date IS NOT NULL AND fn_start_date_untrusted(u.start_date, u.created_at)
     ORDER BY u.user_id $q$;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  EXECUTE $q$
    UPDATE users SET hire_date = start_date
     WHERE hire_date IS NULL AND start_date IS NOT NULL AND NOT fn_start_date_untrusted(start_date, created_at) $q$;
  ALTER TABLE users DROP COLUMN start_date;
  ALTER TABLE users ADD COLUMN start_date date GENERATED ALWAYS AS (hire_date) STORED;
  RETURN v_n;
END;
$$;

SELECT fn_users_merge_start_date() AS start_date_untrusted_audited;
COMMENT ON COLUMN users.start_date IS 'DEPRECATED (v1.6.9, O-50): read-only alias of hire_date (generated). Removal planned for v1.7.';
REVOKE ALL ON FUNCTION fn_users_merge_start_date(), fn_users_start_date_is_plain(), fn_start_date_untrusted(date, timestamptz),
                       fn_mig_source_tz(), fn_tz_edge(timestamptz) FROM PUBLIC;

-- Upgrade / migration: one audit row for every user that has none yet (idempotent). Returns rows written.
CREATE OR REPLACE FUNCTION fn_tps_wait_audit_backfill()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE v_n int := 0; r record;
BEGIN
  FOR r IN SELECT u.user_id FROM users u
            WHERE NOT EXISTS (SELECT 1 FROM access_audit_log a
                               WHERE a.action = 'tps_wait_source' AND a.scope->>'user_id' = u.user_id::text)
            ORDER BY u.user_id LOOP
    PERFORM fn_tps_wait_audit(r.user_id);
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;

SELECT fn_tps_wait_audit_backfill() AS tps_wait_source_audited;
REVOKE ALL ON FUNCTION fn_tps_wait_start(uuid), fn_tps_wait_audit(uuid), fn_tps_wait_audit_backfill() FROM PUBLIC;

-- =============================================================================
-- v1.6.8 (Chief of Drive 21.10, O-45): frozen v1.4 tables (legacy_v1_4_*, created only by the
-- migration) are read-only: no client grants, and this trigger refuses INSERT / UPDATE / DELETE /
-- TRUNCATE for every role, the owner included. They are never dropped by the pack.
-- =============================================================================
CREATE OR REPLACE FUNCTION fn_legacy_read_only()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'legacy_read_only'
    USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=legacy_read_only', HINT = 'legacy_read_only';
END;
$$;

-- Attach the read-only guard to every legacy_v1_4_* table that lacks it (idempotent). Returns tables guarded.
CREATE OR REPLACE FUNCTION fn_legacy_guard_all()
RETURNS int
LANGUAGE plpgsql
AS $$
DECLARE r record; v_n int := 0;
BEGIN
  FOR r IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relname LIKE 'legacy\_v1\_4\_%'
              AND pg_has_role(current_user, c.relowner, 'USAGE') LOOP   -- v1.6.10: skip tables handed to legacy_v1_4_owner
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = ('public.' || r.relname)::regclass AND tgname = 'trg_legacy_read_only_row') THEN
      EXECUTE format('CREATE TRIGGER trg_legacy_read_only_row BEFORE INSERT OR UPDATE OR DELETE ON public.%I
                        FOR EACH ROW EXECUTE FUNCTION fn_legacy_read_only()', r.relname);
      EXECUTE format('CREATE TRIGGER trg_legacy_read_only_truncate BEFORE TRUNCATE ON public.%I
                        FOR EACH STATEMENT EXECUTE FUNCTION fn_legacy_read_only()', r.relname);
      v_n := v_n + 1;
    END IF;
    EXECUTE format('REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.%I FROM PUBLIC, anon, authenticated, service_role', r.relname);
  END LOOP;
  RETURN v_n;
END;
$$;

SELECT fn_legacy_guard_all() AS legacy_tables_guarded;
REVOKE ALL ON FUNCTION fn_legacy_guard_all() FROM PUBLIC;

-- v1.6.10 (Chief of Drive 21.10): does an auto-picked zone of this country need review? Only when the
-- country lists more than one zone AND its zone is not an explicit pin ('override: …', e.g. UA → Kyiv).
CREATE OR REPLACE FUNCTION fn_country_tz_needs_review(p_country text)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE((SELECT c.tz_zone_count > 1 AND COALESCE(c.main_timezone_source, '') NOT LIKE 'override:%'
                     FROM ref_country_calendar c WHERE c.country = p_country), false)
$$;

-- System audit row for a company (viewer NULL = system).
CREATE OR REPLACE FUNCTION fn_company_system_audit(p_company uuid, p_action text, p_scope jsonb)
RETURNS void
LANGUAGE sql
AS $$
  INSERT INTO access_audit_log (viewer_id, company_id, action, scope) VALUES (NULL, p_company, p_action, p_scope)
$$;

-- Backfill ONE company with a country (NULL fields only). v1.6.7 (O-43): a timezone auto-picked for a
-- multi-zone country (> 1 zone in zone.tab) is marked needs_review. Returns values filled.
CREATE OR REPLACE FUNCTION fn_backfill_company_calendar_one(p_company uuid)
RETURNS int
LANGUAGE plpgsql
AS $$
DECLARE
  r   record;
  v_n int := 0;
  v_v text;
BEGIN
  SELECT company_id, country, week_start_dow, last_workday_dow, timezone INTO r
    FROM companies WHERE company_id = p_company AND country IS NOT NULL;
  IF NOT FOUND THEN
    RETURN 0;
  END IF;
  IF r.week_start_dow IS NULL THEN
    v_v := fn_default_week_start_dow(r.country)::text;
    UPDATE companies SET week_start_dow = v_v::smallint WHERE company_id = r.company_id;
    PERFORM fn_backfill_company_field(r.company_id, 'week_start_dow', v_v); v_n := v_n + 1;
  END IF;
  IF r.last_workday_dow IS NULL THEN
    v_v := fn_default_last_workday_dow(r.country)::text;
    UPDATE companies SET last_workday_dow = v_v::smallint WHERE company_id = r.company_id;
    PERFORM fn_backfill_company_field(r.company_id, 'last_workday_dow', v_v); v_n := v_n + 1;
  END IF;
  v_v := fn_default_timezone(r.country);
  IF r.timezone IS NULL AND v_v IS NOT NULL THEN
    UPDATE companies SET timezone = v_v,
                         timezone_status = CASE WHEN fn_country_tz_needs_review(r.country) THEN 'needs_review' ELSE timezone_status END
     WHERE company_id = r.company_id;
    PERFORM fn_backfill_company_field(r.company_id, 'timezone', v_v); v_n := v_n + 1;
  END IF;
  RETURN v_n;
END;
$$;

-- v1.6.7 (O-43): a legacy company WITHOUT a country gets no backfill; it is marked needs_review and
-- its reminders are held (audited 'reminders_on_hold'). Returns 1 when newly held.
CREATE OR REPLACE FUNCTION fn_hold_reminders_no_country(p_company uuid)
RETURNS int
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE companies SET reminders_on_hold = true, timezone_status = 'needs_review'
   WHERE company_id = p_company AND country IS NULL AND NOT reminders_on_hold;
  IF NOT FOUND THEN
    RETURN 0;
  END IF;
  PERFORM fn_company_system_audit(p_company, 'reminders_on_hold', jsonb_build_object('reason', 'no_country'));
  RETURN 1;
END;
$$;

-- Backfill all legacy companies; hold reminders of companies without a country. Columns become
-- NOT NULL once nothing is missing. Returns the number of values filled.
CREATE OR REPLACE FUNCTION fn_backfill_company_calendar()
RETURNS int
LANGUAGE plpgsql
AS $$
DECLARE
  r   record;
  v_n int := 0;
BEGIN
  FOR r IN SELECT company_id, country FROM companies
            WHERE (country IS NOT NULL AND (week_start_dow IS NULL OR last_workday_dow IS NULL OR timezone IS NULL))
               OR (country IS NULL AND NOT reminders_on_hold)
            ORDER BY company_id LOOP
    IF r.country IS NULL THEN
      PERFORM fn_hold_reminders_no_country(r.company_id);
    ELSE
      v_n := v_n + fn_backfill_company_calendar_one(r.company_id);
    END IF;
  END LOOP;
  PERFORM fn_company_calendar_lock_not_null();
  RETURN v_n;
END;
$$;

-- v1.6.7 (O-43): when a held company gets a country, backfill it and release its reminders
-- (audited 'reminders_released'). The company's timezone status follows the backfill rule.
CREATE OR REPLACE FUNCTION fn_companies_country_release()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
BEGIN
  IF NEW.country IS NULL OR NOT NEW.reminders_on_hold THEN
    RETURN NULL;
  END IF;
  PERFORM fn_backfill_company_calendar_one(NEW.company_id);
  UPDATE companies c
     SET reminders_on_hold = false,
         timezone_status = CASE WHEN c.timezone IS NULL OR fn_country_tz_needs_review(NEW.country) THEN 'needs_review' ELSE 'confirmed' END
   WHERE c.company_id = NEW.company_id;
  PERFORM fn_company_system_audit(NEW.company_id, 'reminders_released', jsonb_build_object('country', NEW.country));
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_companies_country_release ON companies;
CREATE TRIGGER trg_companies_country_release
    AFTER UPDATE OF country ON companies
    FOR EACH ROW WHEN (OLD.country IS NULL AND NEW.country IS NOT NULL)
    EXECUTE FUNCTION fn_companies_country_release();

-- Make the calendar columns NOT NULL when no company is missing a value (otherwise leave them and notice).
CREATE OR REPLACE FUNCTION fn_company_calendar_lock_not_null()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM companies WHERE country IS NULL OR week_start_dow IS NULL
                                           OR last_workday_dow IS NULL OR timezone IS NULL) THEN
    RAISE NOTICE 'company calendar incomplete: complete country / week start / last workday / timezone manually';
    RETURN;
  END IF;
  ALTER TABLE companies ALTER COLUMN country SET NOT NULL, ALTER COLUMN week_start_dow SET NOT NULL,
                        ALTER COLUMN last_workday_dow SET NOT NULL, ALTER COLUMN timezone SET NOT NULL;
END;
$$;
REVOKE ALL ON FUNCTION fn_backfill_company_field(uuid, text, text), fn_backfill_company_calendar(),
                       fn_company_calendar_lock_not_null(), fn_company_system_audit(uuid, text, jsonb),
                       fn_backfill_company_calendar_one(uuid), fn_hold_reminders_no_country(uuid) FROM PUBLIC;
SELECT fn_backfill_company_calendar() AS company_calendar_values_backfilled;

-- =============================================================================
-- v1.6.16 agents (agents-bot-instructions-v3, Karin 30.10) — three ADVISORY management agents:
--   Agent 1 EverStore budget · Agent 2 burnout forecast · Agent 3 monthly board report.
-- Agents never pay, never change a budget and never message an employee (v3 §1.1).
-- Every table below is CLOSED to clients (RLS forced, no grants); access is only through the
-- SECURITY DEFINER RPCs in rpc.sql. No agent table holds person_id / pseudonym, except the internal
-- golden_spoons_ledger (user_id, never returned) and remediation_records.approved_by (never returned).
-- =============================================================================

-- agent_settings — every agent parameter (v3 §6.1). company_id NULL = system default row; a company row
-- overrides it. value_status 'not_defined' = "לא הוגדר" (no value is invented; the agent shows the label).
CREATE TABLE IF NOT EXISTS agent_settings (
    setting_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id     uuid REFERENCES companies(company_id) ON DELETE CASCADE,
    setting_key    text NOT NULL CHECK (setting_key ~ '^[a-z][a-z0-9_]*$'),
    value_kind     text NOT NULL CHECK (value_kind IN ('numeric', 'text', 'time', 'timezone', 'method')),
    value_numeric  numeric,
    value_text     text,
    value_status   text NOT NULL CHECK (value_status IN ('set', 'not_defined')),
    is_locked      boolean NOT NULL DEFAULT false,
    source_note    text,
    updated_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT chk_agent_setting_value CHECK (
         (value_status = 'not_defined' AND value_numeric IS NULL AND value_text IS NULL)
      OR (value_status = 'set' AND value_kind = 'numeric' AND value_numeric IS NOT NULL AND value_text IS NULL)
      OR (value_status = 'set' AND value_kind <> 'numeric' AND value_text IS NOT NULL AND value_numeric IS NULL))
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_agent_settings_scope_key
    ON agent_settings ((COALESCE(company_id, '00000000-0000-0000-0000-000000000000'::uuid)), setting_key);

COMMENT ON TABLE agent_settings IS
  'v1.6.16 (v3 §6.1): agent parameters. company_id NULL = system default; value_status not_defined = לא הוגדר (never invented).';

-- System defaults (code-managed: re-applying the schema refreshes them; company override rows are untouched).
-- is_locked = a closed decision (Karin 30.10 / v3): the value is a parameter here, never a code constant, but a
-- company cannot override it (PUT → 403 setting_locked); changing it is a pack change.
INSERT INTO agent_settings (company_id, setting_key, value_kind, value_numeric, value_text, value_status, is_locked, source_note) VALUES
  (NULL, 'company_timezone',            'timezone', NULL, NULL, 'not_defined', false, 'v3 §1.7: falls back to companies.timezone until set'),
  (NULL, 'daily_summary_time',          'time',     NULL, NULL, 'not_defined', false, 'v3 §3.4: לא הוגדר — להשלמה'),
  (NULL, 'liability_method',            'method',   NULL, NULL, 'not_defined', false, 'v3 §3.2: fixed_cost | avg_redeemed — לא הוגדר'),
  (NULL, 'spoon_cost_ils',              'numeric',  NULL, NULL, 'not_defined', false, 'v3 §3.2: internal ILS cost per Golden Spoon — לא הוגדר'),
  (NULL, 'exit_redemption_days',        'numeric',  30,   NULL, 'set',         true,  'v3 §3.3 decision 4 (Karin 30.10)'),
  (NULL, 'small_category_min_buyers',   'numeric',  5,    NULL, 'set',         true,  'v3 §3.5 decision 5 (Karin 30.10); never lowered'),
  (NULL, 'budget_threshold_low_pct',    'numeric',  75,   NULL, 'set',         false, 'v3 §3.1 / decision 6'),
  (NULL, 'budget_threshold_mid_pct',    'numeric',  90,   NULL, 'set',         false, 'v3 §3.1 / decision 6'),
  (NULL, 'budget_threshold_high_pct',   'numeric',  100,  NULL, 'set',         false, 'v3 §3.1 / decision 6'),
  (NULL, 'pcq_drop_pct',                'numeric',  10,   NULL, 'set',         false, 'v3 §4.2 default'),
  (NULL, 'rise_pct',                    'numeric',  15,   NULL, 'set',         false, 'v3 §4.2 default (מס קיפוח, Happiness Debt, approved absences)'),
  (NULL, 'burnout_ma_months',           'numeric',  3,    NULL, 'set',         true,  'v3 §4.2 decision 2: 3-month moving average'),
  (NULL, 'burnout_consecutive_periods', 'numeric',  2,    NULL, 'set',         true,  'v3 §4.2 decision 2: 2 consecutive periods'),
  (NULL, 'score_range_coefficient',     'numeric',  12.5, NULL, 'set',         false, 'v3 §4.3: margin = coefficient × (1 − r); replaces margin_budget_points_pcq / _ihs'),
  (NULL, 'deprivation_tax_rate',        'numeric',  0.12, NULL, 'set',         true,  'v3 §5.4: locked 12% (Oswald et al. 2015; Bellet et al. 2024) = fn_chr_productivity_factor()'),
  (NULL, 'deprivation_tax_sensitivity', 'numeric',  0.10, NULL, 'set',         true,  'v3 §5.4: 10% display-only sensitivity switch'),
  (NULL, 'turnover_baseline_junior',    'numeric',  NULL, NULL, 'not_defined', false, 'v3 §5.5: baseline leavers per month (junior) — לא הוגדר'),
  (NULL, 'turnover_baseline_mid',       'numeric',  NULL, NULL, 'not_defined', false, 'v3 §5.5: baseline leavers per month (mid) — לא הוגדר'),
  (NULL, 'turnover_baseline_senior',    'numeric',  NULL, NULL, 'not_defined', false, 'v3 §5.5: baseline leavers per month (senior) — לא הוגדר'),
  -- v1.6.18 (A-14, Karin 31.10): the three questionnaire amounts are adjustable per company (not locked):
  -- 1–20 per questionnaire, one value for the whole company, vp_hr only, WORM history, non-retroactive.
  (NULL, 'golden_spoons_per_questionnaire',           'numeric', 10,  NULL, 'set',         false, 'Karin 30.10 / 31.10: monthly questionnaire incl. PCQ-12 and Cantril = 10 כפיות (participation only); A-14: adjustable per company 1–20, vp_hr only'),
  (NULL, 'golden_spoons_per_short_questionnaire',     'numeric', 2,   NULL, 'set',         false, 'Karin 30.10: weekly / short questionnaire = 2 כפיות (participation only; Cantril is monthly — Karin 31.10); A-14: adjustable per company 1–20, vp_hr only'),
  (NULL, 'golden_spoons_per_quarterly_questionnaire', 'numeric', 10,  NULL, 'set',         false, 'Karin 31.10: TPS-12 / IHS = 10 כפיות per participation, same as a monthly questionnaire; A-14: adjustable per company 1–20, vp_hr only'),
  (NULL, 'golden_spoons_per_checkin',     'numeric', NULL, NULL, 'not_defined', false, 'v3 §6.1: midday check-in participation — לא הוגדר'),
  (NULL, 'golden_spoons_per_shift',       'numeric', 2.0,  NULL, 'set',         false, 'O-16 / Q11 (Karin 24.10): 2 per shift (morning shift-start check-in)'),
  (NULL, 'golden_spoons_per_onboarding',  'numeric', 10.0, NULL, 'set',         false, 'O-16 / Q11 (Karin 24.10): 10 at signup'),
  (NULL, 'movement_rate_multiplier',      'numeric', 1.5,  NULL, 'set',         true,  'Karin 30.10: 5th signal — team rate ≥ 1.5 × organization average'),
  (NULL, 'movement_min_events',           'numeric', 2,    NULL, 'set',         true,  'Karin 30.10: 5th signal — at least 2 events'),
  (NULL, 'movement_min_team_size',        'numeric', 10,   NULL, 'set',         true,  'Karin 30.10: 5th signal is SENSITIVE — shown only for teams of ≥ 10 employees'),
  (NULL, 'movement_window_months',        'numeric', 3,    NULL, 'set',         true,  'Karin 30.10: events of the last 3 months ÷ employees in the team')
ON CONFLICT ((COALESCE(company_id, '00000000-0000-0000-0000-000000000000'::uuid)), setting_key) DO UPDATE SET
  value_kind = EXCLUDED.value_kind, value_numeric = EXCLUDED.value_numeric, value_text = EXCLUDED.value_text,
  value_status = EXCLUDED.value_status, is_locked = EXCLUDED.is_locked, source_note = EXCLUDED.source_note;
-- v3 §6.1 movement_rise_pct ("לא הוגדר (הוצע 15%)") is SUPERSEDED by Karin 30.10 (multiplier / min events / min team size).
DELETE FROM agent_settings WHERE company_id IS NULL AND setting_key IN ('movement_rise_pct', 'margin_budget_points_pcq', 'margin_budget_points_ihs');

-- everstore_budget — Agent 1 monthly EverStore budget in Golden Spoons (company-local month; set by cfo / vp_hr).
CREATE TABLE IF NOT EXISTS everstore_budget (
    company_id            uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    budget_month          date NOT NULL CHECK (extract(day FROM budget_month) = 1),
    budget_golden_spoons  numeric(12, 1) NOT NULL CHECK (budget_golden_spoons > 0),
    set_at                timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (company_id, budget_month)
);

-- everstore_item_cost — INTERNAL ILS cost of a catalog item (avg_redeemed liability method). Kept out of
-- shop_item_catalog because employees can read the catalog: no conversion rate may ever reach an employee.
CREATE TABLE IF NOT EXISTS everstore_item_cost (
    item_id            varchar(64) PRIMARY KEY REFERENCES shop_item_catalog(item_id) ON DELETE CASCADE,
    internal_cost_ils  numeric(12, 2) NOT NULL CHECK (internal_cost_ils >= 0),
    updated_at         timestamptz NOT NULL DEFAULT clock_timestamp()
);

-- agent_daily_summaries — Agent 1: ONE summary per company-local day, only on days a threshold was crossed.
CREATE TABLE IF NOT EXISTS agent_daily_summaries (
    summary_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id          uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    local_date          date NOT NULL,
    budget_month        date NOT NULL,
    thresholds_crossed  int[] NOT NULL CHECK (cardinality(thresholds_crossed) >= 1),
    utilization_pct     numeric(8, 2) NOT NULL,
    forecast_pct        numeric(8, 2),
    sent_at             timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (company_id, local_date)
);

-- golden_spoons_ledger — internal, append-only: reset of a departed employee's balance on day 31 (v3 §3.3).
CREATE TABLE IF NOT EXISTS golden_spoons_ledger (
    entry_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    company_id     uuid REFERENCES companies(company_id) ON DELETE SET NULL,
    event_type     text NOT NULL CHECK (event_type IN ('expired_after_exit')),
    amount         numeric(10, 1) NOT NULL CHECK (amount > 0),
    exit_deadline  date NOT NULL,
    created_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (user_id, event_type, exit_deadline)
);
DROP TRIGGER IF EXISTS trg_golden_spoons_ledger_worm ON golden_spoons_ledger;
CREATE TRIGGER trg_golden_spoons_ledger_worm
    BEFORE UPDATE OR DELETE ON golden_spoons_ledger
    FOR EACH ROW EXECUTE FUNCTION fn_worm_immutable('ledger_immutable');

-- remediation_records — documented fix (v3 §5.3): group, date, what was fixed, approver, reduction.
CREATE TABLE IF NOT EXISTS remediation_records (
    remediation_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id        uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    group_id          varchar(255) NOT NULL,          -- team = company + department
    remediated_on     date NOT NULL,
    what_fixed        text NOT NULL CHECK (length(btrim(what_fixed)) > 0),
    approved_by       uuid REFERENCES users(user_id) ON DELETE SET NULL,   -- internal; never in agent output
    reduction_amount  numeric(14, 2) NOT NULL CHECK (reduction_amount > 0),
    created_at        timestamptz NOT NULL DEFAULT clock_timestamp()
);
DROP TRIGGER IF EXISTS trg_remediation_records_worm ON remediation_records;
CREATE TRIGGER trg_remediation_records_worm
    BEFORE UPDATE OR DELETE ON remediation_records
    FOR EACH ROW EXECUTE FUNCTION fn_worm_immutable('ledger_immutable');

-- happiness_debt_events — every Happiness Debt movement (v3 §5.3, NO person_id). leaver_transfer moves a
-- leaver's share to the memo line "יצא עם העוזבים" (never deleted); remediation reduces it against a record;
-- v1.6.17 (A-8) leaver_reversal returns a transfer to its team when the offboarding is reversed — it points at
-- the original leaver_transfer (reverses_event_id) and exists at most once per transfer.
CREATE TABLE IF NOT EXISTS happiness_debt_events (
    event_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id      uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    group_id        varchar(255) NOT NULL,
    period_month    date NOT NULL CHECK (extract(day FROM period_month) = 1),
    event_type      text NOT NULL CONSTRAINT happiness_debt_events_event_type_check
                    CHECK (event_type IN ('leaver_transfer', 'remediation', 'leaver_reversal')),
    amount          numeric(14, 2) NOT NULL,
    remediation_id  uuid REFERENCES remediation_records(remediation_id),
    reverses_event_id uuid CONSTRAINT happiness_debt_events_reverses_event_id_fkey REFERENCES happiness_debt_events(event_id),
    created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT chk_hde_remediation_link CHECK ((event_type = 'remediation') = (remediation_id IS NOT NULL)),
    CONSTRAINT chk_hde_reversal_link CHECK ((event_type = 'leaver_reversal') = (reverses_event_id IS NOT NULL)),
    -- v1.6.18 (A-12): a reversal returns the open balance, which is 0 when remediations covered the transfer
    CONSTRAINT happiness_debt_events_amount_check CHECK (amount > 0 OR (event_type = 'leaver_reversal' AND amount = 0))
);
-- v1.6.17 upgrade of a v1.6.16 table (adds the reversal type and link; no-op when already present).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public'
                  AND table_name = 'happiness_debt_events' AND column_name = 'reverses_event_id') THEN
    ALTER TABLE happiness_debt_events DROP CONSTRAINT IF EXISTS happiness_debt_events_event_type_check;
    ALTER TABLE happiness_debt_events ADD CONSTRAINT happiness_debt_events_event_type_check
      CHECK (event_type IN ('leaver_transfer', 'remediation', 'leaver_reversal'));
    ALTER TABLE happiness_debt_events ADD COLUMN reverses_event_id uuid
      CONSTRAINT happiness_debt_events_reverses_event_id_fkey REFERENCES happiness_debt_events(event_id);
    ALTER TABLE happiness_debt_events ADD CONSTRAINT chk_hde_reversal_link
      CHECK ((event_type = 'leaver_reversal') = (reverses_event_id IS NOT NULL));
  END IF;
END $$;
-- v1.6.18 upgrade of a v1.6.17 table (A-12): allow a documented 0 reversal (fully remediated transfer).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'happiness_debt_events'::regclass
                  AND conname = 'happiness_debt_events_amount_check'
                  AND pg_get_constraintdef(oid) LIKE '%leaver_reversal%') THEN
    ALTER TABLE happiness_debt_events DROP CONSTRAINT IF EXISTS happiness_debt_events_amount_check;
    ALTER TABLE happiness_debt_events ADD CONSTRAINT happiness_debt_events_amount_check
      CHECK (amount > 0 OR (event_type = 'leaver_reversal' AND amount = 0));
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_hde_company_period ON happiness_debt_events (company_id, period_month);
-- One reversal per leaver_transfer (idempotency backstop).
CREATE UNIQUE INDEX IF NOT EXISTS uq_hde_one_reversal ON happiness_debt_events (reverses_event_id)
    WHERE event_type = 'leaver_reversal';

-- happiness_debt_leaver_link — v1.6.17 (A-8) INTERNAL link from a leaver_transfer event to the employee who
-- left, needed only to find the transfer to reverse when the offboarding is reversed. Closed to clients
-- (RLS forced, no grants), never returned by any RPC, removed when the employee's pseudonym key is
-- crypto-shredded (a reversal is impossible after that). happiness_debt_events itself holds no person column.
CREATE TABLE IF NOT EXISTS happiness_debt_leaver_link (
    event_id    uuid PRIMARY KEY REFERENCES happiness_debt_events(event_id) ON DELETE CASCADE,
    user_id     uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    created_at  timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX IF NOT EXISTS idx_hdll_user ON happiness_debt_leaver_link (user_id);

-- happiness_debt_remediation_allocation — v1.6.18 (A-12): which leaver_transfer a documented remediation was made
-- against, and how much of it. A new remediation is attributed to exactly ONE transfer of its own team and never
-- exceeds that transfer's open balance, so it can never reduce another leaver's share. Open balance of a transfer
-- = amount − Σ allocations − its reversal. WORM, no person column, closed to clients.
CREATE TABLE IF NOT EXISTS happiness_debt_remediation_allocation (
    remediation_event_id uuid NOT NULL REFERENCES happiness_debt_events(event_id) ON DELETE CASCADE,
    transfer_event_id    uuid NOT NULL REFERENCES happiness_debt_events(event_id) ON DELETE CASCADE,
    amount               numeric(14, 2) NOT NULL CHECK (amount > 0),
    created_at           timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (remediation_event_id, transfer_event_id)
);
CREATE INDEX IF NOT EXISTS idx_hdra_transfer ON happiness_debt_remediation_allocation (transfer_event_id);
DROP TRIGGER IF EXISTS trg_hdra_worm ON happiness_debt_remediation_allocation;
CREATE TRIGGER trg_hdra_worm
    BEFORE UPDATE OR DELETE ON happiness_debt_remediation_allocation
    FOR EACH ROW EXECUTE FUNCTION fn_worm_immutable('ledger_immutable');

-- v1.6.18 upgrade (A-12): a v1.6.17 remediation was team-level only. Each unattributed remediation is allocated
-- to its own team's transfers, oldest first, never above a transfer's open balance and never to a transfer of a
-- later month; any remainder stays unattributed (it still reduces the company memo line as it did in v1.6.17,
-- but no transfer). No-op on a fresh database or once every remediation is attributed.
DO $$
DECLARE r record; t record; v_left numeric; v_open numeric; v_take numeric;
BEGIN
  FOR r IN SELECT e.* FROM happiness_debt_events e
            WHERE e.event_type = 'remediation'
              AND NOT EXISTS (SELECT 1 FROM happiness_debt_remediation_allocation a WHERE a.remediation_event_id = e.event_id)
            ORDER BY e.created_at, e.event_id LOOP
    v_left := r.amount;
    FOR t IN SELECT x.* FROM happiness_debt_events x
              WHERE x.event_type = 'leaver_transfer' AND x.company_id = r.company_id AND x.group_id = r.group_id
                AND x.period_month <= r.period_month
              ORDER BY x.created_at, x.event_id LOOP
      EXIT WHEN v_left <= 0;
      v_open := t.amount
        - COALESCE((SELECT sum(a.amount) FROM happiness_debt_remediation_allocation a WHERE a.transfer_event_id = t.event_id), 0)
        - COALESCE((SELECT sum(v.amount) FROM happiness_debt_events v
                     WHERE v.event_type = 'leaver_reversal' AND v.reverses_event_id = t.event_id), 0);
      IF v_open > 0 THEN
        v_take := least(v_open, v_left);
        INSERT INTO happiness_debt_remediation_allocation (remediation_event_id, transfer_event_id, amount)
        VALUES (r.event_id, t.event_id, v_take);
        v_left := v_left - v_take;
      END IF;
    END LOOP;
  END LOOP;
END $$;
DROP TRIGGER IF EXISTS trg_happiness_debt_events_worm ON happiness_debt_events;
CREATE TRIGGER trg_happiness_debt_events_worm
    BEFORE UPDATE OR DELETE ON happiness_debt_events
    FOR EACH ROW EXECUTE FUNCTION fn_worm_immutable('ledger_immutable');

-- happiness_debt_ledger — the Shadow Balance split into the 4 hidden-obligation classes (v3 §5.2) per company
-- month (management disclosure, not a book provision). exported_on_exit rows mirror the leaver memo line.
CREATE TABLE IF NOT EXISTS happiness_debt_ledger (
    entry_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id        uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    group_id          varchar(255),                 -- NULL = company level
    period_month      date NOT NULL CHECK (extract(day FROM period_month) = 1),
    obligation_class  text CHECK (obligation_class IN ('dormant_legal', 'constructive', 'statistical_accrued', 'pure_economic_erosion')),
    amount            numeric(14, 2) NOT NULL CHECK (amount >= 0),
    exported_on_exit  boolean NOT NULL DEFAULT false,
    created_at        timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT chk_hdl_class_or_exit CHECK (exported_on_exit OR obligation_class IS NOT NULL)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_hdl_split
    ON happiness_debt_ledger (company_id, period_month, obligation_class) WHERE NOT exported_on_exit;

-- team_movements — 5th burnout signal input (v3 §6.1 + Karin 30.10): aggregate counts per team and month of
-- voluntary exits and transfer requests. No names, no person_id.
CREATE TABLE IF NOT EXISTS team_movements (
    company_id         uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    group_id           varchar(255) NOT NULL,
    period_month       date NOT NULL CHECK (extract(day FROM period_month) = 1),
    voluntary_exits    int NOT NULL DEFAULT 0 CHECK (voluntary_exits >= 0),
    transfer_requests  int NOT NULL DEFAULT 0 CHECK (transfer_requests >= 0),
    updated_at         timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (company_id, group_id, period_month)
);

-- metric_assurance — assurance tier 0–4 per board metric (v3 §5.6). Missing row = tier 0 (לא מאומת).
CREATE TABLE IF NOT EXISTS metric_assurance (
    company_id      uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    metric_key      text NOT NULL,
    tier            smallint NOT NULL CHECK (tier BETWEEN 0 AND 4),
    explanation_he  text,
    updated_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (company_id, metric_key)
);

-- bcr_checks — monthly 15-question (Ping-Pong) check of the EverStore budget (v3 §3.7): B1–B4, C1–C7, R1–R4.
CREATE TABLE IF NOT EXISTS bcr_checks (
    company_id            uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    check_month           date NOT NULL CHECK (extract(day FROM check_month) = 1),
    answers               jsonb NOT NULL,
    independent_approved  boolean NOT NULL DEFAULT false,   -- C6–C7 count only with independent approval
    yes_count             int NOT NULL CHECK (yes_count BETWEEN 0 AND 15),
    result_he             text NOT NULL,
    created_at            timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (company_id, check_month)
);

-- epwi_inputs — OPTIONAL group-level EPWI inputs (v3 §6.1): after-hours messages, schedule volatility.
-- Stored only; the EPWI formula and the Weinberg table (0/20/40/60/75 %) are unchanged.
CREATE TABLE IF NOT EXISTS epwi_inputs (
    company_id            uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    group_id              varchar(255) NOT NULL,
    week_start_date       date NOT NULL,
    after_hours_messages  int CHECK (after_hours_messages IS NULL OR after_hours_messages >= 0),
    schedule_volatility   numeric(8, 4) CHECK (schedule_volatility IS NULL OR schedule_volatility >= 0),
    PRIMARY KEY (company_id, group_id, week_start_date)
);

-- board_reconciliation — CFO inputs for the line-by-line reconciliation (v3 §5.1): GAAP EBITDA and payroll
-- expense per company month. The 4 debt lines come from happiness_debt_ledger, מס קיפוח from the system.
CREATE TABLE IF NOT EXISTS board_reconciliation (
    company_id       uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    period_month     date NOT NULL CHECK (extract(day FROM period_month) = 1),
    gaap_ebitda      numeric(14, 2) NOT NULL,
    payroll_expense  numeric(14, 2) CHECK (payroll_expense IS NULL OR payroll_expense >= 0),
    is_first_period  boolean NOT NULL DEFAULT false,   -- the company's first report: no prior period exists
    entered_at       timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (company_id, period_month)
);

-- board_report — every PUBLISHED monthly board report (append-only snapshot of the JSON returned).
CREATE TABLE IF NOT EXISTS board_report (
    report_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id    uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    period_month  date NOT NULL CHECK (extract(day FROM period_month) = 1),
    report        jsonb NOT NULL,
    built_at      timestamptz NOT NULL DEFAULT clock_timestamp()
);
DROP TRIGGER IF EXISTS trg_board_report_worm ON board_report;
CREATE TRIGGER trg_board_report_worm
    BEFORE UPDATE OR DELETE ON board_report
    FOR EACH ROW EXECUTE FUNCTION fn_worm_immutable('ledger_immutable');

-- Lock every agent table: RLS on + forced, no client privileges (SECURITY DEFINER RPCs only).
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['agent_settings', 'everstore_budget', 'everstore_item_cost', 'agent_daily_summaries',
                           'golden_spoons_ledger', 'remediation_records', 'happiness_debt_events',
                           'happiness_debt_ledger', 'team_movements', 'metric_assurance', 'bcr_checks',
                           'epwi_inputs', 'board_reconciliation', 'board_report', 'happiness_debt_leaver_link',
                           'happiness_debt_remediation_allocation'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format('REVOKE ALL ON TABLE %I FROM PUBLIC, anon, authenticated', t);
  END LOOP;
END $$;

-- v1.6.16 (v3 §3.6): a submission records whether its participation amount was defined ('set') or the
-- setting was still "לא הוגדר" ('not_defined' → 0 Golden Spoons credited, nothing invented).
ALTER TABLE questionnaire_submission ADD COLUMN IF NOT EXISTS
    reward_status text NOT NULL DEFAULT 'set' CHECK (reward_status IN ('set', 'not_defined'));
-- v1.6.18 (A-14): non-retroactive proof — each submission snapshots WHICH setting paid it and since when the
-- value it earned was in effect (questionnaire_reward_history.effective_from; NULL = the pack default, never
-- changed for the company). reward_golden_spoons already snapshots the amount. NULL on pre-1.6.18 rows.
ALTER TABLE questionnaire_submission ADD COLUMN IF NOT EXISTS reward_setting_key text;
ALTER TABLE questionnaire_submission ADD COLUMN IF NOT EXISTS reward_effective_from timestamptz;

-- v1.6.18 (A-14) questionnaire_reward_history — WORM history of every change of a company's questionnaire
-- participation amount (monthly / short / quarterly). value_after is the amount in effect from effective_from on
-- (scope 'default' = the company went back to the pack default). Who changed it is in access_audit_log (WORM);
-- this table has no person column. Closed to clients (RLS forced, no grant).
CREATE TABLE IF NOT EXISTS questionnaire_reward_history (
    history_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id      uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    setting_key     text NOT NULL CHECK (setting_key IN ('golden_spoons_per_questionnaire',
                                                         'golden_spoons_per_short_questionnaire',
                                                         'golden_spoons_per_quarterly_questionnaire')),
    value_before    numeric(10, 1),
    value_after     numeric(10, 1) NOT NULL CHECK (value_after BETWEEN 1 AND 20),
    scope_after     text NOT NULL CHECK (scope_after IN ('company', 'default')),
    effective_from  timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX IF NOT EXISTS idx_qrh_company_key ON questionnaire_reward_history (company_id, setting_key, effective_from DESC);
ALTER TABLE questionnaire_reward_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE questionnaire_reward_history FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE questionnaire_reward_history FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_questionnaire_reward_history_worm ON questionnaire_reward_history;
CREATE TRIGGER trg_questionnaire_reward_history_worm
    BEFORE UPDATE OR DELETE ON questionnaire_reward_history
    FOR EACH ROW EXECUTE FUNCTION fn_worm_immutable('ledger_immutable');
-- v1.6.18 (A-13): refunds are WORM.
DROP TRIGGER IF EXISTS trg_time_benefit_refund_worm ON time_benefit_refund;
CREATE TRIGGER trg_time_benefit_refund_worm
    BEFORE UPDATE OR DELETE ON time_benefit_refund
    FOR EACH ROW EXECUTE FUNCTION fn_worm_immutable('ledger_immutable');
