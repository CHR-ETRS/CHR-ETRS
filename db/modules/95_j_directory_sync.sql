-- =============================================================================
-- CHR-ETRS v1.7.0 · modules/95_j_directory_sync.sql — directory / entry-system sync contract J-195, J-199, J-202
-- DB contract only (the identity provider and protocol: לא הוגדר; the integration is a separate PR).
--   * shift assignment comes ONLY from this sync (no manual entry, no client grant); until a sync exists there is no
--     shift breakdown (J-202);
--   * the IT capability (J-199) sees the connection status only — no person data.
-- =============================================================================

CREATE TABLE IF NOT EXISTS directory_sync_run (
    run_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id   uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    status       text NOT NULL CHECK (status IN ('ok', 'failed')),
    finished_at  timestamptz NOT NULL DEFAULT clock_timestamp(),
    users_seen   int NOT NULL DEFAULT 0 CHECK (users_seen >= 0)
);
CREATE TABLE IF NOT EXISTS user_shift (
    user_id     uuid PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
    company_id  uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    shift_code  text NOT NULL CHECK (length(btrim(shift_code)) BETWEEN 1 AND 64),
    source      text NOT NULL DEFAULT 'directory_sync' CHECK (source = 'directory_sync'),
    synced_at   timestamptz NOT NULL DEFAULT clock_timestamp()
);
DROP TRIGGER IF EXISTS trg_directory_sync_run_worm ON directory_sync_run;
CREATE TRIGGER trg_directory_sync_run_worm BEFORE UPDATE OR DELETE ON directory_sync_run
    FOR EACH ROW EXECUTE FUNCTION fn_worm_immutable('ledger_immutable');
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['directory_sync_run', 'user_shift'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format('REVOKE ALL ON TABLE %I FROM PUBLIC, anon, authenticated', t);
  END LOOP;
END $$;

-- System (the sync job): apply one run for a company — {"status": "ok"|"failed", "shifts": [{"email", "shift_code"}]}.
-- Writes the shift of each matched employee of that company and the run row. Leavers go through rpc_offboard_employee.
CREATE OR REPLACE FUNCTION fn_directory_sync_apply(p_company uuid, p_run jsonb)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  s   jsonb;
  v_n int := 0;
BEGIN
  PERFORM fn_j_assert_system();
  IF COALESCE(p_run->>'status', '') = 'ok' THEN
    FOR s IN SELECT jsonb_array_elements(COALESCE(p_run->'shifts', '[]'::jsonb)) LOOP
      INSERT INTO user_shift (user_id, company_id, shift_code)
      SELECT u.user_id, p_company, btrim(s->>'shift_code') FROM users u
       WHERE u.company_id = p_company AND lower(u.email) = lower(btrim(s->>'email'))
      ON CONFLICT (user_id) DO UPDATE SET shift_code = EXCLUDED.shift_code, synced_at = clock_timestamp();
      v_n := v_n + 1;
    END LOOP;
  END IF;
  INSERT INTO directory_sync_run (company_id, status, users_seen)
  VALUES (p_company, CASE WHEN p_run->>'status' = 'ok' THEN 'ok' ELSE 'failed' END, v_n);
  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION fn_directory_sync_apply(uuid, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION fn_directory_sync_apply(uuid, jsonb) TO service_role;

-- J-199: the IT capability sees the connection status of her company only (last run time + status; no person data).
CREATE OR REPLACE FUNCTION rpc_it_connection_status()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_comp uuid := fn_my_company();
  r      directory_sync_run;
BEGIN
  IF NOT fn_has_capability_in(v_comp, 'it_admin') THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  SELECT * INTO r FROM directory_sync_run x WHERE x.company_id = v_comp ORDER BY x.finished_at DESC LIMIT 1;
  RETURN jsonb_build_object('connected', r.run_id IS NOT NULL, 'last_status', r.status, 'last_run_at', r.finished_at,
                            'provider', fn_j_not_defined_he());
END;
$$;

-- J-202: shift breakdown for the safety officer — none until the entry-system sync has delivered shifts; then the
-- PCQ-12 average per shift for shifts that pass the regular threshold (others hidden with the standard text).
CREATE OR REPLACE FUNCTION rpc_safety_shift_breakdown(p_month date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_comp uuid := fn_my_company();
  v_m    date;
BEGIN
  IF NOT fn_has_capability_in(v_comp, 'safety_officer') THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM user_shift s WHERE s.company_id = v_comp) THEN
    RETURN jsonb_build_object('available', false, 'reason', 'no_directory_sync');
  END IF;
  v_m := COALESCE(fn_month_of(p_month), fn_agent_month_start(v_comp, clock_timestamp()));
  PERFORM fn_audit_view('safety_shift_breakdown', jsonb_build_object('month', v_m));
  RETURN jsonb_build_object('available', true, 'month', v_m, 'shifts',
    (SELECT COALESCE(jsonb_agg(CASE WHEN g.reporters >= fn_privacy_min_n('regular')
                                    THEN jsonb_build_object('shift', x.shift_code, 'pcq12_average', g.avg_score)
                                    ELSE jsonb_build_object('shift', x.shift_code, 'display_he', fn_insufficient_data_period_he())
                               END ORDER BY x.shift_code), '[]'::jsonb)
       FROM (SELECT s.shift_code, array_agg(s.user_id) AS members FROM user_shift s WHERE s.company_id = v_comp
              GROUP BY s.shift_code) x
       CROSS JOIN LATERAL fn_j_group_pcq(x.members, v_m) g));
END;
$$;

REVOKE ALL ON FUNCTION rpc_it_connection_status(), rpc_safety_shift_breakdown(date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_it_connection_status(), rpc_safety_shift_breakdown(date) TO authenticated;
