-- =============================================================================
-- CHR-ETRS v1.7.0 · modules/20_j_capabilities.sql — extra capabilities of an employee (Karin 16.11)
-- IT (J-199), works council (J-201) and the safety officer (J-202) are NOT app roles: they stay employees
-- (app_role unchanged, employee interface intact) and vp_hr of their own company grants / revokes a capability.
-- fn_has_capability_in (rpc.sql) reads this table.
-- =============================================================================

CREATE TABLE IF NOT EXISTS user_capability (
    capability_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    company_id    uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    capability    text NOT NULL CHECK (capability IN ('it_admin', 'works_council', 'safety_officer')),
    granted_by    uuid REFERENCES users(user_id) ON DELETE SET NULL,
    granted_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
    revoked_by    uuid REFERENCES users(user_id) ON DELETE SET NULL,
    revoked_at    timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_user_capability_active
    ON user_capability (user_id, capability) WHERE revoked_at IS NULL;
ALTER TABLE user_capability ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_capability FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE user_capability FROM PUBLIC, anon, authenticated;

-- Only revoked_by / revoked_at may change, once (a grant is never rewritten or deleted).
CREATE OR REPLACE FUNCTION fn_user_capability_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'DELETE' AND current_setting('chr.cascade_delete', true) IS DISTINCT FROM 'on' THEN
    PERFORM fn_raise_business('ledger_immutable');
  END IF;
  IF TG_OP = 'UPDATE' AND (OLD.revoked_at IS NOT NULL
      OR (NEW.user_id, NEW.company_id, NEW.capability, NEW.granted_by, NEW.granted_at)
         IS DISTINCT FROM (OLD.user_id, OLD.company_id, OLD.capability, OLD.granted_by, OLD.granted_at)) THEN
    PERFORM fn_raise_business('ledger_immutable');
  END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;
DROP TRIGGER IF EXISTS trg_user_capability_guard ON user_capability;
CREATE TRIGGER trg_user_capability_guard BEFORE UPDATE ON user_capability
    FOR EACH ROW EXECUTE FUNCTION fn_user_capability_guard();

-- Target must be an active employee (with an employee profile) of the caller's company; else 400 invalid_user.
CREATE OR REPLACE FUNCTION fn_j_assert_company_employee(p_company uuid, p_user uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM users u WHERE u.user_id = p_user AND u.company_id = p_company
                    AND u.employment_ended_at IS NULL AND u.has_employee_profile) THEN
    PERFORM fn_raise_bad_request('invalid_user');
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION fn_j_assert_company_employee(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- vp_hr grants a capability to an employee of her own company (idempotent). Audited (who / when / what).
CREATE OR REPLACE FUNCTION rpc_grant_capability(p_user_id uuid, p_capability text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_comp uuid := fn_my_company();
BEGIN
  PERFORM fn_assert_vp_hr(v_comp);
  IF p_capability IS NULL OR p_capability NOT IN ('it_admin', 'works_council', 'safety_officer') THEN
    PERFORM fn_raise_bad_request('invalid_capability');
  END IF;
  PERFORM fn_j_assert_company_employee(v_comp, p_user_id);
  INSERT INTO user_capability (user_id, company_id, capability, granted_by)
  VALUES (p_user_id, v_comp, p_capability, auth.uid())
  ON CONFLICT (user_id, capability) WHERE revoked_at IS NULL DO NOTHING;
  PERFORM fn_audit_view('capability_grant', jsonb_build_object('capability', p_capability), p_user_id);
  RETURN jsonb_build_object('capability', p_capability, 'status', 'granted');
END;
$$;

-- vp_hr revokes a capability of an employee of her own company (the grant row is kept, marked revoked).
CREATE OR REPLACE FUNCTION rpc_revoke_capability(p_user_id uuid, p_capability text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_comp uuid := fn_my_company();
BEGIN
  PERFORM fn_assert_vp_hr(v_comp);
  UPDATE user_capability SET revoked_at = clock_timestamp(), revoked_by = auth.uid()
   WHERE user_id = p_user_id AND company_id = v_comp AND capability = p_capability AND revoked_at IS NULL;
  PERFORM fn_audit_view('capability_revoke', jsonb_build_object('capability', p_capability), p_user_id);
  RETURN jsonb_build_object('capability', p_capability, 'status', 'revoked');
END;
$$;

-- The caller's own active capabilities (an employee sees which extra screens she has). No ids.
CREATE OR REPLACE FUNCTION rpc_my_capabilities()
RETURNS text[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT COALESCE(array_agg(c.capability ORDER BY c.capability), '{}')
    FROM user_capability c JOIN users u ON u.user_id = c.user_id
   WHERE c.user_id = auth.uid() AND c.revoked_at IS NULL AND u.employment_ended_at IS NULL
$$;

REVOKE ALL ON FUNCTION rpc_grant_capability(uuid, text), rpc_revoke_capability(uuid, text), rpc_my_capabilities()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_grant_capability(uuid, text), rpc_revoke_capability(uuid, text), rpc_my_capabilities()
  TO authenticated;
