-- =============================================================================
-- CHR-ETRS v1.7.0 · modules/10_j_common.sql — shared helpers for J-178 … J-219 (Karin 16.11)
-- Loaded after schema.sql + rpc.sql (modules/all.sql). Idempotent. No invented numbers: every value
-- that Karin did not set is NULL / 'לא הוגדר'.
-- =============================================================================

-- Text shown for any unset value (no invented numbers / addresses / legal duties).
CREATE OR REPLACE FUNCTION fn_j_not_defined_he()
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$ SELECT 'לא הוגדר'::text $$;

-- Write one access_audit_log row for the caller with an EXPLICIT company (researchers / auditors / system have no
-- users.company_id of their own, so fn_audit_view cannot be used). viewer_id = auth.uid() (NULL for a system job).
CREATE OR REPLACE FUNCTION fn_j_audit(p_action text, p_company uuid, p_scope jsonb DEFAULT '{}'::jsonb)
RETURNS void
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  INSERT INTO access_audit_log (viewer_id, company_id, action, scope)
  VALUES (auth.uid(), p_company, p_action, COALESCE(p_scope, '{}'::jsonb))
$$;
REVOKE ALL ON FUNCTION fn_j_audit(text, uuid, jsonb) FROM PUBLIC, anon, authenticated;

-- Server secret by name (J-184 / J-208): read ONLY from the server's secrets vault, which the server process injects
-- into the session as the setting chr.secret_<name> (never stored in a DB table, never in nb_config, never in git).
-- Placeholder only — no key value in the pack. Missing → 422 secret_not_configured.
CREATE OR REPLACE FUNCTION fn_j_secret(p_name text)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v text := NULLIF(current_setting('chr.secret_' || p_name, true), '');
BEGIN
  IF v IS NULL THEN
    PERFORM fn_raise_unprocessable('secret_not_configured');
  END IF;
  RETURN v;
END;
$$;
REVOKE ALL ON FUNCTION fn_j_secret(text) FROM PUBLIC, anon, authenticated;

-- HMAC-SHA256 (hex) of a value with a named server secret (J-184 company code, J-208 badge number).
CREATE OR REPLACE FUNCTION fn_j_hmac(p_secret_name text, p_value text)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, extensions
AS $$
  SELECT encode(hmac(convert_to(p_value, 'UTF8'), convert_to(fn_j_secret(p_secret_name), 'UTF8'), 'sha256'), 'hex')
$$;
REVOKE ALL ON FUNCTION fn_j_hmac(text, text) FROM PUBLIC, anon, authenticated;

-- Length check of a free text (trimmed): true when min ≤ length ≤ max.
CREATE OR REPLACE FUNCTION fn_j_text_ok(p_text text, p_min int, p_max int)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$ SELECT p_text IS NOT NULL AND length(btrim(p_text)) BETWEEN p_min AND p_max $$;

-- Calendar quarter label 'YYYY-Qn' of a date.
CREATE OR REPLACE FUNCTION fn_j_quarter_label(p_day date)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$ SELECT to_char(p_day, 'YYYY') || '-Q' || extract(quarter FROM p_day)::int $$;

-- First day of a calendar quarter given as 'YYYY-Qn'; NULL when malformed.
CREATE OR REPLACE FUNCTION fn_j_quarter_start(p_label text)
RETURNS date
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE WHEN p_label ~ '^[0-9]{4}-Q[1-4]$'
              THEN make_date(substr(p_label, 1, 4)::int, (substr(p_label, 7, 1)::int - 1) * 3 + 1, 1) END
$$;

-- J-185 (Karin 16.11): a calendar quarter enters a research export only when it has ended AND 14 days have passed
-- since its end, counted on the company's own calendar (companies.timezone).
CREATE OR REPLACE FUNCTION fn_j_quarter_ready(p_company uuid, p_quarter_start date, p_now timestamptz)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT fn_agent_local_ts(p_company, p_now)::date >= (p_quarter_start + interval '3 months')::date + 14
$$;
REVOKE ALL ON FUNCTION fn_j_quarter_ready(uuid, date, timestamptz) FROM PUBLIC, anon, authenticated;

-- Today on the company's calendar.
CREATE OR REPLACE FUNCTION fn_j_company_today(p_company uuid, p_now timestamptz DEFAULT NULL)
RETURNS date
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$ SELECT fn_agent_local_ts(p_company, COALESCE(p_now, clock_timestamp()))::date $$;
REVOKE ALL ON FUNCTION fn_j_company_today(uuid, timestamptz) FROM PUBLIC, anon, authenticated;

