-- =============================================================================
-- CHR-ETRS v1.7.0 · modules/30_j_research.sql — research access J-178 … J-192, J-215, J-216 (Karin 16.11)
--   * researcher accounts + DPAs come ONLY from db/config/research_dpa.json (a reviewed PR; file starts EMPTY);
--   * one DPA per (company, researcher) pair (J-187), valid to its signed end date, max 2 years (J-189);
--   * vp_hr of the company approves a request; the approval runs to the end of the research period, max 1 year (J-188);
--   * an export = ONE company (J-187), company level only (J-182), PCQ-12 / IHS / TPS-12 + response rate + score
--     range only (J-183); company code = HMAC with a server secret, sector + size band (J-184);
--   * completed calendar quarters only, 14 days after the end, company calendar (J-185); research scope = 20:
--     a quarter where ANY metric has fewer than 20 → the whole quarter is hidden with the standard text;
--   * difference rule vs every earlier export of that company by ANY researcher (J-180 / J-186);
--   * the export log is kept while the company is active; 24 months after companies.service_ended_at it is copied to
--     a WORM archive, never deleted (J-190 — DRAFT, pending the privacy lawyer);
--   * method comments: text only, 5–2000 characters, kept permanently (J-191 / J-192 / J-216).
-- No user_id / person_id / pseudonym / company name in any output.
-- =============================================================================

-- ---------- tables ----------
CREATE TABLE IF NOT EXISTS research_dpa (
    company_id      uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    researcher_id   uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    dpa_signed_on   date NOT NULL,
    dpa_valid_until date NOT NULL,
    synced_at       timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (company_id, researcher_id),
    -- J-189: valid to the date signed in it, at most 2 years
    CONSTRAINT chk_research_dpa_max_2y CHECK (dpa_valid_until >= dpa_signed_on
                                              AND dpa_valid_until <= (dpa_signed_on + interval '2 years')::date)
);

