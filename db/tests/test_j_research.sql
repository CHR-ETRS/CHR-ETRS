-- =============================================================================
-- CHR-ETRS v1.7.0 · tests/test_j_research.sql — research access J-178 … J-192, J-215, J-216 (Karin 16.11)
-- Fresh DB: ref_country_calendar.sql + schema.sql + rpc.sql + modules/all.sql, then tests/j_helpers.sql + this file.
-- =============================================================================
\ir j_helpers.sql

-- ---------- fixtures: companies R (22 employees), R2 (22, one metric with 19), R3 (20) — sector 'tech' ----------
SELECT t_company('R', 'tech') IS NOT NULL AS r, t_company('R2', 'tech') IS NOT NULL AS r2, t_company('R3', 'tech') IS NOT NULL AS r3,
       t_company('R4', 'unique-sector') IS NOT NULL AS r4;
DO $$
BEGIN
  PERFORM t_mk('hrR', 'R', 'vp_hr', 'vp', 'Mgmt');
  PERFORM t_mk('cfoR', 'R', 'cfo', 'vp', 'Mgmt');
  PERFORM t_mk('hrR2', 'R2', 'vp_hr', 'vp', 'Mgmt');
  FOR i IN 1..22 LOOP
    PERFORM t_mk('r' || i, 'R');
    PERFORM t_mk('s' || i, 'R2');
  END LOOP;
  FOR i IN 1..20 LOOP PERFORM t_mk('t' || i, 'R3'); PERFORM t_mk('u' || i, 'R4'); END LOOP;
  -- the last completed quarter: 20 employees of R fill PCQ-12 / IHS / TPS-12; R2: 20 / 20 / 19
  FOR i IN 1..20 LOOP
    PERFORM t_sub('r' || i, 'PCQ-12', t_last_q() + 10, 40 + i);
    PERFORM t_sub('r' || i, 'IHS', t_last_q() + 11, 50 + i);
    PERFORM t_sub('r' || i, 'TPS-12', t_last_q() + 12, 60 + i);
    PERFORM t_sub('s' || i, 'PCQ-12', t_last_q() + 10, 40 + i);
    PERFORM t_sub('s' || i, 'IHS', t_last_q() + 11, 50 + i);
    IF i <= 19 THEN PERFORM t_sub('s' || i, 'TPS-12', t_last_q() + 12, 60 + i); END IF;
  END LOOP;
END $$;

-- ---------- config: researchers + DPAs only through db/config (system) ----------
SELECT t_assert('J-181: the config loader is system-only (no EXECUTE for clients)',
  NOT has_function_privilege('authenticated', 'fn_sync_research_config(jsonb)', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'fn_sync_research_config(jsonb)', 'EXECUTE'));
SELECT t_err_as('J-181: even a vp_hr cannot load researchers / DPAs → 42501', 'hrR',
  $$SELECT fn_sync_research_config('{}'::jsonb)$$, '42501');
