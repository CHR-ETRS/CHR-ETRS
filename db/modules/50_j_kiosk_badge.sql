-- =============================================================================
-- CHR-ETRS v1.7.0 · modules/50_j_kiosk_badge.sql — shared kiosk + badge login J-200 / J-208 / J-219 (Karin 16.11)
--   * the badge number is stored only as an HMAC with the server secret 'badge' (never plain, never unsalted);
--   * the FIRST PIN needs a one-time activation code issued by vp_hr; a PIN reset also goes through vp_hr;
--   * 5 wrong attempts → locked until vp_hr releases it; after the 3rd wrong attempt "נשארו 2 ניסיונות",
--     after the 4th "נשאר ניסיון 1";
--   * a successful login returns a ONE-TIME login ticket (60 s, once — redeemed by rpc_kiosk_redeem_ticket in
--     55_j_kiosk_session.sql, J-242); the Edge Function itself is a separate PR. The kiosk RPCs are system-only (service
--     role, called by that Edge Function) — never anon.
--   * J-200 (3 minutes idle + a 30-second warning) is enforced client-side; the DB only holds the contract.
-- =============================================================================

CREATE TABLE IF NOT EXISTS kiosk_badge (
    company_id           uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    badge_hmac           text NOT NULL,
    user_id              uuid NOT NULL UNIQUE REFERENCES users(user_id) ON DELETE CASCADE,
    pin_hash             text,                      -- crypt() / bcrypt; NULL until the first PIN
    activation_code_hash text,                      -- one-time; NULL once used
    failed_attempts      int NOT NULL DEFAULT 0 CHECK (failed_attempts BETWEEN 0 AND 5),
    locked_at            timestamptz,
    updated_at           timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (company_id, badge_hmac)
);

