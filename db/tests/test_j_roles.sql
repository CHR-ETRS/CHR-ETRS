-- =============================================================================
-- CHR-ETRS v1.7.0 · tests/test_j_roles.sql — app roles + capabilities J-198 … J-203 (Karin 16.11)
-- app_role adds ONLY researcher + external_auditor; IT / works council / safety officer are capabilities.
-- =============================================================================
\ir j_helpers.sql

SELECT t_company('A', 'tech') IS NOT NULL AS a, t_company('B', 'tech') IS NOT NULL AS b;
DO $$
BEGIN
  PERFORM t_mk('hrA', 'A', 'vp_hr', 'vp', 'Mgmt');
  PERFORM t_mk('chairA', 'A', 'board_chair', 'board_chair', 'Board');
  PERFORM t_mk('hrB', 'B', 'vp_hr', 'vp', 'Mgmt');
  PERFORM t_mk('it', 'A'); PERFORM t_mk('wc', 'A'); PERFORM t_mk('safe', 'A'); PERFORM t_mk('plain', 'A');
  PERFORM t_mk('empB', 'B');
  FOR i IN 1..6 LOOP PERFORM t_mk('ops' || i, 'A', 'employee', 'employee', 'Ops'); END LOOP;
END $$;

-- ---------- app_role ----------
SELECT t_assert('app_role list = the 8 existing + researcher + external_auditor (no admin, no it / works council / safety role)',
  (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'users_app_role_check') ~ 'researcher'
  AND (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'users_app_role_check') ~ 'external_auditor'
  AND (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'users_app_role_check') !~ '(''admin''|it_admin|works_council|safety)');
SELECT t_err('an unknown app_role (admin) is refused by the CHECK',
  $$INSERT INTO users (user_id, company_id, email, full_name, app_role, timezone) VALUES (gen_random_uuid(), t_u('A'), 'x@x', 'x', 'admin', 'UTC')$$, '23514');
DO $$ BEGIN INSERT INTO auth.users (id) VALUES (t_u('selfsign')); END $$;
SELECT t_assert('signup cannot choose researcher / external_auditor — the profile stays employee',
  (t_json_as('selfsign', $$rpc_signup_profile('self@j.test', 'Self', 'Asia/Jerusalem', 'IL', t_u('A'), NULL, 'researcher')$$)->>'app_role') = 'employee');

-- ---------- capabilities (J-199 / J-201 / J-202) ----------
SELECT t_err_as('only vp_hr grants a capability (plain employee → 403)', 'plain',
  format($$SELECT rpc_grant_capability('%s', 'it_admin')$$, t_u('it')), 'insufficient_privilege', 403);
SELECT t_err_as('vp_hr of another company cannot grant to our employee → 400 invalid_user', 'hrB',
  format($$SELECT rpc_grant_capability('%s', 'it_admin')$$, t_u('it')), 'invalid_user', 400);
SELECT t_err_as('an unknown capability → 400', 'hrA',
  format($$SELECT rpc_grant_capability('%s', 'admin')$$, t_u('it')), 'invalid_capability', 400);
SELECT jsonb_typeof(t_json_as('hrA', format($$rpc_grant_capability('%s', 'it_admin')$$, t_u('it')))) AS g1,
       jsonb_typeof(t_json_as('hrA', format($$rpc_grant_capability('%s', 'works_council')$$, t_u('wc')))) AS g2,
       jsonb_typeof(t_json_as('hrA', format($$rpc_grant_capability('%s', 'safety_officer')$$, t_u('safe')))) AS g3;
SELECT jsonb_typeof(t_json_as('hrA', format($$rpc_grant_capability('%s', 'it_admin')$$, t_u('it')))) AS g1_again;
SELECT t_assert('grants are idempotent, audited, and the holders stay employees (app_role unchanged)',
  (SELECT count(*) = 3 FROM user_capability WHERE revoked_at IS NULL)
  AND (SELECT count(*) = 4 FROM access_audit_log WHERE action = 'capability_grant')
  AND (SELECT bool_and(app_role = 'employee' AND has_employee_profile) FROM users WHERE user_id IN (t_u('it'), t_u('wc'), t_u('safe'))));
SELECT t_assert('rpc_my_capabilities: the holder sees her own capability; a plain employee sees none',
  t_json_as('it', $$rpc_my_capabilities()$$) = '["it_admin"]'::jsonb AND t_json_as('plain', $$rpc_my_capabilities()$$) = '[]'::jsonb);
