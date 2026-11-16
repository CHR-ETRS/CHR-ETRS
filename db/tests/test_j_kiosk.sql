-- =============================================================================
-- CHR-ETRS v1.7.0 · tests/test_j_kiosk.sql — shared kiosk + badge login J-200 / J-208 / J-219 (Karin 16.11)
-- The badge secret is a TEST-ONLY placeholder set in j_helpers.sql (the real one is in the server's secrets vault).
-- =============================================================================
\ir j_helpers.sql

-- Run p_sql as the service role (the Edge Function) and return its value as jsonb.
CREATE OR REPLACE FUNCTION t_svc(p_sql text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '', false);
  SET LOCAL ROLE service_role;
  EXECUTE format('SELECT to_jsonb((%s))', p_sql) INTO v;
  RESET ROLE;
  RETURN v;
END $$;

SELECT t_company('K') IS NOT NULL AS k, t_company('L') IS NOT NULL AS l;
DO $$
BEGIN
  PERFORM t_mk('hrK', 'K', 'vp_hr', 'vp', 'Mgmt'); PERFORM t_mk('hrL', 'L', 'vp_hr', 'vp', 'Mgmt');
  PERFORM t_mk('worker', 'K'); PERFORM t_mk('other', 'K'); PERFORM t_mk('mgrK', 'K', 'manager', 'direct_manager');
END $$;

SELECT t_assert('J-200: the contract (Karin''s values): idle 180 s, warning 30 s before, 5 attempts, enforced client-side',
  rpc_kiosk_contract() = '{"idle_logout_seconds": 180, "warning_seconds_before": 30, "max_pin_attempts": 5, "enforced": "client"}'::jsonb);
SELECT t_assert('J-219: login / set-PIN are NOT callable by anon or authenticated (service role = Edge Function only)',
  NOT has_function_privilege('anon', 'rpc_kiosk_login(uuid, text, text)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'rpc_kiosk_login(uuid, text, text)', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'rpc_kiosk_set_pin(uuid, text, text, text)', 'EXECUTE')
  AND has_function_privilege('service_role', 'rpc_kiosk_login(uuid, text, text)', 'EXECUTE'));
SELECT t_err_as('J-219: only vp_hr issues an activation code (manager → 403)', 'mgrK',
  format($$SELECT rpc_kiosk_issue_activation('%s', 'B-1001')$$, t_u('worker')), 'insufficient_privilege', 403);
SELECT t_err_as('J-219: vp_hr of another company cannot issue for our employee → 400', 'hrL',
  format($$SELECT rpc_kiosk_issue_activation('%s', 'B-1001')$$, t_u('worker')), 'invalid_user', 400);
CREATE TEMP TABLE t_k (label text PRIMARY KEY, j jsonb);
INSERT INTO t_k SELECT 'act', t_json_as('hrK', format($$rpc_kiosk_issue_activation('%s', 'B-1001')$$, t_u('worker')));
SELECT t_assert('J-208: the badge number is stored only as an HMAC with the server secret (never plain, never an unsalted sha256)',
  (SELECT count(*) = 1 FROM kiosk_badge)
  AND (SELECT badge_hmac = encode(hmac('B-1001', 'test-only-placeholder-badge', 'sha256'), 'hex')
              AND badge_hmac <> encode(digest('B-1001', 'sha256'), 'hex') AND badge_hmac !~ 'B-1001' FROM kiosk_badge));
SELECT t_assert('J-219: the activation code is returned ONCE to vp_hr and stored only as a bcrypt hash',
  (SELECT j->>'activation_code' ~ '^[0-9A-F]{10}$' FROM t_k WHERE label = 'act')
  AND (SELECT activation_code_hash LIKE '$2%' AND pin_hash IS NULL FROM kiosk_badge));
SELECT t_assert('J-219: without the activation code nobody can set the first PIN (neutral refusal)',
  t_svc(format($$rpc_kiosk_set_pin('%s', 'B-1001', 'WRONG', '1234')$$, t_u('K'))) = '{"ok": false, "code": "invalid_credentials"}'::jsonb);
SELECT t_assert('J-219: login before a PIN exists → the same neutral refusal (does not reveal the badge exists)',
  t_svc(format($$rpc_kiosk_login('%s', 'B-1001', '1234')$$, t_u('K'))) = t_svc(format($$rpc_kiosk_login('%s', 'NOPE', '1234')$$, t_u('K'))));
SELECT t_err('PIN must be 4 digits → 400',
  format($$SELECT t_svc('rpc_kiosk_set_pin(''%s'', ''B-1001'', ''X'', ''12a4'')')$$, t_u('K')), 'invalid_pin_format');
SELECT t_assert('J-219: with the one-time code the first PIN is set',
  t_svc(format($$rpc_kiosk_set_pin('%s', 'B-1001', '%s', '2468')$$, t_u('K'), (SELECT j->>'activation_code' FROM t_k WHERE label = 'act'))) = '{"ok": true}'::jsonb);
SELECT t_assert('J-219: the activation code is single-use (second use refused)',
  t_svc(format($$rpc_kiosk_set_pin('%s', 'B-1001', '%s', '1357')$$, t_u('K'), (SELECT j->>'activation_code' FROM t_k WHERE label = 'act'))) = '{"ok": false, "code": "invalid_credentials"}'::jsonb);
INSERT INTO t_k SELECT 'ok', t_svc(format($$rpc_kiosk_login('%s', 'B-1001', '2468')$$, t_u('K')));
SELECT t_assert('J-219: a correct PIN returns a one-time login ticket; only its sha256 is stored; no user id in the answer',
  (SELECT j->>'ok' = 'true' AND j->>'login_ticket' ~ '^[0-9a-f]{64}$' AND t_free_of(j, t_all_user_ids()) FROM t_k WHERE label = 'ok')
  AND (SELECT count(*) = 1 FROM kiosk_login_ticket WHERE ticket_hash = encode(digest((SELECT j->>'login_ticket' FROM t_k WHERE label = 'ok'), 'sha256'), 'hex'))
  AND NOT EXISTS (SELECT 1 FROM kiosk_login_ticket WHERE ticket_hash = (SELECT j->>'login_ticket' FROM t_k WHERE label = 'ok')));
-- wrong PINs 1 … 5
INSERT INTO t_k SELECT 'w1', t_svc(format($$rpc_kiosk_login('%s', 'B-1001', '0000')$$, t_u('K')));
INSERT INTO t_k SELECT 'w2', t_svc(format($$rpc_kiosk_login('%s', 'B-1001', '0000')$$, t_u('K')));
INSERT INTO t_k SELECT 'w3', t_svc(format($$rpc_kiosk_login('%s', 'B-1001', '0000')$$, t_u('K')));
INSERT INTO t_k SELECT 'w4', t_svc(format($$rpc_kiosk_login('%s', 'B-1001', '0000')$$, t_u('K')));
SELECT t_assert('J-208: wrong 1–2 → neutral; after the 3rd "נשארו 2 ניסיונות"; after the 4th "נשאר ניסיון 1"',
  (SELECT j = '{"ok": false, "code": "invalid_credentials"}'::jsonb FROM t_k WHERE label = 'w1')
  AND (SELECT j = '{"ok": false, "code": "invalid_credentials"}'::jsonb FROM t_k WHERE label = 'w2')
  AND (SELECT j->>'message_he' = 'נשארו 2 ניסיונות' FROM t_k WHERE label = 'w3')
  AND (SELECT j->>'message_he' = 'נשאר ניסיון 1' FROM t_k WHERE label = 'w4'));
INSERT INTO t_k SELECT 'w5', t_svc(format($$rpc_kiosk_login('%s', 'B-1001', '0000')$$, t_u('K')));
INSERT INTO t_k SELECT 'after', t_svc(format($$rpc_kiosk_login('%s', 'B-1001', '2468')$$, t_u('K')));
SELECT t_assert('J-208: the 5th wrong PIN locks; then even the right PIN → badge_locked (until vp_hr)',
  (SELECT j->>'code' = 'badge_locked' FROM t_k WHERE label = 'w5') AND (SELECT j->>'code' = 'badge_locked' FROM t_k WHERE label = 'after')
  AND (SELECT locked_at IS NOT NULL AND failed_attempts = 5 FROM kiosk_badge));
SELECT t_err_as('J-208: only vp_hr of the company releases (vp_hr of L → 400 invalid_badge)', 'hrL',
  format($$SELECT rpc_kiosk_release('%s')$$, t_u('worker')), 'invalid_badge', 400);
SELECT jsonb_typeof(t_json_as('hrK', format($$rpc_kiosk_release('%s')$$, t_u('worker')))) AS released;
SELECT t_assert('J-208: after vp_hr releases, the kept PIN works again',
  t_svc(format($$rpc_kiosk_login('%s', 'B-1001', '2468')$$, t_u('K')))->>'ok' = 'true');
SELECT t_assert('J-208: every badge event is logged (WORM) with the HMAC only — no user id column',
  (SELECT count(*) >= 10 FROM kiosk_badge_event)
  AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'kiosk_badge_event' AND column_name ~ 'user'));
SELECT t_err('kiosk_badge_event is WORM', $$DELETE FROM kiosk_badge_event$$, 'ledger_immutable');
-- PIN reset goes through vp_hr: a new activation code clears the old PIN
INSERT INTO t_k SELECT 'act2', t_json_as('hrK', format($$rpc_kiosk_issue_activation('%s', 'B-1001')$$, t_u('worker')));
SELECT t_assert('J-219: a PIN reset = a new vp_hr activation code; the old PIN stops working',
  t_svc(format($$rpc_kiosk_login('%s', 'B-1001', '2468')$$, t_u('K')))->>'ok' = 'false'
  AND (SELECT pin_hash IS NULL FROM kiosk_badge));
SELECT t_assert('a badge HMAC belongs to one company (same number in company L does not log into K)',
  t_svc(format($$rpc_kiosk_login('%s', 'B-1001', '2468')$$, t_u('L'))) = '{"ok": false, "code": "invalid_credentials"}'::jsonb);
SELECT t_err('J-208: no badge secret configured → 422 secret_not_configured',
  $$SELECT set_config('chr.secret_badge', '', true), fn_kiosk_badge_hmac('B-1')$$, 'secret_not_configured');
SELECT t_assert('kiosk tables are closed to clients',
  NOT has_table_privilege('authenticated', 'kiosk_badge', 'SELECT') AND NOT has_table_privilege('anon', 'kiosk_login_ticket', 'SELECT'));

-- ---------- J-242 (Karin 16.11): ticket redeem (60 s, once) + server session limit (10 minutes) ----------
-- Real clock: old tickets / sessions are backdated rows, never a fake clock.
SELECT t_assert('J-242: set the PIN again with the vp_hr reset code (setup)',
  t_svc(format($$rpc_kiosk_set_pin('%s', 'B-1001', '%s', '2468')$$, t_u('K'), (SELECT j->>'activation_code' FROM t_k WHERE label = 'act2'))) = '{"ok": true}'::jsonb);
INSERT INTO t_k SELECT 'tk', t_svc(format($$rpc_kiosk_login('%s', 'B-1001', '2468')$$, t_u('K')));
INSERT INTO t_k SELECT 'red1', t_svc(format($$rpc_kiosk_redeem_ticket('%s')$$, (SELECT j->>'login_ticket' FROM t_k WHERE label = 'tk')));
SELECT t_assert('J-242 happy path: a fresh ticket → a session token + expiry 10 minutes after the start; no user id in the answer',
  (SELECT j->>'ok' = 'true' AND j->>'session_token' ~ '^[0-9a-f]{64}$' AND t_free_of(j, t_all_user_ids()) FROM t_k WHERE label = 'red1')
  AND (SELECT (s.started_at + interval '10 minutes') = ((SELECT j->>'expires_at' FROM t_k WHERE label = 'red1')::timestamptz)
         FROM kiosk_session s WHERE s.session_hash = encode(digest((SELECT j->>'session_token' FROM t_k WHERE label = 'red1'), 'sha256'), 'hex'))
  AND NOT EXISTS (SELECT 1 FROM kiosk_session WHERE session_hash = (SELECT j->>'session_token' FROM t_k WHERE label = 'red1')));
INSERT INTO t_k SELECT 'val1', t_svc(format($$rpc_kiosk_validate_session('%s')$$, (SELECT j->>'session_token' FROM t_k WHERE label = 'red1')));
SELECT t_assert('J-242 happy path: the new session is valid (ok, expires_at, seconds_left 1…600); no user id',
  (SELECT j->>'ok' = 'true' AND (j->>'seconds_left')::int BETWEEN 1 AND 600 AND t_free_of(j, t_all_user_ids()) FROM t_k WHERE label = 'val1'));
INSERT INTO t_k SELECT 'red2', t_svc(format($$rpc_kiosk_redeem_ticket('%s')$$, (SELECT j->>'login_ticket' FROM t_k WHERE label = 'tk')));
SELECT t_assert('J-242: an already redeemed ticket is refused the second time (ticket_used) and opens no session',
  (SELECT j = '{"ok": false, "code": "ticket_used"}'::jsonb FROM t_k WHERE label = 'red2')
  AND (SELECT count(*) = 1 FROM kiosk_session));
INSERT INTO t_k SELECT 'tk61', t_svc(format($$rpc_kiosk_login('%s', 'B-1001', '2468')$$, t_u('K')));
UPDATE kiosk_login_ticket SET issued_at = clock_timestamp() - interval '61 seconds'
 WHERE ticket_hash = encode(digest((SELECT j->>'login_ticket' FROM t_k WHERE label = 'tk61'), 'sha256'), 'hex');
INSERT INTO t_k SELECT 'red61', t_svc(format($$rpc_kiosk_redeem_ticket('%s')$$, (SELECT j->>'login_ticket' FROM t_k WHERE label = 'tk61')));
SELECT t_assert('J-242: a 61-second-old ticket is refused (ticket_expired), consumed, and opens no session',
  (SELECT j = '{"ok": false, "code": "ticket_expired"}'::jsonb FROM t_k WHERE label = 'red61')
  AND (SELECT used_at IS NOT NULL FROM kiosk_login_ticket
        WHERE ticket_hash = encode(digest((SELECT j->>'login_ticket' FROM t_k WHERE label = 'tk61'), 'sha256'), 'hex'))
  AND (SELECT count(*) = 1 FROM kiosk_session));
INSERT INTO t_k SELECT 'tk59', t_svc(format($$rpc_kiosk_login('%s', 'B-1001', '2468')$$, t_u('K')));
UPDATE kiosk_login_ticket SET issued_at = clock_timestamp() - interval '59 seconds'
 WHERE ticket_hash = encode(digest((SELECT j->>'login_ticket' FROM t_k WHERE label = 'tk59'), 'sha256'), 'hex');
SELECT t_assert('J-242: a 59-second-old ticket is still redeemed',
  t_svc(format($$rpc_kiosk_redeem_ticket('%s')$$, (SELECT j->>'login_ticket' FROM t_k WHERE label = 'tk59')))->>'ok' = 'true');
SELECT t_assert('J-242: an unknown ticket → invalid_ticket',
  t_svc($$rpc_kiosk_redeem_ticket('nope')$$) = '{"ok": false, "code": "invalid_ticket"}'::jsonb);
UPDATE kiosk_session SET started_at = clock_timestamp() - interval '10 minutes 1 second'
 WHERE session_hash = encode(digest((SELECT j->>'session_token' FROM t_k WHERE label = 'red1'), 'sha256'), 'hex');
INSERT INTO t_k SELECT 'val_old', t_svc(format($$rpc_kiosk_validate_session('%s')$$, (SELECT j->>'session_token' FROM t_k WHERE label = 'red1')));
SELECT t_assert('J-242: a session older than 10 minutes is refused (session_expired) and the server ends it (max_age)',
  (SELECT j = '{"ok": false, "code": "session_expired"}'::jsonb FROM t_k WHERE label = 'val_old')
  AND (SELECT ended_at IS NOT NULL AND end_reason = 'max_age' FROM kiosk_session
        WHERE session_hash = encode(digest((SELECT j->>'session_token' FROM t_k WHERE label = 'red1'), 'sha256'), 'hex')));
SELECT t_assert('J-242: an ended session stays refused (session_ended); an unknown token → invalid_session',
  t_svc(format($$rpc_kiosk_validate_session('%s')$$, (SELECT j->>'session_token' FROM t_k WHERE label = 'red1'))) = '{"ok": false, "code": "session_ended"}'::jsonb
  AND t_svc($$rpc_kiosk_validate_session('nope')$$) = '{"ok": false, "code": "invalid_session"}'::jsonb);
-- ---------- J-247 (Karin 16.11): expired tickets never count toward the 5-attempt badge lock ----------
INSERT INTO t_k SELECT 'x' || i, t_svc(format($$rpc_kiosk_login('%s', 'B-1001', '0000')$$, t_u('K'))) FROM generate_series(1, 4) i;
CREATE TEMP TABLE t_before AS SELECT b.failed_attempts, (SELECT count(*) FROM kiosk_badge_event) AS events FROM kiosk_badge b WHERE b.user_id = t_u('worker');
INSERT INTO kiosk_login_ticket (ticket_hash, user_id, issued_at)
SELECT encode(digest('expired-' || i, 'sha256'), 'hex'), t_u('worker'), clock_timestamp() - interval '5 minutes' FROM generate_series(1, 5) i;
CREATE TEMP TABLE t_exp AS SELECT i, t_svc(format($$rpc_kiosk_redeem_ticket('expired-%s')$$, i)) AS j FROM generate_series(1, 5) i;
SELECT t_assert('J-247: 5 expired tickets in a row (after 4 wrong PINs) → each refused ticket_expired and burned, but the badge is NOT locked — attempts stay 4, no badge event',
  (SELECT bool_and(j = '{"ok": false, "code": "ticket_expired"}'::jsonb) AND count(*) = 5 FROM t_exp)
  AND (SELECT count(*) = 5 FROM kiosk_login_ticket WHERE ticket_hash IN (SELECT encode(digest('expired-' || i, 'sha256'), 'hex') FROM generate_series(1, 5) i) AND used_at IS NOT NULL)
  AND (SELECT b.failed_attempts = 4 AND b.locked_at IS NULL FROM kiosk_badge b WHERE b.user_id = t_u('worker'))
  AND (SELECT failed_attempts = 4 FROM t_before)
  AND (SELECT count(*) FROM kiosk_badge_event) = (SELECT events FROM t_before));
SELECT t_assert('J-247: the right PIN still logs in after the 5 expired tickets (not locked)',
  t_svc(format($$rpc_kiosk_login('%s', 'B-1001', '2468')$$, t_u('K')))->>'ok' = 'true');

-- ---------- J-248 (Karin 16.11): exactly 60 s / exactly 10 minutes are valid — server clock (now()) only ----------
-- Backdate + call in ONE transaction (one statement), so now() is the same instant for both → the age is exact.
-- Insert a ticket aged exactly p_age on the server clock and redeem it in the same transaction.
CREATE OR REPLACE FUNCTION t_redeem_at_age(p_ticket text, p_age interval) RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO kiosk_login_ticket (ticket_hash, user_id, issued_at) VALUES (encode(digest(p_ticket, 'sha256'), 'hex'), t_u('worker'), now() - p_age);
  RETURN t_svc(format('rpc_kiosk_redeem_ticket(%L)', p_ticket));
END $$;
-- Insert a session aged exactly p_age on the server clock and validate it in the same transaction.
CREATE OR REPLACE FUNCTION t_validate_at_age(p_token text, p_age interval) RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO kiosk_session (session_hash, user_id, started_at) VALUES (encode(digest(p_token, 'sha256'), 'hex'), t_u('worker'), now() - p_age);
  RETURN t_svc(format('rpc_kiosk_validate_session(%L)', p_token));
END $$;
SELECT t_assert('J-248: a ticket aged EXACTLY 60 seconds (server clock) is redeemed',
  t_redeem_at_age('age-60', interval '60 seconds')->>'ok' = 'true');
SELECT t_assert('J-248: a ticket aged 60.001 seconds is refused (ticket_expired)',
  t_redeem_at_age('age-60001', interval '60.001 seconds') = '{"ok": false, "code": "ticket_expired"}'::jsonb);
SELECT t_assert('J-248: a session aged EXACTLY 10 minutes (server clock) is valid (seconds_left 0)',
  (SELECT j->>'ok' = 'true' AND (j->>'seconds_left')::int = 0 FROM (SELECT t_validate_at_age('sess-600', interval '10 minutes') j) x));
SELECT t_assert('J-248: a session aged 10 minutes + 1 ms is refused (session_expired)',
  t_validate_at_age('sess-600001', interval '10 minutes 0.001 seconds') = '{"ok": false, "code": "session_expired"}'::jsonb);
SELECT t_assert('J-248: no kiosk RPC takes a time from the device (redeem / validate take only the text code; login / set-PIN have no time parameter)',
  NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.proname IN ('rpc_kiosk_redeem_ticket', 'rpc_kiosk_validate_session', 'rpc_kiosk_login', 'rpc_kiosk_set_pin')
                 AND EXISTS (SELECT 1 FROM unnest(p.proargtypes::oid[]) t WHERE t IN ('timestamptz'::regtype, 'timestamp'::regtype, 'date'::regtype, 'interval'::regtype, 'bigint'::regtype))));
SELECT t_assert('J-242: redeem / validate are service role ONLY (no EXECUTE for PUBLIC, anon, authenticated)',
  has_function_privilege('service_role', 'rpc_kiosk_redeem_ticket(text)', 'EXECUTE')
  AND has_function_privilege('service_role', 'rpc_kiosk_validate_session(text)', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'rpc_kiosk_redeem_ticket(text)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'rpc_kiosk_redeem_ticket(text)', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'rpc_kiosk_validate_session(text)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'rpc_kiosk_validate_session(text)', 'EXECUTE')
  AND NOT EXISTS (SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a
                   WHERE p.proname IN ('rpc_kiosk_redeem_ticket', 'rpc_kiosk_validate_session') AND a.grantee = 0));
SELECT t_assert('J-242: kiosk_session is closed to clients and stores only the token hash (no token column)',
  NOT has_table_privilege('authenticated', 'kiosk_session', 'SELECT') AND NOT has_table_privilege('anon', 'kiosk_session', 'SELECT')
  AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'kiosk_session' AND column_name = 'session_token'));

SELECT 'ALL J KIOSK TESTS PASSED' AS result;