CREATE TABLE IF NOT EXISTS kiosk_badge_event (
    event_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id  uuid NOT NULL,
    badge_hmac  text NOT NULL,
    event_type  text NOT NULL CHECK (event_type IN ('activation_issued', 'pin_set', 'login_ok', 'login_failed',
                                                    'locked', 'released')),
    created_at  timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE IF NOT EXISTS kiosk_login_ticket (
    ticket_hash text PRIMARY KEY,                   -- sha256 of the one-time ticket; the ticket itself is never stored
    user_id     uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    issued_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
    used_at     timestamptz
);

DROP TRIGGER IF EXISTS trg_kiosk_badge_event_worm ON kiosk_badge_event;
CREATE TRIGGER trg_kiosk_badge_event_worm BEFORE UPDATE OR DELETE ON kiosk_badge_event
    FOR EACH ROW EXECUTE FUNCTION fn_worm_immutable('ledger_immutable');
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['kiosk_badge', 'kiosk_badge_event', 'kiosk_login_ticket'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format('REVOKE ALL ON TABLE %I FROM PUBLIC, anon, authenticated', t);
  END LOOP;
END $$;

-- J-200 / J-219 contract (Karin's values only): idle 180 s, warning 30 s before, 5 attempts.
CREATE OR REPLACE FUNCTION rpc_kiosk_contract()
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$ SELECT jsonb_build_object('idle_logout_seconds', 180, 'warning_seconds_before', 30, 'max_pin_attempts', 5,
                                'enforced', 'client') $$;

-- HMAC of a badge number (server secret 'badge').
CREATE OR REPLACE FUNCTION fn_kiosk_badge_hmac(p_badge text)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$ SELECT fn_j_hmac('badge', btrim(p_badge)) $$;

-- Hebrew message after a wrong PIN, by the number of wrong attempts so far (Karin: 3 → 2 left, 4 → 1 left).
CREATE OR REPLACE FUNCTION fn_kiosk_attempts_he(p_failed int)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$ SELECT CASE p_failed WHEN 3 THEN 'נשארו 2 ניסיונות' WHEN 4 THEN 'נשאר ניסיון 1' END $$;

-- Log one badge event (WORM).
CREATE OR REPLACE FUNCTION fn_kiosk_event(p_company uuid, p_hmac text, p_type text)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$ INSERT INTO kiosk_badge_event (company_id, badge_hmac, event_type) VALUES (p_company, p_hmac, p_type) $$;

-- vp_hr issues (or re-issues) the one-time activation code of an employee's badge in her company: first PIN, PIN
-- reset and unlock all go through this. The old PIN is cleared. Returns the code ONCE (to vp_hr).
CREATE OR REPLACE FUNCTION rpc_kiosk_issue_activation(p_user_id uuid, p_badge_number text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, extensions
AS $$
DECLARE
  v_comp uuid := fn_my_company();
  v_hmac text;
  v_code text := upper(encode(gen_random_bytes(5), 'hex'));
BEGIN
  PERFORM fn_assert_vp_hr(v_comp);
  PERFORM fn_j_assert_company_employee(v_comp, p_user_id);
  IF NULLIF(btrim(p_badge_number), '') IS NULL THEN
    PERFORM fn_raise_bad_request('invalid_badge');
  END IF;
  v_hmac := fn_kiosk_badge_hmac(p_badge_number);
  DELETE FROM kiosk_badge WHERE user_id = p_user_id AND badge_hmac <> v_hmac;    -- one badge per employee
  INSERT INTO kiosk_badge (company_id, badge_hmac, user_id, activation_code_hash)
  VALUES (v_comp, v_hmac, p_user_id, crypt(v_code, gen_salt('bf')))
  ON CONFLICT (company_id, badge_hmac) DO UPDATE SET user_id = EXCLUDED.user_id, pin_hash = NULL,
    activation_code_hash = EXCLUDED.activation_code_hash, failed_attempts = 0, locked_at = NULL,
    updated_at = clock_timestamp();
  PERFORM fn_kiosk_event(v_comp, v_hmac, 'activation_issued');
  PERFORM fn_audit_view('kiosk_activation_issue', '{}'::jsonb, p_user_id);
  RETURN jsonb_build_object('activation_code', v_code);
END;
$$;

-- vp_hr releases a locked badge of her company (attempts back to 0; the PIN is kept).
CREATE OR REPLACE FUNCTION rpc_kiosk_release(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_comp uuid := fn_my_company();
  b      kiosk_badge;
BEGIN
  PERFORM fn_assert_vp_hr(v_comp);
  UPDATE kiosk_badge SET failed_attempts = 0, locked_at = NULL, updated_at = clock_timestamp()
   WHERE user_id = p_user_id AND company_id = v_comp RETURNING * INTO b;
  IF b.user_id IS NULL THEN
    PERFORM fn_raise_bad_request('invalid_badge');
  END IF;
  PERFORM fn_kiosk_event(v_comp, b.badge_hmac, 'released');
  PERFORM fn_audit_view('kiosk_release', '{}'::jsonb, p_user_id);
  RETURN jsonb_build_object('status', 'released');
END;
$$;

-- The neutral refusal (unknown badge, wrong code, wrong PIN without a count message): never reveals whether the
-- badge exists.
CREATE OR REPLACE FUNCTION fn_kiosk_refusal(p_message text DEFAULT NULL, p_code text DEFAULT 'invalid_credentials')
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$ SELECT jsonb_build_object('ok', false, 'code', p_code) || CASE WHEN p_message IS NULL THEN '{}'::jsonb
                                                                     ELSE jsonb_build_object('message_he', p_message) END $$;

-- First PIN (or PIN after a vp_hr reset) with the one-time activation code. System only (Edge Function).
-- PIN = exactly 4 digits.
CREATE OR REPLACE FUNCTION rpc_kiosk_set_pin(p_company_id uuid, p_badge_number text, p_activation_code text, p_pin text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, extensions
AS $$
DECLARE
  b kiosk_badge;
BEGIN
  PERFORM fn_j_assert_system();
  IF COALESCE(p_pin, '') !~ '^[0-9]{4}$' THEN
    PERFORM fn_raise_bad_request('invalid_pin_format');
  END IF;
  SELECT * INTO b FROM kiosk_badge WHERE company_id = p_company_id AND badge_hmac = fn_kiosk_badge_hmac(p_badge_number)
   FOR UPDATE;
  IF b.user_id IS NULL OR b.activation_code_hash IS NULL OR b.locked_at IS NOT NULL
     OR crypt(COALESCE(p_activation_code, ''), b.activation_code_hash) <> b.activation_code_hash THEN
    RETURN fn_kiosk_refusal();
  END IF;
  UPDATE kiosk_badge SET pin_hash = crypt(p_pin, gen_salt('bf')), activation_code_hash = NULL, failed_attempts = 0,
         updated_at = clock_timestamp()
   WHERE company_id = b.company_id AND badge_hmac = b.badge_hmac;
  PERFORM fn_kiosk_event(b.company_id, b.badge_hmac, 'pin_set');
  RETURN jsonb_build_object('ok', true);
END;
$$;

-- Badge + PIN login. System only (Edge Function). Success → a one-time ticket (only its sha256 is stored).
-- Wrong PIN → the attempt count grows; 3 / 4 → Karin's messages; 5 → locked until vp_hr. A locked badge refuses
-- even the right PIN. Never raises (the counter must persist).
CREATE OR REPLACE FUNCTION rpc_kiosk_login(p_company_id uuid, p_badge_number text, p_pin text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, extensions
AS $$
DECLARE
  b        kiosk_badge;
  v_ticket text;
  v_failed int;
BEGIN
  PERFORM fn_j_assert_system();
  SELECT * INTO b FROM kiosk_badge WHERE company_id = p_company_id AND badge_hmac = fn_kiosk_badge_hmac(p_badge_number)
   FOR UPDATE;
  IF b.user_id IS NULL OR b.pin_hash IS NULL THEN
    RETURN fn_kiosk_refusal();
  END IF;
  IF b.locked_at IS NOT NULL THEN
    RETURN fn_kiosk_refusal(NULL, 'badge_locked');
  END IF;
  IF crypt(COALESCE(p_pin, ''), b.pin_hash) = b.pin_hash THEN
    UPDATE kiosk_badge SET failed_attempts = 0, updated_at = clock_timestamp()
     WHERE company_id = b.company_id AND badge_hmac = b.badge_hmac;
    v_ticket := encode(gen_random_bytes(32), 'hex');
    INSERT INTO kiosk_login_ticket (ticket_hash, user_id) VALUES (encode(digest(v_ticket, 'sha256'), 'hex'), b.user_id);
    PERFORM fn_kiosk_event(b.company_id, b.badge_hmac, 'login_ok');
    RETURN jsonb_build_object('ok', true, 'login_ticket', v_ticket);
  END IF;
  v_failed := b.failed_attempts + 1;
  UPDATE kiosk_badge SET failed_attempts = v_failed,
         locked_at = CASE WHEN v_failed >= 5 THEN clock_timestamp() END, updated_at = clock_timestamp()
   WHERE company_id = b.company_id AND badge_hmac = b.badge_hmac;
  PERFORM fn_kiosk_event(b.company_id, b.badge_hmac, CASE WHEN v_failed >= 5 THEN 'locked' ELSE 'login_failed' END);
  IF v_failed >= 5 THEN
    RETURN fn_kiosk_refusal(NULL, 'badge_locked');
  END IF;
  RETURN fn_kiosk_refusal(fn_kiosk_attempts_he(v_failed));
END;
$$;

REVOKE ALL ON FUNCTION rpc_kiosk_issue_activation(uuid, text), rpc_kiosk_release(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_kiosk_issue_activation(uuid, text), rpc_kiosk_release(uuid) TO authenticated;
REVOKE ALL ON FUNCTION rpc_kiosk_set_pin(uuid, text, text, text), rpc_kiosk_login(uuid, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION rpc_kiosk_set_pin(uuid, text, text, text), rpc_kiosk_login(uuid, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION rpc_kiosk_contract() TO authenticated, service_role;
REVOKE ALL ON FUNCTION fn_kiosk_badge_hmac(text), fn_kiosk_event(uuid, text, text) FROM PUBLIC, anon, authenticated;