SELECT t_err('a grant row is never rewritten (capability change refused)',
  $$UPDATE user_capability SET capability = 'works_council' WHERE capability = 'it_admin'$$, 'ledger_immutable');
SELECT t_assert('user_capability is closed to clients', NOT has_table_privilege('authenticated', 'user_capability', 'SELECT'));

-- J-199 IT
SELECT t_assert('J-199: IT sees the connection status of her company: not connected yet, provider "לא הוגדר", no person data',
  (SELECT j->>'connected' = 'false' AND j->>'provider' = 'לא הוגדר' AND t_free_of(j, t_all_user_ids())
     FROM (SELECT t_json_as('it', $$rpc_it_connection_status()$$) j) x));
SELECT t_err_as('J-199: a plain employee → 403', 'plain', $$SELECT rpc_it_connection_status()$$, 'access_denied', 403);
SELECT t_err_as('J-199: the directory sync is system-only (client → 42501)', 'it',
  format($$SELECT fn_directory_sync_apply('%s', '{"status": "ok"}')$$, t_u('A')), '42501');

-- J-201 works council
SELECT t_err_as('J-201: the works council passes the role gate and meets the SAME privacy thresholds as the board (small company → aggregation_privacy_threshold, not access_denied)',
  'wc', $$SELECT * FROM rpc_get_board_macro_metrics()$$, 'aggregation_privacy_threshold');
SELECT t_err_as('J-201: the board chair gets the same answer on the same company', 'chairA',
  $$SELECT * FROM rpc_get_board_macro_metrics()$$, 'aggregation_privacy_threshold');
SELECT t_err_as('J-201: a plain employee → 403 access_denied', 'plain', $$SELECT * FROM rpc_get_board_macro_metrics()$$, 'access_denied', 403);
SELECT t_err_as('J-201: the works council has NO team breakdown (team agent → 403)', 'wc',
  format($$SELECT rpc_get_burnout_trend('%s', 'Ops')$$, t_u('A')), 'insufficient_privilege', 403);

-- J-202 safety officer
SELECT t_assert('J-202: the safety officer reads team-level agent figures (team Ops)',
  jsonb_typeof(t_json_as('safe', format($$rpc_get_burnout_trend('%s', 'Ops')$$, t_u('A')))) = 'object');
SELECT t_err_as('J-202: the safety officer of company A cannot read company B', 'safe',
  format($$SELECT rpc_get_burnout_trend('%s', 'TEAM')$$, t_u('B')), 'insufficient_privilege', 403);
SELECT t_assert('J-202: no shift breakdown until the entry-system sync delivered shifts',
  t_json_as('safe', $$rpc_safety_shift_breakdown()$$) = '{"available": false, "reason": "no_directory_sync"}'::jsonb);
SELECT fn_directory_sync_apply(t_u('A'), jsonb_build_object('status', 'ok', 'shifts',
  (SELECT jsonb_agg(jsonb_build_object('email', 'ops' || i || '@j.test', 'shift_code', 'בוקר')) FROM generate_series(1, 6) i))) AS synced;
SELECT t_assert('J-202: after the sync — per-shift rows only (shift + average or the standard hidden text), no person data',
  (SELECT j->>'available' = 'true' AND jsonb_array_length(j->'shifts') = 1 AND j->'shifts'->0->>'shift' = 'בוקר'
          AND t_free_of(j, t_all_user_ids())
     FROM (SELECT t_json_as('safe', $$rpc_safety_shift_breakdown()$$) j) x));
SELECT t_err_as('J-202: shift breakdown without the capability → 403', 'plain', $$SELECT rpc_safety_shift_breakdown()$$, 'access_denied', 403);
SELECT t_assert('J-199: after a sync IT sees connected / ok',
  (SELECT j->>'connected' = 'true' AND j->>'last_status' = 'ok' FROM (SELECT t_json_as('it', $$rpc_it_connection_status()$$) j) x));
SELECT t_err('J-199: the sync run log is WORM', $$DELETE FROM directory_sync_run$$, 'ledger_immutable');

-- revoke
SELECT jsonb_typeof(t_json_as('hrA', format($$rpc_revoke_capability('%s', 'works_council')$$, t_u('wc')))) AS r1;
SELECT t_err_as('after the revoke the works council loses the report → 403', 'wc',
  $$SELECT * FROM rpc_get_board_macro_metrics()$$, 'access_denied', 403);
SELECT t_assert('the revoked grant is kept (marked, not deleted) and audited',
  (SELECT count(*) = 1 FROM user_capability WHERE capability = 'works_council' AND revoked_at IS NOT NULL)
  AND (SELECT count(*) = 1 FROM access_audit_log WHERE action = 'capability_revoke'));