CREATE TABLE IF NOT EXISTS researcher_ack (
    ack_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    researcher_id uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    ack_version   text NOT NULL,
    acked_at      timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE IF NOT EXISTS research_request (
    request_id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id           uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    researcher_id        uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    dataset              text NOT NULL DEFAULT 'J-183' CHECK (dataset = 'J-183'),
    quarter_from         date NOT NULL,
    quarter_to           date NOT NULL,
    research_period_end  date NOT NULL,
    deletion_commitment  boolean NOT NULL CHECK (deletion_commitment),
    created_at           timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT chk_research_request_quarters CHECK (quarter_from <= quarter_to)
);

CREATE TABLE IF NOT EXISTS research_decision (
    decision_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id           uuid NOT NULL REFERENCES research_request(request_id) ON DELETE CASCADE,
    decision             text NOT NULL CHECK (decision IN ('approved', 'rejected', 'revoked')),
    decided_by           uuid REFERENCES users(user_id) ON DELETE SET NULL,
    decided_at           timestamptz NOT NULL DEFAULT clock_timestamp(),
    approval_valid_until date
);

CREATE TABLE IF NOT EXISTS research_export_log (
    export_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id    uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    researcher_id uuid REFERENCES users(user_id) ON DELETE SET NULL,
    request_id    uuid REFERENCES research_request(request_id) ON DELETE SET NULL,
    cells         jsonb NOT NULL,          -- [{quarter, metric, n}] of the PUBLISHED cells only
    created_at    timestamptz NOT NULL DEFAULT clock_timestamp()
);

-- DRAFT J-190 (pending the privacy lawyer): the archive copy. No row is ever deleted from the log or the archive.
CREATE TABLE IF NOT EXISTS research_export_archive (
    export_id     uuid PRIMARY KEY,
    company_id    uuid NOT NULL,
    cells         jsonb NOT NULL,
    created_at    timestamptz NOT NULL,
    archived_at   timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE IF NOT EXISTS method_comment (
    comment_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    method_version text NOT NULL,
    body_he        text NOT NULL CHECK (length(btrim(body_he)) BETWEEN 5 AND 2000),   -- Karin 16.11: 5–2000
    created_at     timestamptz NOT NULL DEFAULT clock_timestamp()
);

-- WORM: these rows are never updated or deleted (403 ledger_immutable).
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['researcher_ack', 'research_request', 'research_decision', 'research_export_log',
                           'research_export_archive', 'method_comment'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_%s_worm ON %I', t, t);
    EXECUTE format('CREATE TRIGGER trg_%s_worm BEFORE UPDATE OR DELETE ON %I FOR EACH ROW '
                   'EXECUTE FUNCTION fn_worm_immutable(''ledger_immutable'')', t, t);
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format('REVOKE ALL ON TABLE %I FROM PUBLIC, anon, authenticated', t);
  END LOOP;
  ALTER TABLE research_dpa ENABLE ROW LEVEL SECURITY;
  ALTER TABLE research_dpa FORCE ROW LEVEL SECURITY;
  REVOKE ALL ON TABLE research_dpa FROM PUBLIC, anon, authenticated;
END $$;

-- ---------- config sync (system only; db/config/research_dpa.json) ----------

-- Create / refresh one researcher account from config (company_id NULL, no employee profile). Returns her user id
-- (internal only).
CREATE OR REPLACE FUNCTION fn_research_upsert_researcher(p_email text, p_full_name text, p_timezone text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_id uuid := (SELECT u.user_id FROM users u WHERE lower(u.email) = lower(btrim(p_email)));
BEGIN
  IF v_id IS NOT NULL AND (SELECT u.app_role FROM users u WHERE u.user_id = v_id) <> 'researcher' THEN
    PERFORM fn_raise_bad_request('researcher_email_in_use');      -- never turn an employee into a researcher
  END IF;
  IF v_id IS NULL THEN
    v_id := gen_random_uuid();
    INSERT INTO auth.users (id) VALUES (v_id);
    INSERT INTO users (user_id, company_id, email, full_name, app_role, org_role_code, timezone, has_employee_profile)
    VALUES (v_id, NULL, btrim(p_email), btrim(p_full_name), 'researcher', 'employee', p_timezone, false);
  END IF;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION fn_research_upsert_researcher(text, text, text) FROM PUBLIC, anon, authenticated;

-- Load db/config/research_dpa.json: {"researchers": [{email, full_name, timezone}],
-- "dpas": [{company_id, researcher_email, dpa_signed_on, dpa_valid_until}]}. System only. A DPA that left the file is
-- NOT deleted (removal = reviewed PR + manual service step); returns the number of DPA rows written.
CREATE OR REPLACE FUNCTION fn_sync_research_config(p_config jsonb)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  r   jsonb;
  v_n int := 0;
BEGIN
  PERFORM fn_j_assert_system();
  FOR r IN SELECT jsonb_array_elements(COALESCE(p_config->'researchers', '[]'::jsonb)) LOOP
    PERFORM fn_research_upsert_researcher(r->>'email', r->>'full_name', r->>'timezone');
  END LOOP;
  FOR r IN SELECT jsonb_array_elements(COALESCE(p_config->'dpas', '[]'::jsonb)) LOOP
    INSERT INTO research_dpa (company_id, researcher_id, dpa_signed_on, dpa_valid_until)
    VALUES ((r->>'company_id')::uuid,
            (SELECT u.user_id FROM users u WHERE lower(u.email) = lower(btrim(r->>'researcher_email'))
                AND u.app_role = 'researcher'),
            (r->>'dpa_signed_on')::date, (r->>'dpa_valid_until')::date)
    ON CONFLICT (company_id, researcher_id) DO UPDATE
      SET dpa_signed_on = EXCLUDED.dpa_signed_on, dpa_valid_until = EXCLUDED.dpa_valid_until,
          synced_at = clock_timestamp();
    PERFORM fn_j_audit('research_dpa_sync', (r->>'company_id')::uuid, '{}'::jsonb);
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION fn_sync_research_config(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION fn_sync_research_config(jsonb) TO service_role;

-- ---------- caller checks ----------

-- Raise 403 access_denied unless the caller is an active researcher account.
CREATE OR REPLACE FUNCTION fn_research_assert_researcher()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (SELECT 1 FROM users u WHERE u.user_id = auth.uid()
                                          AND u.app_role = 'researcher' AND u.employment_ended_at IS NULL) THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
END;
$$;

-- J-215: 403 onboarding_not_acknowledged until the researcher logged her acknowledgement.
CREATE OR REPLACE FUNCTION fn_research_assert_ack()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM researcher_ack a WHERE a.researcher_id = auth.uid()) THEN
    PERFORM fn_raise_business('onboarding_not_acknowledged');
  END IF;
END;
$$;

-- J-187 / J-189: the caller holds a DPA for this company that is valid today (company calendar).
CREATE OR REPLACE FUNCTION fn_research_dpa_valid(p_company uuid, p_now timestamptz DEFAULT NULL)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (SELECT 1 FROM research_dpa d
                  WHERE d.company_id = p_company AND d.researcher_id = auth.uid()
                    AND fn_j_company_today(p_company, p_now) BETWEEN d.dpa_signed_on AND d.dpa_valid_until)
$$;

-- J-184: the company code shown to researchers = HMAC(company_id) with the server secret 'research_company'.
CREATE OR REPLACE FUNCTION fn_research_company_code(p_company uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$ SELECT fn_j_hmac('research_company', p_company::text) $$;

-- Company of a code among the caller's DPAs (NULL when none matches).
CREATE OR REPLACE FUNCTION fn_research_company_of_code(p_code text)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT d.company_id FROM research_dpa d
   WHERE d.researcher_id = auth.uid() AND fn_research_company_code(d.company_id) = p_code LIMIT 1
$$;

-- Active employees of a company today (the size basis of J-184).
CREATE OR REPLACE FUNCTION fn_research_headcount(p_company uuid)
RETURNS int
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT count(*)::int FROM users u
   WHERE u.company_id = p_company AND u.has_employee_profile AND u.employment_ended_at IS NULL
$$;

-- J-184 size band (Karin 16.11): 20–99, 100–499, 500–1999, 2000+; below 20 → NULL (no band shown).
CREATE OR REPLACE FUNCTION fn_research_size_band(p_n int)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE WHEN p_n >= 2000 THEN '2000+' WHEN p_n >= 500 THEN '500–1999'
              WHEN p_n >= 100 THEN '100–499' WHEN p_n >= 20 THEN '20–99' END
$$;

-- J-184 descriptor: sector + size band; when fewer than 3 companies on the platform share sector + band → sector only.
CREATE OR REPLACE FUNCTION fn_research_descriptor(p_company uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  WITH me AS (SELECT c.industry, fn_research_size_band(fn_research_headcount(c.company_id)) AS band
                FROM companies c WHERE c.company_id = p_company),
       peers AS (SELECT count(*) AS n FROM companies c, me
                  WHERE c.industry IS NOT DISTINCT FROM me.industry
                    AND fn_research_size_band(fn_research_headcount(c.company_id)) IS NOT DISTINCT FROM me.band)
  SELECT jsonb_build_object('sector_he', COALESCE(me.industry, fn_j_not_defined_he()),
                            'size_band', CASE WHEN me.band IS NOT NULL AND peers.n >= 3 THEN me.band END)
    FROM me, peers
$$;

-- ---------- researcher RPCs ----------

-- J-215: the researcher logs her acknowledgement (WORM). The acknowledgement text itself: לא הוגדר (version only).
CREATE OR REPLACE FUNCTION rpc_researcher_acknowledge(p_version text DEFAULT 'J-215')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  PERFORM fn_research_assert_researcher();
  INSERT INTO researcher_ack (researcher_id, ack_version) VALUES (auth.uid(), COALESCE(NULLIF(btrim(p_version), ''), 'J-215'));
  PERFORM fn_j_audit('researcher_acknowledge', NULL, jsonb_build_object('version', p_version));
  RETURN jsonb_build_object('acknowledged', true);
END;
$$;

-- The companies the researcher may ask about (valid DPA): code + J-184 descriptor only.
CREATE OR REPLACE FUNCTION rpc_research_my_companies()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  PERFORM fn_research_assert_researcher();
  PERFORM fn_research_assert_ack();
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('company_code', fn_research_company_code(d.company_id))
                                    || fn_research_descriptor(d.company_id) ORDER BY 1)
                     FROM research_dpa d
                    WHERE d.researcher_id = auth.uid() AND fn_research_dpa_valid(d.company_id)), '[]'::jsonb);
END;
$$;

-- The researcher asks for one company's dataset over a quarter range. Needs the acknowledgement and a valid DPA;
-- the deletion commitment is mandatory (400). Returns the request id (no person id).
CREATE OR REPLACE FUNCTION rpc_research_request(p_company_code text, p_quarter_from text, p_quarter_to text,
                                                p_research_period_end date, p_deletion_commitment boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_comp uuid;
  v_id   uuid;
BEGIN
  PERFORM fn_research_assert_researcher();
  PERFORM fn_research_assert_ack();
  v_comp := fn_research_company_of_code(p_company_code);
  IF v_comp IS NULL OR NOT fn_research_dpa_valid(v_comp) THEN
    PERFORM fn_raise_business('dpa_not_valid');
  END IF;
  IF p_deletion_commitment IS NOT TRUE OR p_research_period_end IS NULL
     OR fn_j_quarter_start(p_quarter_from) IS NULL OR fn_j_quarter_start(p_quarter_to) IS NULL
     OR fn_j_quarter_start(p_quarter_from) > fn_j_quarter_start(p_quarter_to) THEN
    PERFORM fn_raise_bad_request('invalid_research_request');
  END IF;
  INSERT INTO research_request (company_id, researcher_id, quarter_from, quarter_to, research_period_end,
                                deletion_commitment)
  VALUES (v_comp, auth.uid(), fn_j_quarter_start(p_quarter_from), fn_j_quarter_start(p_quarter_to),
          p_research_period_end, true)
  RETURNING request_id INTO v_id;
  PERFORM fn_j_audit('research_request', v_comp, jsonb_build_object('request_id', v_id));
  RETURN jsonb_build_object('request_id', v_id, 'status', 'pending');
END;
$$;

-- Latest decision of a request ('pending' when none).
CREATE OR REPLACE FUNCTION fn_research_status(p_request uuid)
RETURNS research_decision
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT d.* FROM research_decision d WHERE d.request_id = p_request ORDER BY d.decided_at DESC, d.decision_id LIMIT 1
$$;

-- ---------- vp_hr RPCs (J-188) ----------

-- vp_hr of the company lists its research requests (researcher shown by name to vp_hr only; no ids).
CREATE OR REPLACE FUNCTION rpc_research_list_requests()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_comp uuid := fn_my_company();
BEGIN
  PERFORM fn_assert_vp_hr(v_comp);
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object(
            'request_id', r.request_id, 'researcher_name', u.full_name, 'dataset', r.dataset,
            'quarter_from', fn_j_quarter_label(r.quarter_from), 'quarter_to', fn_j_quarter_label(r.quarter_to),
            'research_period_end', r.research_period_end,
            'status', COALESCE((fn_research_status(r.request_id)).decision, 'pending'),
            'approval_valid_until', (fn_research_status(r.request_id)).approval_valid_until) ORDER BY r.created_at)
     FROM research_request r JOIN users u ON u.user_id = r.researcher_id WHERE r.company_id = v_comp), '[]'::jsonb);
END;
$$;

-- vp_hr approves / rejects a request of her company. Approval valid to the end of the research period, at most
-- 1 year from today (J-188). Audited.
CREATE OR REPLACE FUNCTION rpc_research_decide(p_request_id uuid, p_approve boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  r       research_request;
  v_until date;
BEGIN
  SELECT * INTO r FROM research_request WHERE request_id = p_request_id;
  PERFORM fn_assert_vp_hr(r.company_id);
  IF (fn_research_status(p_request_id)).decision IS NOT NULL OR p_approve IS NULL THEN
    PERFORM fn_raise_bad_request('research_request_not_pending');
  END IF;
  v_until := CASE WHEN p_approve THEN least(r.research_period_end,
                                            (fn_j_company_today(r.company_id) + interval '1 year')::date) END;
  INSERT INTO research_decision (request_id, decision, decided_by, approval_valid_until)
  VALUES (p_request_id, CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END, auth.uid(), v_until);
  PERFORM fn_audit_view('research_decide', jsonb_build_object('request_id', p_request_id, 'approved', p_approve,
                                                              'approval_valid_until', v_until));
  RETURN jsonb_build_object('request_id', p_request_id, 'status', CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
                            'approval_valid_until', v_until);
END;
$$;

-- vp_hr revokes an approval of her company; the next export is refused.
CREATE OR REPLACE FUNCTION rpc_research_revoke(p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_comp uuid := (SELECT r.company_id FROM research_request r WHERE r.request_id = p_request_id);
BEGIN
  PERFORM fn_assert_vp_hr(v_comp);
  INSERT INTO research_decision (request_id, decision, decided_by) VALUES (p_request_id, 'revoked', auth.uid());
  PERFORM fn_audit_view('research_revoke', jsonb_build_object('request_id', p_request_id));
  RETURN jsonb_build_object('request_id', p_request_id, 'status', 'revoked');
END;
$$;

-- ---------- the export (J-180 … J-186) ----------

-- One metric of a company quarter: average score, interquartile score range, and N = distinct employees (J-221).
CREATE OR REPLACE FUNCTION fn_research_metric(p_company uuid, p_code text, p_q date)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT jsonb_build_object('n', count(DISTINCT q.user_id), 'average', round(avg(q.score), 1),
                            'score_range', jsonb_build_object(
                               'p25', round(percentile_cont(0.25) WITHIN GROUP (ORDER BY q.score)::numeric, 0),
                               'p75', round(percentile_cont(0.75) WITHIN GROUP (ORDER BY q.score)::numeric, 0)))
    FROM questionnaire_submission q JOIN users u ON u.user_id = q.user_id
   WHERE u.company_id = p_company AND q.questionnaire_code = p_code AND q.score IS NOT NULL
     AND q.local_date >= p_q AND q.local_date < (p_q + interval '3 months')::date
$$;

-- Employees of the company active at the end of a quarter (response-rate denominator, J-222).
CREATE OR REPLACE FUNCTION fn_research_members_at(p_company uuid, p_q date)
RETURNS int
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT count(*)::int FROM users u
   WHERE u.company_id = p_company AND u.has_employee_profile
     AND (u.hire_date IS NULL OR u.hire_date < (p_q + interval '3 months')::date)
     AND (u.employment_ended_at IS NULL
          OR fn_agent_local_ts(p_company, u.employment_ended_at)::date >= (p_q + interval '3 months')::date)
$$;

-- J-180 / J-186 difference rule: true when ANY earlier export of this company (any researcher) published the same
-- quarter + metric with an N that differs by 1 … (research threshold − 1).
CREATE OR REPLACE FUNCTION fn_research_difference_hit(p_company uuid, p_quarter text, p_metric text, p_n int)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM research_export_log l, jsonb_array_elements(l.cells) c
     WHERE l.company_id = p_company AND c->>'quarter' = p_quarter AND c->>'metric' = p_metric
       AND abs((c->>'n')::int - p_n) BETWEEN 1 AND fn_privacy_min_n('research') - 1)
$$;

-- One quarter of the export: shown with the three metrics + response rate, or hidden as a whole (J-185) with the
-- standard text when any metric is under the research threshold or the difference rule hits.
CREATE OR REPLACE FUNCTION fn_research_quarter(p_company uuid, p_q date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_label text := fn_j_quarter_label(p_q);
  v_min   int := fn_privacy_min_n('research');
  m_pcq   jsonb := fn_research_metric(p_company, 'PCQ-12', p_q);
  m_ihs   jsonb := fn_research_metric(p_company, 'IHS', p_q);
  m_tps   jsonb := fn_research_metric(p_company, 'TPS-12', p_q);
  v_mem   int := fn_research_members_at(p_company, p_q);
BEGIN
  IF least((m_pcq->>'n')::int, (m_ihs->>'n')::int, (m_tps->>'n')::int, v_mem) < v_min
     OR fn_research_difference_hit(p_company, v_label, 'PCQ-12', (m_pcq->>'n')::int)
     OR fn_research_difference_hit(p_company, v_label, 'IHS', (m_ihs->>'n')::int)
     OR fn_research_difference_hit(p_company, v_label, 'TPS-12', (m_tps->>'n')::int) THEN
    RETURN jsonb_build_object('quarter', v_label, 'shown', false, 'display_he', fn_insufficient_data_period_he());
  END IF;
  RETURN jsonb_build_object('quarter', v_label, 'shown', true,
           'pcq12', m_pcq, 'ihs', m_ihs, 'tps12', m_tps,
           'response_rate_pct', round(100.0 * least((m_pcq->>'n')::int, v_mem) / v_mem, 0));
END;
$$;

-- The researcher exports one approved request (one company). Refused unless: acknowledged, DPA valid today,
-- approval valid today and not revoked. Only completed quarters 14 days after their end are included. Published
-- cells are logged (WORM) for the difference rule. Output: company code + descriptor + quarters, nothing else.
CREATE OR REPLACE FUNCTION rpc_research_export(p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  r       research_request;
  d       research_decision;
  v_q     date;
  v_now   timestamptz := clock_timestamp();
  v_out   jsonb := '[]'::jsonb;
  v_cells jsonb := '[]'::jsonb;
  v_one   jsonb;
BEGIN
  PERFORM fn_research_assert_researcher();
  PERFORM fn_research_assert_ack();
  SELECT * INTO r FROM research_request WHERE request_id = p_request_id AND researcher_id = auth.uid();
  IF r.request_id IS NULL OR NOT fn_research_dpa_valid(r.company_id, v_now) THEN
    PERFORM fn_raise_business('dpa_not_valid');
  END IF;
  d := fn_research_status(p_request_id);
  IF d.decision IS DISTINCT FROM 'approved' OR fn_j_company_today(r.company_id, v_now) > d.approval_valid_until THEN
    PERFORM fn_raise_business('research_not_approved');
  END IF;
  v_q := r.quarter_from;
  WHILE v_q <= r.quarter_to LOOP
    IF fn_j_quarter_ready(r.company_id, v_q, v_now) THEN
      v_one := fn_research_quarter(r.company_id, v_q);
      v_out := v_out || jsonb_build_array(v_one);
      IF (v_one->>'shown')::boolean THEN
        v_cells := v_cells || jsonb_build_array(
          jsonb_build_object('quarter', v_one->>'quarter', 'metric', 'PCQ-12', 'n', (v_one->'pcq12'->>'n')::int),
          jsonb_build_object('quarter', v_one->>'quarter', 'metric', 'IHS', 'n', (v_one->'ihs'->>'n')::int),
          jsonb_build_object('quarter', v_one->>'quarter', 'metric', 'TPS-12', 'n', (v_one->'tps12'->>'n')::int));
      END IF;
    END IF;
    v_q := (v_q + interval '3 months')::date;
  END LOOP;
  INSERT INTO research_export_log (company_id, researcher_id, request_id, cells)
  VALUES (r.company_id, auth.uid(), r.request_id, v_cells);
  PERFORM fn_j_audit('research_export', r.company_id, jsonb_build_object('request_id', r.request_id));
  RETURN jsonb_build_object('company_code', fn_research_company_code(r.company_id), 'dataset', r.dataset)
         || fn_research_descriptor(r.company_id) || jsonb_build_object('quarters', v_out);
END;
$$;

-- DRAFT J-190 (pending the privacy lawyer): copy the export log of companies whose service ended ≥ 24 months ago into
-- the WORM archive. Nothing is deleted. System only. Returns the number of rows archived now.
CREATE OR REPLACE FUNCTION fn_archive_research_exports(p_now timestamptz DEFAULT NULL)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_n int;
BEGIN
  PERFORM fn_j_assert_system();
  INSERT INTO research_export_archive (export_id, company_id, cells, created_at)
  SELECT l.export_id, l.company_id, l.cells, l.created_at
    FROM research_export_log l JOIN companies c ON c.company_id = l.company_id
   WHERE c.service_ended_at IS NOT NULL
     AND c.service_ended_at + interval '24 months' <= COALESCE(p_now, clock_timestamp())
  ON CONFLICT (export_id) DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION fn_archive_research_exports(timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION fn_archive_research_exports(timestamptz) TO service_role;

-- ---------- J-191 / J-192 / J-216: method comments ----------

-- J-216 notice returned with every comment: text only, no attachments. The wording itself: לא הוגדר.
CREATE OR REPLACE FUNCTION fn_method_comment_notice()
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$ SELECT jsonb_build_object('warning_code', 'text_only_no_attachments', 'warning_he', 'לא הוגדר') $$;

-- A researcher sends a comment on the METHOD (5–2000 characters, text only, no attachment parameter exists).
-- Stored permanently (WORM, no author id) and queued to every method-team address from db/config (J-191).
CREATE OR REPLACE FUNCTION rpc_method_comment_send(p_body text, p_method_version text DEFAULT 'v1.7.0')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_id uuid;
  v_n  int := 0;
  a    text;
BEGIN
  PERFORM fn_research_assert_researcher();
  PERFORM fn_research_assert_ack();
  IF NOT fn_j_text_ok(p_body, 5, 2000) THEN
    PERFORM fn_raise_bad_request('invalid_comment_length');
  END IF;
  INSERT INTO method_comment (method_version, body_he) VALUES (COALESCE(p_method_version, 'v1.7.0'), btrim(p_body))
  RETURNING comment_id INTO v_id;
  FOR a IN SELECT r.address FROM j_config_recipient r WHERE r.kind = 'method_team' ORDER BY r.address LOOP
    PERFORM fn_j_outbox_put(NULL, 'method_comment', a, 'הערה על השיטה',
                            jsonb_build_object('body_he', btrim(p_body), 'method_version', p_method_version),
                            'method_comment:' || v_id || ':' || a);
    v_n := v_n + 1;
  END LOOP;
  RETURN jsonb_build_object('stored', true, 'queued', v_n,
                            'delivery', CASE WHEN v_n = 0 THEN 'recipients_not_configured' ELSE 'queued' END)
         || fn_method_comment_notice();
END;
$$;

REVOKE ALL ON FUNCTION rpc_researcher_acknowledge(text), rpc_research_my_companies(),
  rpc_research_request(text, text, text, date, boolean), rpc_research_list_requests(), rpc_research_decide(uuid, boolean),
  rpc_research_revoke(uuid), rpc_research_export(uuid), rpc_method_comment_send(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_researcher_acknowledge(text), rpc_research_my_companies(),
  rpc_research_request(text, text, text, date, boolean), rpc_research_list_requests(), rpc_research_decide(uuid, boolean),
  rpc_research_revoke(uuid), rpc_research_export(uuid), rpc_method_comment_send(text, text) TO authenticated;
REVOKE ALL ON FUNCTION fn_research_assert_researcher(), fn_research_assert_ack(), fn_research_dpa_valid(uuid, timestamptz),
  fn_research_company_code(uuid), fn_research_company_of_code(text), fn_research_headcount(uuid),
  fn_research_descriptor(uuid), fn_research_status(uuid), fn_research_metric(uuid, text, date),
  fn_research_members_at(uuid, date), fn_research_difference_hit(uuid, text, text, int), fn_research_quarter(uuid, date)
  FROM PUBLIC, anon, authenticated;