SELECT t_err('J-189: a DPA longer than 2 years is refused (CHECK)',
  format($$SELECT fn_sync_research_config('{"researchers": [{"email": "bad@res.test", "full_name": "Bad", "timezone": "Asia/Jerusalem"}],
          "dpas": [{"company_id": "%s", "researcher_email": "bad@res.test", "dpa_signed_on": "2026-01-01", "dpa_valid_until": "2028-01-02"}]}'::jsonb)$$, t_u('R')),
  '23514');
SELECT fn_sync_research_config(jsonb_build_object(
  'researchers', jsonb_build_array(
     jsonb_build_object('email', 'res1@res.test', 'full_name', 'Researcher One', 'timezone', 'Asia/Jerusalem'),
     jsonb_build_object('email', 'res2@res.test', 'full_name', 'Researcher Two', 'timezone', 'Asia/Jerusalem')),
  'dpas', jsonb_build_array(
     jsonb_build_object('company_id', t_u('R'), 'researcher_email', 'res1@res.test', 'dpa_signed_on', CURRENT_DATE - 30, 'dpa_valid_until', CURRENT_DATE + 600),
     jsonb_build_object('company_id', t_u('R'), 'researcher_email', 'res2@res.test', 'dpa_signed_on', CURRENT_DATE - 30, 'dpa_valid_until', CURRENT_DATE + 600),
     jsonb_build_object('company_id', t_u('R2'), 'researcher_email', 'res1@res.test', 'dpa_signed_on', CURRENT_DATE - 30, 'dpa_valid_until', CURRENT_DATE + 600)))) AS dpas;
-- test keys for the researcher accounts (created by config with random ids)
CREATE TEMP TABLE t_res AS SELECT email, user_id FROM users WHERE app_role = 'researcher';
CREATE OR REPLACE FUNCTION t_as_res(p_email text) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', (SELECT user_id::text FROM t_res WHERE email = p_email), false)
$$;
-- Run p_sql as a researcher (client role) and return its value as jsonb.
CREATE OR REPLACE FUNCTION t_res_json(p_email text, p_sql text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v jsonb;
BEGIN
  PERFORM t_as_res(p_email);
  SET LOCAL ROLE authenticated;
  EXECUTE format('SELECT to_jsonb((%s))', p_sql) INTO v;
  RESET ROLE;
  RETURN v;
END $$;
-- Expect a researcher call to fail with p_code / p_http.
CREATE OR REPLACE FUNCTION t_res_err(p_name text, p_email text, p_sql text, p_code text, p_http int) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_detail text; v_msg text;
BEGIN
  BEGIN
    PERFORM t_as_res(p_email);
    SET LOCAL ROLE authenticated;
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_detail = PG_EXCEPTION_DETAIL, v_msg = MESSAGE_TEXT;
    RESET ROLE;
    IF v_msg = p_code AND v_detail = format('http_hint=%s;code=%s', p_http, p_code) THEN PERFORM t_pass(p_name); RETURN; END IF;
    RAISE EXCEPTION 'FAIL % — got % / %', p_name, v_msg, v_detail;
  END;
  RAISE EXCEPTION 'FAIL % — no error', p_name;
END $$;
GRANT SELECT ON t_res TO authenticated;
SELECT t_assert('J-181: researcher accounts come from config: app_role researcher, no company, no employee profile (2 accounts, 3 DPAs)',
  (SELECT count(*) = 2 AND bool_and(company_id IS NULL AND NOT has_employee_profile) FROM users WHERE app_role = 'researcher')
  AND (SELECT count(*) = 3 FROM research_dpa));

-- ---------- J-215 acknowledgement ----------
SELECT t_res_err('J-215: before the acknowledgement every research RPC → 403 onboarding_not_acknowledged', 'res1@res.test',
  $$SELECT rpc_research_my_companies()$$, 'onboarding_not_acknowledged', 403);
CREATE TEMP TABLE t_ack AS SELECT t_res_json('res1@res.test', $$rpc_researcher_acknowledge()$$) AS a1;
INSERT INTO t_ack SELECT t_res_json('res2@res.test', $$rpc_researcher_acknowledge()$$);
SELECT t_assert('J-215: the acknowledgement is logged (WORM row + audit)',
  (SELECT bool_and((a1->>'acknowledged')::boolean) FROM t_ack)
  AND (SELECT count(*) = 2 FROM researcher_ack)
  AND (SELECT count(*) = 2 FROM access_audit_log WHERE action = 'researcher_acknowledge'));
SELECT t_err('J-215: researcher_ack is WORM', $$DELETE FROM researcher_ack$$, 'ledger_immutable');

-- ---------- J-184 company code + descriptor ----------
CREATE TEMP TABLE t_codes AS SELECT 'R' AS k, fn_research_company_code(t_u('R')) AS code
  UNION ALL SELECT 'R2', fn_research_company_code(t_u('R2')) UNION ALL SELECT 'R3', fn_research_company_code(t_u('R3'));
GRANT SELECT ON t_codes TO authenticated;
SELECT t_assert('J-184: the company code is an HMAC-SHA256 (64 hex) with the server secret, never the company id',
  (SELECT bool_and(code ~ '^[0-9a-f]{64}$') FROM t_codes)
  AND fn_research_company_code(t_u('R')) <> encode(digest(t_u('R')::text, 'sha256'), 'hex'));
SELECT t_err('J-184: the secret is read only from the server setting — missing → 422 secret_not_configured',
  $$SELECT set_config('chr.secret_research_company', '', true), fn_research_company_code(t_u('R'))$$, 'secret_not_configured');
SELECT t_assert('J-184: no secret is stored in any table of the pack (no column named like secret / hmac_key)',
  NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND column_name ~* '(secret|hmac_key|api_key)'));
CREATE TEMP TABLE t_out (label text PRIMARY KEY, j jsonb);
INSERT INTO t_out SELECT 'mine', t_res_json('res1@res.test', $$rpc_research_my_companies()$$);
SELECT t_assert('J-184: the researcher sees only DPA companies: code + sector + size band 20–99 (3 tech companies share it)',
  (SELECT jsonb_array_length(j) = 2 FROM t_out WHERE label = 'mine')
  AND (SELECT bool_and(e->>'sector_he' = 'tech' AND e->>'size_band' = '20–99'
                                                 AND e->>'company_code' IN (SELECT code FROM t_codes))
     FROM t_out, jsonb_array_elements(j) e WHERE label = 'mine'));
SELECT t_assert('J-184: fewer than 3 companies in the same sector + band → the sector only (no size band)',
  fn_research_descriptor(t_u('R4')) = '{"sector_he": "unique-sector", "size_band": null}'::jsonb);
SELECT t_assert('J-184: size bands exactly 20–99, 100–499, 500–1999, 2000+ (under 20 → none)',
  fn_research_size_band(19) IS NULL AND fn_research_size_band(20) = '20–99' AND fn_research_size_band(99) = '20–99'
  AND fn_research_size_band(100) = '100–499' AND fn_research_size_band(499) = '100–499' AND fn_research_size_band(500) = '500–1999'
  AND fn_research_size_band(1999) = '500–1999' AND fn_research_size_band(2000) = '2000+');

-- ---------- requests + approval (J-187 / J-188) ----------
SELECT t_res_err('request without the deletion commitment → 400', 'res1@res.test',
  format($$SELECT rpc_research_request('%s', '%s', '%s', CURRENT_DATE + 730, false)$$,
         (SELECT code FROM t_codes WHERE k = 'R'), fn_j_quarter_label(t_last_q()), fn_j_quarter_label(t_last_q())),
  'invalid_research_request', 400);
SELECT t_res_err('J-187: a company without a DPA for this researcher (R3) → 403 dpa_not_valid', 'res1@res.test',
  format($$SELECT rpc_research_request('%s', '%s', '%s', CURRENT_DATE + 730, true)$$,
         (SELECT code FROM t_codes WHERE k = 'R3'), fn_j_quarter_label(t_last_q()), fn_j_quarter_label(t_last_q())),
  'dpa_not_valid', 403);
INSERT INTO t_out SELECT 'req1', t_res_json('res1@res.test', format($$rpc_research_request('%s', '%s', '%s', CURRENT_DATE + 730, true)$$,
  (SELECT code FROM t_codes WHERE k = 'R'), fn_j_quarter_label(t_last_q()), fn_j_quarter_label(CURRENT_DATE)));
INSERT INTO t_out SELECT 'req2', t_res_json('res1@res.test', format($$rpc_research_request('%s', '%s', '%s', CURRENT_DATE + 100, true)$$,
  (SELECT code FROM t_codes WHERE k = 'R2'), fn_j_quarter_label(t_last_q()), fn_j_quarter_label(t_last_q())));
GRANT SELECT ON t_out TO authenticated;
SELECT t_assert('J-187: one request = one company (a researcher with two companies has two requests and two DPAs)',
  (SELECT count(DISTINCT company_id) = 2 AND count(*) = 2 FROM research_request)
  AND (SELECT count(*) = 2 FROM research_dpa d JOIN t_res r ON r.user_id = d.researcher_id WHERE r.email = 'res1@res.test'));
SELECT t_res_err('export before approval → 403 research_not_approved', 'res1@res.test',
  format($$SELECT rpc_research_export('%s')$$, (SELECT j->>'request_id' FROM t_out WHERE label = 'req1')), 'research_not_approved', 403);
SELECT t_err_as('J-188: the vp_hr of ANOTHER company cannot approve → 403', 'hrR2',
  format($$SELECT rpc_research_decide('%s', true)$$, (SELECT j->>'request_id' FROM t_out WHERE label = 'req1')), 'insufficient_privilege', 403);
SELECT t_err_as('J-188: a cfo cannot approve → 403', 'cfoR',
  format($$SELECT rpc_research_decide('%s', true)$$, (SELECT j->>'request_id' FROM t_out WHERE label = 'req1')), 'insufficient_privilege', 403);
INSERT INTO t_out SELECT 'dec1', t_json_as('hrR', format($$rpc_research_decide('%s', true)$$, (SELECT j->>'request_id' FROM t_out WHERE label = 'req1')));
INSERT INTO t_out SELECT 'dec2', t_json_as('hrR2', format($$rpc_research_decide('%s', true)$$, (SELECT j->>'request_id' FROM t_out WHERE label = 'req2')));
SELECT t_assert('J-188: approval valid to the end of the research period, at most 1 year (period 2 years → 1 year; 100 days → 100 days)',
  (SELECT (j->>'approval_valid_until')::date = (CURRENT_DATE + interval '1 year')::date FROM t_out WHERE label = 'dec1')
  AND (SELECT (j->>'approval_valid_until')::date = CURRENT_DATE + 100 FROM t_out WHERE label = 'dec2'));
SELECT t_assert('J-188: the decision is audited (vp_hr, research_decide)',
  (SELECT count(*) = 2 FROM access_audit_log WHERE action = 'research_decide'));

-- ---------- export (J-180 … J-185) ----------
INSERT INTO t_out SELECT 'exp1', t_res_json('res1@res.test', format($$rpc_research_export('%s')$$, (SELECT j->>'request_id' FROM t_out WHERE label = 'req1')));
SELECT t_assert('J-185: only completed quarters 14 days after their end — the last quarter is in, the current one is not',
  (SELECT jsonb_array_length(j->'quarters') = 1 AND j->'quarters'->0->>'quarter' = fn_j_quarter_label(t_last_q()) FROM t_out WHERE label = 'exp1'));
SELECT t_assert('J-185: the 14-day rule on the company calendar — 13 days after the end: out; 14 days: in',
  NOT fn_j_quarter_ready(t_u('R'), t_last_q(), ((t_last_q() + interval '3 months')::date + 13 + time '12:00') AT TIME ZONE 'Asia/Jerusalem')
  AND fn_j_quarter_ready(t_u('R'), t_last_q(), ((t_last_q() + interval '3 months')::date + 14 + time '00:30') AT TIME ZONE 'Asia/Jerusalem'));
SELECT t_assert('J-183 / research scope 20: 20 מדווחים בפועל in every metric → the quarter is shown: PCQ-12 / IHS / TPS-12 (N, average, score range) + response rate (20 of 24 active = 83%)',
  (SELECT q->>'shown' = 'true' AND (q->'pcq12'->>'n')::int = 20 AND (q->'ihs'->>'n')::int = 20 AND (q->'tps12'->>'n')::int = 20
          AND (q->'pcq12'->>'average')::numeric = 50.5 AND q->'pcq12'->'score_range' ? 'p25'
          AND (q->>'response_rate_pct')::int = 83
     FROM t_out, jsonb_extract_path(j, 'quarters', '0') q WHERE label = 'exp1'));
SELECT t_assert('J-183: nothing else in the export — keys are company_code, dataset, sector_he, size_band, quarters only; no happiness debt / tax / money',
  (SELECT (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(j) k) = ARRAY['company_code', 'dataset', 'quarters', 'sector_he', 'size_band']
          AND j::text !~* '(debt|tax|ils|salary|ebitda|קיפוח|חוב)' FROM t_out WHERE label = 'exp1'));
SELECT t_assert('J-182 / J-184: no company name, company id, user id, person id or pseudonym in the export',
  (SELECT t_free_of(j, t_all_user_ids() || ARRAY[t_u('R')::text, 'Company R'])
          AND NOT t_free_of(j, ARRAY[(SELECT code FROM t_codes WHERE k = 'R')])
          AND t_free_of(j, (SELECT array_agg(display_pseudonym::text) FROM users)) FROM t_out WHERE label = 'exp1'));
INSERT INTO t_out SELECT 'exp2', t_res_json('res1@res.test', format($$rpc_research_export('%s')$$, (SELECT j->>'request_id' FROM t_out WHERE label = 'req2')));
SELECT t_assert('J-185: one metric under 20 (TPS-12 19) → the WHOLE quarter is hidden with "אין מספיק נתונים להצגה בתקופה זו"',
  (SELECT q->>'shown' = 'false' AND q->>'display_he' = 'אין מספיק נתונים להצגה בתקופה זו' AND NOT q ? 'pcq12' AND NOT q ? 'ihs'
     FROM t_out, jsonb_extract_path(j, 'quarters', '0') q WHERE label = 'exp2')
  AND fn_insufficient_data_period_he() = 'אין מספיק נתונים להצגה בתקופה זו');
SELECT t_assert('J-186: the export log keeps the published cells only (quarter / metric / N; no person)',
  (SELECT count(*) = 2 FROM research_export_log)
  AND (SELECT jsonb_array_length(cells) = 3 FROM research_export_log WHERE company_id = t_u('R'))
  AND (SELECT jsonb_array_length(cells) = 0 FROM research_export_log WHERE company_id = t_u('R2'))
  AND (SELECT bool_and((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(c) k) = ARRAY['metric', 'n', 'quarter'])
         FROM research_export_log l, jsonb_array_elements(l.cells) c));
SELECT t_err('J-190: the export log is WORM (UPDATE refused)', $$UPDATE research_export_log SET cells = '[]'$$, 'ledger_immutable');
SELECT t_err('J-190: the export log is WORM (DELETE refused)', $$DELETE FROM research_export_log$$, 'ledger_immutable');
-- J-180 / J-186: one more employee of R answers that quarter; ANOTHER researcher exports it → difference 1 → hidden
SELECT t_sub('r21', 'PCQ-12', t_last_q() + 20, 70), t_sub('r21', 'IHS', t_last_q() + 20, 70), t_sub('r21', 'TPS-12', t_last_q() + 20, 70);
INSERT INTO t_out SELECT 'req3', t_res_json('res2@res.test', format($$rpc_research_request('%s', '%s', '%s', CURRENT_DATE + 200, true)$$,
  (SELECT code FROM t_codes WHERE k = 'R'), fn_j_quarter_label(t_last_q()), fn_j_quarter_label(t_last_q())));
SELECT jsonb_typeof(t_json_as('hrR', format($$rpc_research_decide('%s', true)$$, (SELECT j->>'request_id' FROM t_out WHERE label = 'req3')))) AS dec3;
INSERT INTO t_out SELECT 'exp3', t_res_json('res2@res.test', format($$rpc_research_export('%s')$$, (SELECT j->>'request_id' FROM t_out WHERE label = 'req3')));
SELECT t_assert('J-180 / J-186: an N that differs from an earlier export of the same company by 1–19 (20 → 21, another researcher) → the quarter is hidden',
  (SELECT q->>'shown' = 'false' AND q->>'display_he' = 'אין מספיק נתונים להצגה בתקופה זו'
     FROM t_out, jsonb_extract_path(j, 'quarters', '0') q WHERE label = 'exp3')
  AND fn_research_difference_hit(t_u('R'), fn_j_quarter_label(t_last_q()), 'PCQ-12', 21)
  AND NOT fn_research_difference_hit(t_u('R'), fn_j_quarter_label(t_last_q()), 'PCQ-12', 20)
  AND NOT fn_research_difference_hit(t_u('R'), fn_j_quarter_label(t_last_q()), 'PCQ-12', 40));
-- revoke → next export refused
SELECT jsonb_typeof(t_json_as('hrR', format($$rpc_research_revoke('%s')$$, (SELECT j->>'request_id' FROM t_out WHERE label = 'req1')))) AS revoked;
SELECT t_res_err('J-188: after vp_hr revokes, the next export → 403 research_not_approved', 'res1@res.test',
  format($$SELECT rpc_research_export('%s')$$, (SELECT j->>'request_id' FROM t_out WHERE label = 'req1')), 'research_not_approved', 403);
-- J-189: a DPA that ended → export refused
SELECT fn_sync_research_config(jsonb_build_object('dpas', jsonb_build_array(
  jsonb_build_object('company_id', t_u('R2'), 'researcher_email', 'res1@res.test', 'dpa_signed_on', CURRENT_DATE - 400, 'dpa_valid_until', CURRENT_DATE - 1)))) AS dpa_ended;
SELECT t_res_err('J-189: a DPA past its end date → 403 dpa_not_valid', 'res1@res.test',
  format($$SELECT rpc_research_export('%s')$$, (SELECT j->>'request_id' FROM t_out WHERE label = 'req2')), 'dpa_not_valid', 403);
SELECT t_res_err('a researcher cannot export another researcher''s request → 403 dpa_not_valid', 'res1@res.test',
  format($$SELECT rpc_research_export('%s')$$, (SELECT j->>'request_id' FROM t_out WHERE label = 'req3')), 'dpa_not_valid', 403);
SELECT t_res_err('a researcher has no employee / board access (board macro → 403)', 'res1@res.test',
  $$SELECT rpc_get_board_macro_metrics()$$, 'access_denied', 403);

-- ---------- J-191 / J-192 / J-216 method comments ----------
SELECT t_res_err('J-216: a comment under 5 characters → 400', 'res1@res.test', $$SELECT rpc_method_comment_send('abcd')$$, 'invalid_comment_length', 400);
SELECT t_res_err('J-216: a comment over 2000 characters → 400', 'res1@res.test', $$SELECT rpc_method_comment_send(repeat('א', 2001))$$, 'invalid_comment_length', 400);
INSERT INTO t_out SELECT 'c1', t_res_json('res1@res.test', $$rpc_method_comment_send('הערה על שיטת המדידה')$$);
SELECT t_assert('J-191: no recipient configured (config starts empty) → stored, nothing queued, "recipients_not_configured"; J-216 text-only notice',
  (SELECT (j->>'stored')::boolean AND (j->>'queued')::int = 0 AND j->>'delivery' = 'recipients_not_configured'
          AND j->>'warning_code' = 'text_only_no_attachments' FROM t_out WHERE label = 'c1'));
SELECT t_assert('J-216: text only — the RPC has no attachment parameter',
  pg_get_function_identity_arguments('rpc_method_comment_send(text, text)'::regprocedure) !~* '(attach|file|blob|bytea|url)');
SELECT fn_sync_method_team('{"recipients": ["team1@method.test", "team2@method.test"]}'::jsonb) AS recipients;
INSERT INTO t_out SELECT 'c2', t_res_json('res1@res.test', $$rpc_method_comment_send('הערה שנייה על השיטה')$$);
SELECT t_assert('J-191: with the configured addresses the comment is queued to each (outbox; sending is outside the DB)',
  (SELECT (j->>'queued')::int = 2 FROM t_out WHERE label = 'c2')
  AND (SELECT count(*) = 2 AND bool_and(sent_at IS NULL) FROM j_outbox WHERE kind = 'method_comment'));
SELECT t_assert('J-192: method comments are kept permanently with no author / employee column',
  NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'method_comment' AND column_name ~* '(user|person|author|researcher|employee)'));
