-- =============================================================================
-- CHR-ETRS v1.7.0 fixes · modules/55_j_kiosk_session.sql — kiosk ticket redeem + session lifetime
-- J-200 / J-219 (Karin 16.11, J-242):
--   * the one-time login ticket from rpc_kiosk_login expires 60 seconds after it was issued and is used once only;
--   * the server ends a kiosk_session 10 minutes after it started (the client J-200 idle logout stays client-side);
--   * both RPCs are for the future Edge Function: service role ONLY (no EXECUTE for PUBLIC / anon / authenticated).
-- Only sha256 hashes of the ticket and of the session token are stored. Nothing is deleted.
-- v1.7.0 fixes 2 (Karin 16.11 21:04–21:07): J-247 an expired ticket is burned but never counts as a failed attempt
-- toward the 5-attempt badge lock (these functions never touch kiosk_badge); J-248 ages are measured ONLY by the
-- server clock — now() of the call's transaction; exactly 60 s / exactly 10 minutes are still valid; no function here
-- takes a time from the device.
-- =============================================================================

CREATE TABLE IF NOT EXISTS kiosk_session (
    session_hash text PRIMARY KEY,                  -- sha256 of the session token; the token itself is never stored
    user_id      uuid NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    started_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
    ended_at     timestamptz,
    end_reason   text CHECK (end_reason IN ('max_age'))
);
ALTER TABLE kiosk_session ENABLE ROW LEVEL SECURITY;
ALTER TABLE kiosk_session FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE kiosk_session FROM PUBLIC, anon, authenticated;

-- J-242: the lifetime of a one-time login ticket (Karin: 60 seconds).
CREATE OR REPLACE FUNCTION fn_kiosk_ticket_ttl()
RETURNS interval
LANGUAGE sql
IMMUTABLE
AS $$ SELECT interval '60 seconds' $$;

-- J-242: the server-side maximum age of a kiosk session (Karin: 10 minutes).
CREATE OR REPLACE FUNCTION fn_kiosk_session_max_age()
RETURNS interval
LANGUAGE sql
IMMUTABLE
AS $$ SELECT interval '10 minutes' $$;

-- sha256 (hex) of a ticket or session token.
CREATE OR REPLACE FUNCTION fn_kiosk_token_hash(p_token text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, public, extensions
AS $$ SELECT encode(digest(COALESCE(p_token, ''), 'sha256'), 'hex') $$;

-- Why a ticket cannot be redeemed now: 'invalid_ticket' (unknown), 'ticket_used', 'ticket_expired'
-- (older than 60 seconds; exactly 60 s is still valid, J-248); NULL = redeemable. p_now = the server clock only.
CREATE OR REPLACE FUNCTION fn_kiosk_ticket_refusal_code(t kiosk_login_ticket, p_now timestamptz)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE WHEN t.ticket_hash IS NULL THEN 'invalid_ticket'
              WHEN t.used_at IS NOT NULL THEN 'ticket_used'
              WHEN p_now - t.issued_at > fn_kiosk_ticket_ttl() THEN 'ticket_expired' END
$$;

-- Why a session is not valid now: 'invalid_session' (unknown), 'session_ended', 'session_expired'
-- (older than 10 minutes; exactly 10 minutes is still valid, J-248); NULL = valid. p_now = the server clock only.
CREATE OR REPLACE FUNCTION fn_kiosk_session_refusal_code(s kiosk_session, p_now timestamptz)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE WHEN s.session_hash IS NULL THEN 'invalid_session'
              WHEN s.ended_at IS NOT NULL THEN 'session_ended'
              WHEN p_now - s.started_at > fn_kiosk_session_max_age() THEN 'session_expired' END
$$;

-- Open a new kiosk session for the ticket's employee; returns the session token ONCE (only its sha256 is kept).
CREATE OR REPLACE FUNCTION fn_kiosk_open_session(p_user uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, extensions
AS $$
DECLARE
  v_token text := encode(gen_random_bytes(32), 'hex');
  v_start timestamptz := now();                    -- J-248: server clock (the call's transaction time)
BEGIN
  INSERT INTO kiosk_session (session_hash, user_id, started_at) VALUES (fn_kiosk_token_hash(v_token), p_user, v_start);
  RETURN jsonb_build_object('ok', true, 'session_token', v_token,
                            'expires_at', v_start + fn_kiosk_session_max_age());
END;
$$;

-- J-242: redeem a one-time login ticket (service role only — the Edge Function). The ticket is consumed by the first
-- call whatever the outcome; a used, expired (> 60 s) or unknown ticket → {ok: false, code}. Success → a new
-- session token + its expiry. Never returns a user id.
CREATE OR REPLACE FUNCTION rpc_kiosk_redeem_ticket(p_ticket text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  t      kiosk_login_ticket;
  v_code text;
BEGIN
  PERFORM fn_j_assert_system();
  SELECT * INTO t FROM kiosk_login_ticket WHERE ticket_hash = fn_kiosk_token_hash(p_ticket) FOR UPDATE;
  v_code := fn_kiosk_ticket_refusal_code(t, now());   -- J-248: server clock only
  -- J-242 / J-247: the first call burns the ticket (even when expired); kiosk_badge.failed_attempts is NOT touched.
  IF t.ticket_hash IS NOT NULL AND t.used_at IS NULL THEN
    UPDATE kiosk_login_ticket SET used_at = now() WHERE ticket_hash = t.ticket_hash;
  END IF;
  IF v_code IS NOT NULL THEN
    RETURN fn_kiosk_refusal(NULL, v_code);
  END IF;
  RETURN fn_kiosk_open_session(t.user_id);
END;
$$;

-- J-242: is this kiosk session still valid? (service role only — the Edge Function, on every kiosk request).
-- Older than 10 minutes → the server ends it (ended_at, 'max_age') and refuses; ended / unknown → refused.
-- Valid → {ok: true, expires_at, seconds_left}. Never returns a user id.
CREATE OR REPLACE FUNCTION rpc_kiosk_validate_session(p_session_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  s      kiosk_session;
  v_now  timestamptz := now();                     -- J-248: server clock (the call's transaction time)
  v_code text;
BEGIN
  PERFORM fn_j_assert_system();
  SELECT * INTO s FROM kiosk_session WHERE session_hash = fn_kiosk_token_hash(p_session_token) FOR UPDATE;
  v_code := fn_kiosk_session_refusal_code(s, v_now);
  IF v_code = 'session_expired' THEN
    UPDATE kiosk_session SET ended_at = v_now, end_reason = 'max_age' WHERE session_hash = s.session_hash;
  END IF;
  IF v_code IS NOT NULL THEN
    RETURN fn_kiosk_refusal(NULL, v_code);
  END IF;
  RETURN jsonb_build_object('ok', true, 'expires_at', s.started_at + fn_kiosk_session_max_age(),
                            'seconds_left', floor(extract(epoch FROM s.started_at + fn_kiosk_session_max_age() - v_now))::int);
END;
$$;

REVOKE ALL ON FUNCTION rpc_kiosk_redeem_ticket(text), rpc_kiosk_validate_session(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION rpc_kiosk_redeem_ticket(text), rpc_kiosk_validate_session(text) TO service_role;
REVOKE ALL ON FUNCTION fn_kiosk_open_session(uuid), fn_kiosk_token_hash(text),
  fn_kiosk_ticket_refusal_code(kiosk_login_ticket, timestamptz), fn_kiosk_session_refusal_code(kiosk_session, timestamptz),
  fn_kiosk_ticket_ttl(), fn_kiosk_session_max_age() FROM PUBLIC, anon, authenticated;
