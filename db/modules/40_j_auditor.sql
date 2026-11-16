-- =============================================================================
-- CHR-ETRS v1.7.0 · modules/40_j_auditor.sql — external auditor J-203 + auditor letters J-214 (Karin 16.11)
--   * vp_hr opens the account (rpc_provision_external_auditor) and sets TWO things: an access window and a range of
--     data months; outside the window every auditor RPC → 403; read only.
--   * the auditor's change log shows time, role, action AND the acting user id — Karin's explicit exception
--     (J-203), in this output only;
--   * J-214: level 3 / 4 only with a letter vp_hr uploaded (uploader + time logged; the stored file is immutable
--     and its sha256 kept); limited → 3, reasonable → 4; valid only for its own period; cancelling = a 'בוטל'
--     mark (never a delete) → the level returns to 2 with a note in the board report.
-- =============================================================================

CREATE TABLE IF NOT EXISTS auditor_access (
    user_id          uuid PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
    company_id       uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    access_from      timestamptz NOT NULL,
    access_until     timestamptz NOT NULL,
    data_month_from  date NOT NULL,
    data_month_to    date NOT NULL,
    set_by           uuid REFERENCES users(user_id) ON DELETE SET NULL,
    set_at           timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT chk_auditor_window CHECK (access_from < access_until AND data_month_from <= data_month_to
                                         AND data_month_from = date_trunc('month', data_month_from)::date
                                         AND data_month_to = date_trunc('month', data_month_to)::date)
);
ALTER TABLE auditor_access ENABLE ROW LEVEL SECURITY;
ALTER TABLE auditor_access FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE auditor_access FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS auditor_letter (
    letter_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id    uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    metric_key    text NOT NULL,
    period_from   date NOT NULL,
    period_to     date NOT NULL,
    assurance     text NOT NULL CHECK (assurance IN ('limited', 'reasonable')),
    storage_path  text NOT NULL UNIQUE,                -- the immutable object in storage
    sha256        char(64) NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
    uploaded_by   uuid REFERENCES users(user_id) ON DELETE SET NULL,
    uploaded_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT chk_letter_period CHECK (period_from <= period_to
                                        AND period_from = date_trunc('month', period_from)::date
                                        AND period_to = date_trunc('month', period_to)::date)
);

