-- =============================================================================
-- CHR-ETRS v1.7.0 · tests/j_helpers.sql — shared harness of the J-178 … J-219 suites (pgTAP-style PASS lines;
-- pgTAP is not installed). Run on a FRESH database after ref_country_calendar.sql + schema.sql + rpc.sql +
-- modules/all.sql. Real clock (no libfaketime): every time is relative to clock_timestamp() or a p_now argument.
-- No identifier is printed.
-- =============================================================================
\set QUIET on
SET client_min_messages = warning;

-- Print one PASS line.
CREATE OR REPLACE FUNCTION t_pass(p_name text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN RAISE WARNING 'PASS %', p_name; END $$;

-- Assert a boolean.
CREATE OR REPLACE FUNCTION t_assert(p_name text, p_ok boolean) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_ok IS NOT TRUE THEN RAISE EXCEPTION 'FAIL %', p_name; END IF;
  PERFORM t_pass(p_name);
END $$;

-- Deterministic fixture uuid of a key.
CREATE OR REPLACE FUNCTION t_u(p_key text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT md5('j178-' || p_key)::uuid
$$;

-- Impersonate a user for auth.uid() (NULL = nobody).
CREATE OR REPLACE FUNCTION t_as(p_key text) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', COALESCE(t_u(p_key)::text, ''), false);
$$;

-- Create a company (Asia/Jerusalem, IL) with an optional industry.
CREATE OR REPLACE FUNCTION t_company(p_key text, p_industry text DEFAULT NULL) RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO companies (company_id, company_name, industry, country, week_start_dow, last_workday_dow, timezone)
  VALUES (t_u(p_key), 'Company ' || p_key, p_industry, 'IL', 0, 4, 'Asia/Jerusalem') RETURNING company_id
$$;

-- Create one user of a company.
CREATE OR REPLACE FUNCTION t_mk(p_key text, p_co text, p_app text DEFAULT 'employee', p_org_role text DEFAULT 'employee',
                                p_dept text DEFAULT 'TEAM', p_mgr text DEFAULT NULL) RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id) VALUES (t_u(p_key));
  INSERT INTO users (user_id, company_id, reports_to, email, full_name, department, app_role, org_role_code, timezone, hire_date)
  VALUES (t_u(p_key), t_u(p_co), CASE WHEN p_mgr IS NOT NULL THEN t_u(p_mgr) END, p_key || '@j.test', 'Person ' || p_key,
          p_dept, p_app, p_org_role, 'Asia/Jerusalem', DATE '2025-01-01');
  RETURN t_u(p_key);
END $$;

-- Run p_sql as user p_who under the client role and return its single value as jsonb.
CREATE OR REPLACE FUNCTION t_json_as(p_who text, p_sql text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v jsonb;
BEGIN
  PERFORM t_as(p_who);
  SET LOCAL ROLE authenticated;
  EXECUTE format('SELECT to_jsonb((%s))', p_sql) INTO v;
  RESET ROLE;
  RETURN v;
END $$;

-- Expect p_sql, run as p_who under the client role, to fail with p_code and the Error Contract DETAIL
-- 'http_hint=<p_http>;code=<p_code>' (p_http NULL = only the code / SQLSTATE).
CREATE OR REPLACE FUNCTION t_err_as(p_name text, p_who text, p_sql text, p_code text, p_http int DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_detail text; v_state text; v_msg text;
BEGIN
  BEGIN
    PERFORM t_as(p_who);
    IF p_who IS NOT NULL THEN SET LOCAL ROLE authenticated; END IF;
    EXECUTE p_sql;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_detail = PG_EXCEPTION_DETAIL, v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    RESET ROLE;
    IF (v_msg = p_code OR v_state = p_code)
       AND (p_http IS NULL OR v_detail = format('http_hint=%s;code=%s', p_http, p_code)) THEN
      PERFORM t_pass(p_name);
      RETURN;
    END IF;
    RAISE EXCEPTION 'FAIL % — got [%] % / %, expected % %', p_name, v_state, v_msg, v_detail, p_http, p_code;
  END;
  RAISE EXCEPTION 'FAIL % — no error (expected %)', p_name, p_code;
END $$;

-- Expect a statement run as the superuser / system to fail with p_code (message or SQLSTATE).
CREATE OR REPLACE FUNCTION t_err(p_name text, p_sql text, p_code text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM t_err_as(p_name, NULL, p_sql, p_code);
END $$;

-- True when a jsonb output carries none of the given ids / names (as text).
CREATE OR REPLACE FUNCTION t_free_of(p_out jsonb, p_needles text[]) RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT NOT EXISTS (SELECT 1 FROM unnest(p_needles) n WHERE position(lower(n) IN lower(p_out::text)) > 0)
$$;

-- Every user id of the database (to prove an output is id-free).
CREATE OR REPLACE FUNCTION t_all_user_ids() RETURNS text[] LANGUAGE sql AS $$
  SELECT array_agg(user_id::text) FROM users
$$;

-- Insert one questionnaire submission directly (fixture history on a chosen local date).
CREATE OR REPLACE FUNCTION t_sub(p_key text, p_code text, p_day date, p_score numeric) RETURNS void LANGUAGE sql AS $$
  INSERT INTO questionnaire_submission (user_id, questionnaire_code, period_key, local_date, answers, score, reward_golden_spoons)
  VALUES (t_u(p_key), p_code, p_code || '-' || p_day::text, p_day, '{1}', p_score, 0)
$$;

-- The last completed calendar quarter (start date) on the real clock (Asia/Jerusalem).
CREATE OR REPLACE FUNCTION t_last_q() RETURNS date LANGUAGE sql STABLE AS $$
  SELECT (date_trunc('quarter', clock_timestamp() AT TIME ZONE 'Asia/Jerusalem') - interval '3 months')::date
$$;

-- The test-only placeholder secrets (NOT keys; the real ones come from the server's secrets vault).
SELECT set_config('chr.secret_research_company', 'test-only-placeholder-research', false) AS secret1,
       set_config('chr.secret_badge', 'test-only-placeholder-badge', false) AS secret2;