SELECT t_err('J-192: method_comment is WORM (DELETE refused)', $$DELETE FROM method_comment$$, 'ledger_immutable');
SELECT t_assert('J-191: the outbox and the recipients are closed to clients',
  NOT has_table_privilege('authenticated', 'j_outbox', 'SELECT') AND NOT has_table_privilege('authenticated', 'j_config_recipient', 'SELECT'));

-- ---------- J-190 (DRAFT) archive ----------
SELECT t_assert('J-190: while the company is active nothing is archived', fn_archive_research_exports() = 0);
SELECT fn_sync_company_service_end(jsonb_build_object('companies', jsonb_build_array(
  jsonb_build_object('company_id', t_u('R'), 'service_ended_at', clock_timestamp() - interval '23 months')))) AS ended;
SELECT t_assert('J-190: 23 months after the end of service → still not archived', fn_archive_research_exports() = 0);
SELECT fn_sync_company_service_end(jsonb_build_object('companies', jsonb_build_array(
  jsonb_build_object('company_id', t_u('R'), 'service_ended_at', clock_timestamp() - interval '25 months')))) AS ended2;
CREATE TEMP TABLE t_arch AS SELECT fn_archive_research_exports() AS n;
SELECT t_assert('J-190 (DRAFT): ≥ 24 months after the end of service → copied to the WORM archive, nothing deleted from the log',
  (SELECT n = 2 FROM t_arch) AND (SELECT count(*) = 3 FROM research_export_log)
  AND (SELECT count(*) = 2 FROM research_export_archive) AND fn_archive_research_exports() = 0);
SELECT t_err('J-190: the archive is WORM', $$DELETE FROM research_export_archive$$, 'ledger_immutable');
SELECT t_assert('J-190: service_ended_at is set only by config / deploy (the loader is system-only, audited)',
  NOT has_function_privilege('authenticated', 'fn_sync_company_service_end(jsonb)', 'EXECUTE')
  AND (SELECT count(*) = 2 FROM access_audit_log WHERE action = 'company_service_end_set'));

SELECT 'ALL J RESEARCH TESTS PASSED' AS result;