CREATE TABLE IF NOT EXISTS auditor_letter_cancel (
    letter_id     uuid PRIMARY KEY REFERENCES auditor_letter(letter_id) ON DELETE CASCADE,
    cancelled_by  uuid REFERENCES users(user_id) ON DELETE SET NULL,
    cancelled_at  timestamptz NOT NULL DEFAULT clock_timestamp()
);

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['auditor_letter', 'auditor_letter_cancel'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_%s_worm ON %I', t, t);
    EXECUTE format('CREATE TRIGGER trg_%s_worm BEFORE UPDATE OR DELETE ON %I FOR EACH ROW '
                   'EXECUTE FUNCTION fn_worm_immutable(''ledger_immutable'')', t, t);
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format('REVOKE ALL ON TABLE %I FROM PUBLIC, anon, authenticated', t);
  END LOOP;
END $$;

-- ---------- J-203 ----------

-- Validate an access window + data-month range; 400 invalid_auditor_window otherwise.
CREATE OR REPLACE FUNCTION fn_auditor_check_window(p_from timestamptz, p_until timestamptz, p_m_from date, p_m_to date)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_from IS NULL OR p_until IS NULL OR p_m_from IS NULL OR p_m_to IS NULL OR p_from >= p_until
     OR date_trunc('month', p_m_from)::date > date_trunc('month', p_m_to)::date THEN
    PERFORM fn_raise_bad_request('invalid_auditor_window');
  END IF;
END;
$$;

-- vp_hr opens an external-auditor account for her company (no employee profile) with its window + data months.
CREATE OR REPLACE FUNCTION rpc_provision_external_auditor(p_user_id uuid, p_email varchar, p_full_name varchar,
    p_timezone text, p_access_from timestamptz, p_access_until timestamptz, p_data_month_from date, p_data_month_to date)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_comp uuid := fn_my_company();
BEGIN
  PERFORM fn_assert_vp_hr(v_comp);
  IF p_user_id IS NULL OR NULLIF(btrim(p_email), '') IS NULL OR NULLIF(btrim(p_full_name), '') IS NULL
     OR EXISTS (SELECT 1 FROM users u WHERE u.user_id = p_user_id AND u.app_role <> 'external_auditor') THEN
    PERFORM fn_raise_bad_request('invalid_auditor');
  END IF;
  PERFORM fn_auditor_check_window(p_access_from, p_access_until, p_data_month_from, p_data_month_to);
  INSERT INTO auth.users (id) VALUES (p_user_id) ON CONFLICT (id) DO NOTHING;
  INSERT INTO users (user_id, company_id, email, full_name, app_role, org_role_code, timezone, has_employee_profile)
  VALUES (p_user_id, v_comp, btrim(p_email), btrim(p_full_name), 'external_auditor', 'employee', p_timezone, false)
  ON CONFLICT (user_id) DO NOTHING;
  PERFORM rpc_set_auditor_access(p_user_id, p_access_from, p_access_until, p_data_month_from, p_data_month_to);
  PERFORM fn_audit_view('provision_external_auditor', '{}'::jsonb, p_user_id);
  RETURN jsonb_build_object('status', 'provisioned');
END;
$$;

-- vp_hr sets / changes an auditor's access window and data-month range (her company only). Audited.
CREATE OR REPLACE FUNCTION rpc_set_auditor_access(p_user_id uuid, p_access_from timestamptz, p_access_until timestamptz,
                                                  p_data_month_from date, p_data_month_to date)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_comp uuid := fn_my_company();
BEGIN
  PERFORM fn_assert_vp_hr(v_comp);
  IF NOT EXISTS (SELECT 1 FROM users u WHERE u.user_id = p_user_id AND u.company_id = v_comp
                    AND u.app_role = 'external_auditor') THEN
    PERFORM fn_raise_bad_request('invalid_auditor');
  END IF;
  PERFORM fn_auditor_check_window(p_access_from, p_access_until, p_data_month_from, p_data_month_to);
  INSERT INTO auditor_access (user_id, company_id, access_from, access_until, data_month_from, data_month_to, set_by)
  VALUES (p_user_id, v_comp, p_access_from, p_access_until, date_trunc('month', p_data_month_from)::date,
          date_trunc('month', p_data_month_to)::date, auth.uid())
  ON CONFLICT (user_id) DO UPDATE SET access_from = EXCLUDED.access_from, access_until = EXCLUDED.access_until,
    data_month_from = EXCLUDED.data_month_from, data_month_to = EXCLUDED.data_month_to,
    set_by = EXCLUDED.set_by, set_at = clock_timestamp();
  PERFORM fn_audit_view('auditor_access_set', jsonb_build_object('access_from', p_access_from, 'access_until', p_access_until,
                        'data_month_from', p_data_month_from, 'data_month_to', p_data_month_to), p_user_id);
  RETURN jsonb_build_object('status', 'set');
END;
$$;

-- The caller's auditor access row when she is an external auditor inside her window; else 403 access_denied.
CREATE OR REPLACE FUNCTION fn_auditor_current()
RETURNS auditor_access
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  a auditor_access;
BEGIN
  SELECT x.* INTO a FROM auditor_access x JOIN users u ON u.user_id = x.user_id
   WHERE x.user_id = auth.uid() AND u.app_role = 'external_auditor' AND u.employment_ended_at IS NULL
     AND clock_timestamp() >= x.access_from AND clock_timestamp() < x.access_until;
  IF a.user_id IS NULL THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  RETURN a;
END;
$$;

-- J-203 change log for the auditor: changes (settings, verification, letters, capabilities, accounts) of her company
-- inside her data months. Columns: time, role, action AND the acting user id — Karin's explicit exception to the
-- "no ids in outputs" rule, in this output only. Never the scope / subject of a row.
CREATE OR REPLACE FUNCTION rpc_auditor_change_log()
RETURNS TABLE (changed_at timestamptz, actor_role text, action text, actor_user_id uuid)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  a auditor_access := fn_auditor_current();
BEGIN
  PERFORM fn_j_audit('auditor_change_log_view', a.company_id, '{}'::jsonb);
  RETURN QUERY
  SELECT l.created_at, COALESCE(u.app_role, 'system'), l.action, l.viewer_id
    FROM access_audit_log l LEFT JOIN users u ON u.user_id = l.viewer_id
   WHERE l.company_id = a.company_id
     AND l.action ~ '(_put|_set|_sync|grant|revoke|provision|upload|cancel|decide)'
     AND fn_agent_local_ts(a.company_id, l.created_at)::date >= a.data_month_from
     AND fn_agent_local_ts(a.company_id, l.created_at)::date < (a.data_month_to + interval '1 month')::date
   ORDER BY l.created_at;
END;
$$;

-- The auditor reads the computed verification levels of a month inside her data range (read only).
CREATE OR REPLACE FUNCTION rpc_auditor_verification_levels(p_month date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  a auditor_access := fn_auditor_current();
BEGIN
  IF p_month IS NULL OR date_trunc('month', p_month)::date NOT BETWEEN a.data_month_from AND a.data_month_to THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  PERFORM fn_j_audit('auditor_levels_view', a.company_id, jsonb_build_object('month', p_month));
  RETURN fn_board_verification_levels(a.company_id, date_trunc('month', p_month)::date);
END;
$$;

-- ---------- J-214 ----------

-- The newest letter (cancelled or not) covering a metric month; NULL when none.
CREATE OR REPLACE FUNCTION fn_j214_letter(p_company uuid, p_metric text, p_month date, p_valid_only boolean)
RETURNS auditor_letter
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT l.* FROM auditor_letter l
   WHERE l.company_id = p_company AND l.metric_key = p_metric
     AND date_trunc('month', p_month)::date BETWEEN l.period_from AND l.period_to
     AND (NOT p_valid_only OR NOT EXISTS (SELECT 1 FROM auditor_letter_cancel c WHERE c.letter_id = l.letter_id))
   ORDER BY l.uploaded_at DESC LIMIT 1
$$;

-- Level from the letters (called by fn_verification_level AFTER its base checks): a valid letter → reasonable 4 /
-- limited 3; only cancelled letters for the month → 2 (Karin: back to 2); no letter → NULL (controls decide 2 / 1).
CREATE OR REPLACE FUNCTION fn_j214_letter_level(p_company uuid, p_metric text, p_month date)
RETURNS int
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  l auditor_letter := fn_j214_letter(p_company, p_metric, p_month, true);
BEGIN
  IF l.letter_id IS NOT NULL THEN
    RETURN CASE l.assurance WHEN 'reasonable' THEN 4 ELSE 3 END;
  END IF;
  IF (fn_j214_letter(p_company, p_metric, p_month, false)).letter_id IS NOT NULL THEN
    RETURN 2;
  END IF;
  RETURN NULL;
END;
$$;

-- Letter facts added to the level JSON: status 'בתוקף' / 'בוטל', the same-person label, and the board note after a
-- cancellation. No person id.
CREATE OR REPLACE FUNCTION fn_j214_letter_json(p_company uuid, p_metric text, p_month date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  l auditor_letter := fn_j214_letter(p_company, p_metric, p_month, true);
  c auditor_letter := fn_j214_letter(p_company, p_metric, p_month, false);
  e metric_verification_evidence := fn_verification_evidence(p_company, p_metric, p_month);
BEGIN
  IF l.letter_id IS NOT NULL THEN
    RETURN jsonb_build_object('letter_status', 'בתוקף', 'letter_assurance', l.assurance)
           || CASE WHEN e.entered_by IS NOT NULL AND e.entered_by = l.uploaded_by
                   THEN jsonb_build_object('same_person_label_he', 'הוזן ואושר על ידי אותו אדם') ELSE '{}'::jsonb END;
  END IF;
  IF c.letter_id IS NOT NULL THEN
    RETURN jsonb_build_object('letter_status', 'בוטל',
                              'board_note_he', 'מכתב המבקר לתקופה זו סומן "בוטל"; רמת האימות חזרה ל-2');
  END IF;
  RETURN '{}'::jsonb;
END;
$$;

-- vp_hr uploads an external auditor letter for one metric and a month range of her company. The file is already in
-- storage (immutable object); we keep its path + sha256 + uploader + time (WORM).
CREATE OR REPLACE FUNCTION rpc_upload_auditor_letter(p_company_id uuid, p_metric_key text, p_period_from date,
    p_period_to date, p_assurance text, p_storage_path text, p_sha256 text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_id uuid;
BEGIN
  PERFORM fn_assert_vp_hr(p_company_id);
  IF p_metric_key IS NULL OR NOT (p_metric_key = ANY (fn_board_metric_keys())) OR p_period_from IS NULL
     OR p_period_to IS NULL OR p_assurance NOT IN ('limited', 'reasonable')
     OR NULLIF(btrim(p_storage_path), '') IS NULL OR lower(COALESCE(p_sha256, '')) !~ '^[0-9a-f]{64}$'
     OR date_trunc('month', p_period_from) > date_trunc('month', p_period_to) THEN
    PERFORM fn_raise_bad_request('invalid_auditor_letter');
  END IF;
  INSERT INTO auditor_letter (company_id, metric_key, period_from, period_to, assurance, storage_path, sha256, uploaded_by)
  VALUES (p_company_id, p_metric_key, date_trunc('month', p_period_from)::date, date_trunc('month', p_period_to)::date,
          p_assurance, btrim(p_storage_path), lower(p_sha256), auth.uid())
  RETURNING letter_id INTO v_id;
  PERFORM fn_audit_view('auditor_letter_upload', jsonb_build_object('letter_id', v_id, 'metric_key', p_metric_key,
                        'assurance', p_assurance, 'sha256', lower(p_sha256)));
  RETURN jsonb_build_object('letter_id', v_id, 'status', 'בתוקף');
END;
$$;

-- vp_hr cancels a letter of her company: a 'בוטל' mark (WORM), never a delete.
CREATE OR REPLACE FUNCTION rpc_cancel_auditor_letter(p_letter_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  PERFORM fn_assert_vp_hr((SELECT l.company_id FROM auditor_letter l WHERE l.letter_id = p_letter_id));
  INSERT INTO auditor_letter_cancel (letter_id, cancelled_by) VALUES (p_letter_id, auth.uid())
  ON CONFLICT (letter_id) DO NOTHING;
  PERFORM fn_audit_view('auditor_letter_cancel', jsonb_build_object('letter_id', p_letter_id));
  RETURN jsonb_build_object('letter_id', p_letter_id, 'status', 'בוטל');
END;
$$;

REVOKE ALL ON FUNCTION rpc_provision_external_auditor(uuid, varchar, varchar, text, timestamptz, timestamptz, date, date),
  rpc_set_auditor_access(uuid, timestamptz, timestamptz, date, date), rpc_auditor_change_log(),
  rpc_auditor_verification_levels(date), rpc_upload_auditor_letter(uuid, text, date, date, text, text, text),
  rpc_cancel_auditor_letter(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_provision_external_auditor(uuid, varchar, varchar, text, timestamptz, timestamptz, date, date),
  rpc_set_auditor_access(uuid, timestamptz, timestamptz, date, date), rpc_auditor_change_log(),
  rpc_auditor_verification_levels(date), rpc_upload_auditor_letter(uuid, text, date, date, text, text, text),
  rpc_cancel_auditor_letter(uuid) TO authenticated;
REVOKE ALL ON FUNCTION fn_auditor_current(), fn_j214_letter(uuid, text, date, boolean), fn_j214_letter_level(uuid, text, date),
  fn_j214_letter_json(uuid, text, date) FROM PUBLIC, anon, authenticated;