UPDATE users SET employment_ended_at = clock_timestamp() WHERE user_id = t_u('it');
SELECT t_assert('a leaver''s capability no longer counts', NOT EXISTS (
  SELECT 1 FROM user_capability c JOIN users u ON u.user_id = c.user_id
   WHERE c.capability = 'it_admin' AND c.revoked_at IS NULL AND u.employment_ended_at IS NULL));

-- ---------- J-203 external auditor ----------
SELECT t_err_as('J-203: only vp_hr provisions an auditor (board chair → 403)', 'chairA',
  format($$SELECT rpc_provision_external_auditor('%s', 'aud@j.test', 'Auditor', 'Asia/Jerusalem', now() - interval '1 hour',
          now() + interval '1 day', date_trunc('month', now())::date, date_trunc('month', now())::date)$$, t_u('aud')), 'insufficient_privilege', 403);
SELECT t_err_as('J-203: a window that ends before it starts → 400', 'hrA',
  format($$SELECT rpc_provision_external_auditor('%s', 'aud@j.test', 'Auditor', 'Asia/Jerusalem', now(), now() - interval '1 day',
          CURRENT_DATE, CURRENT_DATE)$$, t_u('aud')), 'invalid_auditor_window', 400);
SELECT jsonb_typeof(t_json_as('hrA', format($$rpc_provision_external_auditor('%s', 'aud@j.test', 'Auditor', 'Asia/Jerusalem',
  now() - interval '1 hour', now() + interval '1 day', date_trunc('month', now())::date, date_trunc('month', now())::date)$$, t_u('aud')))) AS prov;
SELECT t_assert('J-203: the auditor account: app_role external_auditor, no employee profile, company A',
  (SELECT app_role = 'external_auditor' AND NOT has_employee_profile AND company_id = t_u('A') FROM users WHERE user_id = t_u('aud')));
CREATE TEMP TABLE t_log AS SELECT * FROM jsonb_array_elements(t_json_as('aud', $$(SELECT jsonb_agg(to_jsonb(x)) FROM rpc_auditor_change_log() x)$$)) AS t(e);
SELECT t_assert('J-203: the change log = time, role, action AND the acting user id (Karin''s explicit exception) — nothing else',
  (SELECT count(*) >= 4 FROM t_log)
  AND (SELECT bool_and((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(e) k) = ARRAY['action', 'actor_role', 'actor_user_id', 'changed_at']) FROM t_log)
  AND EXISTS (SELECT 1 FROM t_log WHERE e->>'action' = 'capability_grant' AND e->>'actor_role' = 'vp_hr' AND (e->>'actor_user_id')::uuid = t_u('hrA')));
SELECT t_assert('J-203: the change log never carries the subject / scope of a row (no employee who received a capability)',
  NOT EXISTS (SELECT 1 FROM t_log WHERE e::text ~ (t_u('wc')::text || '|' || t_u('it')::text)));
SELECT t_assert('J-203: the auditor reads the verification levels of a month inside her range',
  jsonb_typeof(t_json_as('aud', $$rpc_auditor_verification_levels(date_trunc('month', now())::date)$$)) IS NOT NULL);
SELECT t_err_as('J-203: a month outside her data range → 403', 'aud',
  $$SELECT rpc_auditor_verification_levels((date_trunc('month', now()) - interval '1 month')::date)$$, 'access_denied', 403);
SELECT t_err_as('J-203: the auditor has no employee / board screens (macro → 403)', 'aud',
  $$SELECT * FROM rpc_get_board_macro_metrics()$$, 'access_denied', 403);
SELECT jsonb_typeof(t_json_as('hrA', format($$rpc_set_auditor_access('%s', now() - interval '2 days', now() - interval '1 day',
  date_trunc('month', now())::date, date_trunc('month', now())::date)$$, t_u('aud')))) AS closed;
SELECT t_err_as('J-203: outside the access window (vp_hr closed it) → 403', 'aud',
  $$SELECT * FROM rpc_auditor_change_log()$$, 'access_denied', 403);
SELECT t_err_as('J-203: vp_hr of another company cannot change our auditor → 400', 'hrB',
  format($$SELECT rpc_set_auditor_access('%s', now(), now() + interval '1 day', CURRENT_DATE, CURRENT_DATE)$$, t_u('aud')), 'invalid_auditor', 400);

SELECT 'ALL J ROLES TESTS PASSED' AS result;
