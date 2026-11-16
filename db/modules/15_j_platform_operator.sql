-- =============================================================================
-- CHR-ETRS v1.7.0 fixes · modules/15_j_platform_operator.sql — the CHR-ETRS operator as the last reminder recipient
-- (Karin 16.11 21:04–21:07, J-250 / J-251 / J-252):
--   * the operator's address is NOT known: it comes only from db/config/platform_operator.json (starts EMPTY);
--   * while it is empty, an operator message is still recorded in the outbox as a HELD row (recipient 'לא הוגדר',
--     hold_reason 'recipient_not_configured') and released to the address once the config is loaded;
--   * the operator message names only the company ("בחברה X אין vp_hr פעילה") — never an employee, count, date or
--     balance;
--   * fn_j_companies_without_vp_hr feeds the go-live preflight (tools/preflight.py --db).
-- =============================================================================

-- J-251: the configured CHR-ETRS operator addresses (empty until db/config/platform_operator.json is filled).
CREATE OR REPLACE FUNCTION fn_j_operator_addresses()
RETURNS SETOF text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$ SELECT r.address FROM j_config_recipient r WHERE r.kind = 'platform_operator' ORDER BY r.address $$;

-- Active users of a company with this app_role and a non-empty e-mail (J-250 fallback levels vp_hr → cfo).
CREATE OR REPLACE FUNCTION fn_j_company_role_addresses(p_company uuid, p_role text)
RETURNS SETOF text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT DISTINCT btrim(u.email) FROM users u
   WHERE u.company_id = p_company AND u.app_role = p_role AND u.employment_ended_at IS NULL
     AND NULLIF(btrim(u.email), '') IS NOT NULL
$$;

-- J-250: the operator's message text for a company without an active vp_hr (Karin's wording; company name only).
CREATE OR REPLACE FUNCTION fn_j_operator_no_vp_hr_he(p_company uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$ SELECT 'בחברה ' || c.company_name || ' אין vp_hr פעילה' FROM companies c WHERE c.company_id = p_company $$;

-- J-250 / J-251: tell the CHR-ETRS operator that a company has no active vp_hr (once per company day per address).
-- No operator address configured → one HELD row (recipient 'לא הוגדר'). Returns the number of rows queued now.
CREATE OR REPLACE FUNCTION fn_j_notify_operator_no_vp_hr(p_company uuid, p_now timestamptz)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_msg  text := fn_j_operator_no_vp_hr_he(p_company);
  v_day  text := fn_j_company_today(p_company, p_now)::text;
  v_n    int := 0;
  a      text;
BEGIN
  FOR a IN SELECT fn_j_operator_addresses() LOOP
    IF fn_j_outbox_put(p_company, 'operator_no_vp_hr', a, v_msg, jsonb_build_object('message_he', v_msg),
                       'operator_no_vp_hr:' || p_company || ':' || v_day || ':' || a) THEN
      v_n := v_n + 1;
    END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM fn_j_operator_addresses())
     AND fn_j_outbox_put(p_company, 'operator_no_vp_hr', fn_j_not_defined_he(), v_msg,
                         jsonb_build_object('message_he', v_msg), 'operator_no_vp_hr:' || p_company || ':' || v_day,
                         'recipient_not_configured') THEN
    v_n := v_n + 1;
  END IF;
  RETURN v_n;
END;
$$;

-- J-251: release the HELD operator rows to every configured operator address (a copy per address; the held row is
-- marked 'released', never deleted). Returns the number of copies queued.
CREATE OR REPLACE FUNCTION fn_j_release_held_operator_rows()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  h   j_outbox;
  a   text;
  v_n int := 0;
BEGIN
  FOR h IN SELECT * FROM j_outbox WHERE kind = 'operator_no_vp_hr' AND hold_reason = 'recipient_not_configured'
              AND EXISTS (SELECT 1 FROM fn_j_operator_addresses()) FOR UPDATE LOOP
    FOR a IN SELECT fn_j_operator_addresses() LOOP
      IF fn_j_outbox_put(h.company_id, h.kind, a, h.subject_he, h.payload, h.dedup_key || ':' || a) THEN
        v_n := v_n + 1;
      END IF;
    END LOOP;
    UPDATE j_outbox SET hold_reason = 'released' WHERE outbox_id = h.outbox_id;
  END LOOP;
  RETURN v_n;
END;
$$;

-- Load db/config/platform_operator.json ({"recipients": ["a@b", …]}) — system only. Adds addresses (none deleted
-- here — removal = a reviewed PR + a manual service step), then releases held operator rows. Returns the file's count.
CREATE OR REPLACE FUNCTION fn_sync_platform_operator(p_config jsonb)
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
    INSERT INTO j_config_recipient (kind, address) VALUES ('platform_operator', btrim(a)) ON CONFLICT DO NOTHING;
    v_n := v_n + 1;
  END LOOP;
  PERFORM fn_j_release_held_operator_rows();
  RETURN v_n;
END;
$$;

-- J-252 (go-live preflight): names of active companies (service not ended) without an active vp_hr with an e-mail.
-- System only; returns company names only.
CREATE OR REPLACE FUNCTION fn_j_companies_without_vp_hr()
RETURNS SETOF text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  PERFORM fn_j_assert_system();
  RETURN QUERY SELECT c.company_name::text FROM companies c
    WHERE c.service_ended_at IS NULL
      AND NOT EXISTS (SELECT 1 FROM fn_j_company_role_addresses(c.company_id, 'vp_hr'))
    ORDER BY c.company_name;
END;
$$;

REVOKE ALL ON FUNCTION fn_j_operator_addresses(), fn_j_company_role_addresses(uuid, text), fn_j_operator_no_vp_hr_he(uuid),
  fn_j_notify_operator_no_vp_hr(uuid, timestamptz), fn_j_release_held_operator_rows(), fn_sync_platform_operator(jsonb),
  fn_j_companies_without_vp_hr() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION fn_sync_platform_operator(jsonb), fn_j_companies_without_vp_hr() TO service_role;