-- Raise 403 access_denied unless the caller is a system process (service role / server login, never a client).
CREATE OR REPLACE FUNCTION fn_j_assert_system()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF fn_is_client_call() THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION fn_j_assert_system() FROM PUBLIC, anon, authenticated;

-- ---------- J-191 / J-196 / J-212: outbox (the DB only queues; sending happens outside the DB) ----------
CREATE TABLE IF NOT EXISTS j_outbox (
    outbox_id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id        uuid REFERENCES companies(company_id) ON DELETE SET NULL,
    kind              text NOT NULL CHECK (kind IN ('method_comment', 'leaver_donation_reminder',
                                                    'supplier_order', 'supplier_monthly_report')),
    recipient_address text NOT NULL,              -- from db/config or the employee's own address; never invented
    subject_he        text NOT NULL,
    payload           jsonb NOT NULL DEFAULT '{}'::jsonb,
    dedup_key         text UNIQUE,                -- idempotent enqueue (reminders, monthly reports)
    created_at        timestamptz NOT NULL DEFAULT clock_timestamp(),
    sent_at           timestamptz
);
ALTER TABLE j_outbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE j_outbox FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE j_outbox FROM PUBLIC, anon, authenticated;

-- Queue one message (system helper). Returns false when the dedup key was already queued.
CREATE OR REPLACE FUNCTION fn_j_outbox_put(p_company uuid, p_kind text, p_to text, p_subject text, p_payload jsonb,
                                           p_dedup text DEFAULT NULL)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO j_outbox (company_id, kind, recipient_address, subject_he, payload, dedup_key)
  VALUES (p_company, p_kind, p_to, p_subject, COALESCE(p_payload, '{}'::jsonb), p_dedup)
  ON CONFLICT (dedup_key) DO NOTHING
  RETURNING outbox_id INTO v_id;
  RETURN v_id IS NOT NULL;
END;
$$;
REVOKE ALL ON FUNCTION fn_j_outbox_put(uuid, text, text, text, jsonb, text) FROM PUBLIC, anon, authenticated;

-- The sender (outside the DB, service role) marks a message as sent. Only sent_at changes.
CREATE OR REPLACE FUNCTION rpc_outbox_mark_sent(p_outbox_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  PERFORM fn_j_assert_system();
  UPDATE j_outbox SET sent_at = COALESCE(sent_at, clock_timestamp()) WHERE outbox_id = p_outbox_id;
END;
$$;
REVOKE ALL ON FUNCTION rpc_outbox_mark_sent(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION rpc_outbox_mark_sent(uuid) TO service_role;

-- ---------- J-191: recipient addresses (db/config/method_team.json; starts EMPTY) ----------
CREATE TABLE IF NOT EXISTS j_config_recipient (
    kind     text NOT NULL CHECK (kind IN ('method_team')),
    address  text NOT NULL CHECK (address ~ '^[^@\s]+@[^@\s]+$'),
    PRIMARY KEY (kind, address)
);
ALTER TABLE j_config_recipient ENABLE ROW LEVEL SECURITY;
ALTER TABLE j_config_recipient FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE j_config_recipient FROM PUBLIC, anon, authenticated;

-- Load db/config/method_team.json ({"recipients": ["a@b", …]}) — system only. Adds new addresses; an address that
-- left the file is NOT deleted here (removal = a reviewed PR + manual service step; no bulk deletes).
CREATE OR REPLACE FUNCTION fn_sync_method_team(p_config jsonb)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_n int := 0;
  a   text;
BEGIN
  PERFORM fn_j_assert_system();
  FOR a IN SELECT jsonb_array_elements_text(COALESCE(p_config->'recipients', '[]'::jsonb)) LOOP
    INSERT INTO j_config_recipient (kind, address) VALUES ('method_team', btrim(a)) ON CONFLICT DO NOTHING;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION fn_sync_method_team(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION fn_sync_method_team(jsonb) TO service_role;

-- J-190 (DRAFT): companies.service_ended_at is set ONLY by config / deploy (db/config/company_service_end.json).
CREATE OR REPLACE FUNCTION fn_sync_company_service_end(p_config jsonb)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_n int := 0;
  e   jsonb;
BEGIN
  PERFORM fn_j_assert_system();
  FOR e IN SELECT jsonb_array_elements(COALESCE(p_config->'companies', '[]'::jsonb)) LOOP
    UPDATE companies SET service_ended_at = (e->>'service_ended_at')::timestamptz
     WHERE company_id = (e->>'company_id')::uuid;
    PERFORM fn_j_audit('company_service_end_set', (e->>'company_id')::uuid,
                       jsonb_build_object('service_ended_at', e->>'service_ended_at'));
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION fn_sync_company_service_end(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION fn_sync_company_service_end(jsonb) TO service_role;
