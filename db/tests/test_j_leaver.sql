-- =============================================================================
-- CHR-ETRS v1.7.0 · tests/test_j_leaver.sql — leaver golden spoons → nonprofit J-196 / J-197 (Karin 16.11)
-- Order on day 31: balance + nonprofit (her choice, else the company default) → record → only then the shred.
-- Real clock: leaving dates are relative to now; the jobs take p_now.
-- =============================================================================
\ir j_helpers.sql

SELECT t_company('A') IS NOT NULL AS a, t_company('B') IS NOT NULL AS b;
DO $$
BEGIN
  PERFORM t_mk('hrA', 'A', 'vp_hr', 'vp', 'Mgmt'); PERFORM t_mk('cfoA', 'A', 'cfo', 'vp', 'Mgmt'); PERFORM t_mk('hrB', 'B', 'vp_hr', 'vp', 'Mgmt');
  PERFORM t_mk('stay', 'A');
  PERFORM t_mk('chooser', 'A');      -- leaves 5 days ago, chooses a nonprofit
  PERFORM t_mk('nochoice', 'A');     -- leaves 40 days ago, never chooses (company default)
  PERFORM t_mk('today', 'A');        -- leaves today
  PERFORM t_mk('week', 'A');         -- day 30 is 7 days from today
  PERFORM t_mk('zero', 'A');         -- leaves today with balance 0
  PERFORM t_mk('lb', 'B');           -- company B, 40 days ago, B has no nonprofit at all
  INSERT INTO avatar_state (user_id, golden_spoons)
  SELECT t_u(k), v FROM (VALUES ('chooser', 12.5), ('nochoice', 20), ('today', 7), ('week', 9), ('zero', 0), ('lb', 15), ('stay', 50)) x(k, v)
  ON CONFLICT (user_id) DO UPDATE SET golden_spoons = EXCLUDED.golden_spoons;
END $$;
UPDATE users SET employment_ended_at = clock_timestamp() - interval '5 days' WHERE user_id = t_u('chooser');
UPDATE users SET employment_ended_at = clock_timestamp() - interval '40 days' WHERE user_id IN (t_u('nochoice'), t_u('lb'));
UPDATE users SET employment_ended_at = clock_timestamp() WHERE user_id IN (t_u('today'), t_u('zero'));
UPDATE users SET employment_ended_at = clock_timestamp() - interval '23 days' WHERE user_id = t_u('week');

-- ---------- J-197 nonprofits ----------
SELECT t_err_as('J-197: only vp_hr adds a nonprofit (cfo → 403)', 'cfoA', $$SELECT rpc_put_nonprofit('עמותה')$$, 'insufficient_privilege', 403);
CREATE TEMP TABLE t_np AS SELECT 'def' AS k, t_json_as('hrA', $$rpc_put_nonprofit('עמותת ברירת המחדל', true)$$) AS j;
INSERT INTO t_np SELECT 'other', t_json_as('hrA', $$rpc_put_nonprofit('עמותה לבחירה', false)$$);
INSERT INTO t_np SELECT 'bnp', t_json_as('hrB', $$rpc_put_nonprofit('עמותה של B', false)$$);
SELECT t_assert('J-197: one company default per company; the list shows only her company''s nonprofits',
  (SELECT count(*) = 1 FROM nonprofit WHERE company_id = t_u('A') AND is_company_default)
  AND jsonb_array_length(t_json_as('stay', $$rpc_list_nonprofits()$$)) = 2);
SELECT t_err_as('J-197: choosing another company''s nonprofit → 400', 'chooser',
  format($$SELECT rpc_choose_my_nonprofit('%s')$$, (SELECT j->>'nonprofit_id' FROM t_np WHERE k = 'bnp')), 'invalid_nonprofit', 400);
SELECT jsonb_typeof(t_json_as('chooser', format($$rpc_choose_my_nonprofit('%s')$$, (SELECT j->>'nonprofit_id' FROM t_np WHERE k = 'other')))) AS chosen;
SELECT t_err_as('J-197: after the 30-day window a leaver cannot choose any more → 403', 'nochoice',
  format($$SELECT rpc_choose_my_nonprofit('%s')$$, (SELECT j->>'nonprofit_id' FROM t_np WHERE k = 'other')), 'access_denied', 403);
SELECT t_assert('J-197: the nonprofit = her choice, else the company default, else none',
  (fn_leaver_nonprofit(t_u('chooser'), t_u('A'))).name_he = 'עמותה לבחירה'
  AND (fn_leaver_nonprofit(t_u('nochoice'), t_u('A'))).name_he = 'עמותת ברירת המחדל'
  AND (fn_leaver_nonprofit(t_u('lb'), t_u('B'))).nonprofit_id IS NULL);

-- ---------- J-196 reminders ----------
SELECT t_assert('J-196: the reminder job is system-only', NOT has_function_privilege('authenticated', 'rpc_queue_leaver_reminders(timestamptz)', 'EXECUTE'));
CREATE TEMP TABLE t_rem AS SELECT rpc_queue_leaver_reminders(clock_timestamp()) AS n;
SELECT t_assert('J-196: reminders today = the leaving day (today) + one week before day 30 (week); not for a 0 balance',
  (SELECT n = 2 FROM t_rem)
  AND (SELECT array_agg(recipient_address ORDER BY recipient_address) = ARRAY['today@j.test', 'week@j.test'] FROM j_outbox WHERE kind = 'leaver_donation_reminder'));
SELECT t_assert('J-196: reminders are idempotent (second run queues nothing)', rpc_queue_leaver_reminders(clock_timestamp()) = 0);
SELECT t_assert('J-196: the reminder = balance, deadline, nonprofit, change link (לא הוגדר) — and nothing about anyone else',
  (SELECT bool_and((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(payload) k) = ARRAY['change_link', 'deadline', 'golden_spoons_balance', 'nonprofit_he']
                   AND payload->>'change_link' = 'לא הוגדר' AND t_free_of(payload, t_all_user_ids()))
     FROM j_outbox WHERE kind = 'leaver_donation_reminder')
  AND (SELECT (payload->>'golden_spoons_balance')::numeric = 7 AND payload->>'nonprofit_he' = 'עמותת ברירת המחדל'
         FROM j_outbox WHERE recipient_address = 'today@j.test'));
SELECT t_assert('J-196: the subject uses the golden-spoons wording', (SELECT bool_and(subject_he = 'יתרת הכפיות המוזהבות שלך') FROM j_outbox WHERE kind = 'leaver_donation_reminder'));

-- ---------- J-196 day 31 ----------
CREATE TEMP TABLE t_don AS SELECT rpc_expire_departed_golden_spoons(clock_timestamp()) AS n;
SELECT t_assert('J-196 / J-241: day 31 — nochoice (40 days, default nonprofit) is donated; lb (no choice, company B without a default) is zeroed; chooser is still in her window',
  (SELECT n = 2 FROM t_don)
  AND (SELECT golden_spoons = 0 FROM avatar_state WHERE user_id = t_u('nochoice'))
  AND (SELECT golden_spoons = 0 FROM avatar_state WHERE user_id = t_u('lb'))
  AND (SELECT golden_spoons = 12.5 FROM avatar_state WHERE user_id = t_u('chooser')));
SELECT t_assert('J-196: the donation is recorded (WORM ledger donated_after_exit) and in the month''s aggregate per nonprofit — never a reset row',
  (SELECT count(*) = 1 AND sum(amount) = 20 FROM golden_spoons_ledger WHERE event_type = 'donated_after_exit' AND note_he IS NULL)
  AND NOT EXISTS (SELECT 1 FROM golden_spoons_ledger WHERE event_type = 'expired_after_exit')
  AND (SELECT golden_spoons = 20 FROM nonprofit_donation_month m JOIN nonprofit n USING (nonprofit_id) WHERE n.name_he = 'עמותת ברירת המחדל'));
SELECT t_assert('J-241: the zeroing is recorded — ledger zeroed_no_nonprofit (15, "לא נתרם — אין עמותה"), nothing in B''s donation aggregate',
  (SELECT count(*) = 1 AND sum(amount) = 15 AND min(note_he) = 'לא נתרם — אין עמותה'
     FROM golden_spoons_ledger WHERE user_id = t_u('lb') AND event_type = 'zeroed_no_nonprofit')
  AND NOT EXISTS (SELECT 1 FROM nonprofit_donation_month WHERE company_id = t_u('B')));
SELECT t_assert('J-241: vp_hr of company B gets ONE "set a default nonprofit" reminder (outbox) — no leaver, no amount, no id in it',
  (SELECT count(*) = 1 AND min(recipient_address) = 'hrB@j.test' AND min(subject_he) = 'יש להגדיר עמותת ברירת מחדל'
     FROM j_outbox WHERE kind = 'default_nonprofit_reminder')
  AND (SELECT (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(payload) k) = ARRAY['action_he', 'reason_he', 'settings_link']
              AND payload->>'reason_he' = 'לא נתרם — אין עמותה' AND payload->>'settings_link' = 'לא הוגדר'
              AND t_free_of(payload, t_all_user_ids())
         FROM j_outbox WHERE kind = 'default_nonprofit_reminder')
  AND NOT EXISTS (SELECT 1 FROM j_outbox WHERE kind = 'default_nonprofit_reminder' AND company_id = t_u('A')));
SELECT t_err('J-241: the zeroing record is WORM', $$UPDATE golden_spoons_ledger SET note_he = NULL WHERE event_type = 'zeroed_no_nonprofit'$$, 'ledger_immutable');
-- the chooser's day 31 (job run with p_now 26 days ahead)
CREATE TEMP TABLE t_don2 AS SELECT rpc_expire_departed_golden_spoons(clock_timestamp() + interval '27 days') AS n;
SELECT t_assert('J-196: the chooser''s balance goes to HER nonprofit (not the default)',
  (SELECT n >= 1 FROM t_don2)
  AND (SELECT golden_spoons = 12.5 FROM nonprofit_donation_month m JOIN nonprofit n USING (nonprofit_id) WHERE n.name_he = 'עמותה לבחירה'
                                                                                          AND m.month = date_trunc('month', (clock_timestamp() + interval '27 days') AT TIME ZONE 'Asia/Jerusalem')::date));
SELECT t_assert('J-196: re-running donates nothing twice', rpc_expire_departed_golden_spoons(clock_timestamp() + interval '27 days') = 0);
SELECT t_err('J-196: the monthly aggregate only grows (decrease refused)', $$UPDATE nonprofit_donation_month SET golden_spoons = 0$$, 'ledger_immutable');
SELECT t_err('J-196: the monthly aggregate is never deleted', $$DELETE FROM nonprofit_donation_month$$, 'ledger_immutable');

-- ---------- shred waits for the donation ----------
UPDATE users SET employment_ended_at = clock_timestamp() - interval '45 days' WHERE user_id = t_u('stay');
SELECT rpc_run_scheduled_crypto_shred() AS shredded;
SELECT t_assert('J-196 order: a leaver whose balance was not settled yet (stay, not yet day-31-processed) is NOT shredded',
  NOT EXISTS (SELECT 1 FROM pseudonym_key WHERE user_id = t_u('stay') AND shredded_at IS NOT NULL));
SELECT t_assert('J-241: the leaver in a company without a nonprofit (lb) is shredded as usual after the day-31 zeroing',
  EXISTS (SELECT 1 FROM pseudonym_key WHERE user_id = t_u('lb'))
  AND NOT EXISTS (SELECT 1 FROM pseudonym_key WHERE user_id = t_u('lb') AND shredded_at IS NULL));
SELECT t_assert('J-196 order: a leaver whose balance was donated (nochoice) is shredded by the same job',
  NOT EXISTS (SELECT 1 FROM pseudonym_key WHERE user_id = t_u('nochoice') AND shredded_at IS NULL));

-- ---------- monthly transfer report ----------
CREATE TEMP TABLE t_tr AS SELECT t_json_as('cfoA', format($$rpc_get_nonprofit_monthly_transfer('%s', CURRENT_DATE)$$, t_u('A'))) AS j;
SELECT t_assert('J-196: the cfo sees the month''s transfer per nonprofit only (name + golden spoons), legal donor "TODO לא הוגדר"',
  (SELECT j->>'legal_donor' = 'TODO לא הוגדר' AND j->>'ils_per_golden_spoon' = 'לא הוגדר'
          AND jsonb_array_length(j->'rows') >= 1
          AND (SELECT bool_and((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(r) k) = ARRAY['golden_spoons', 'nonprofit_he']) FROM jsonb_array_elements(j->'rows') r)
          AND t_free_of(j, t_all_user_ids()) FROM t_tr));
SELECT t_err_as('J-196: an employee cannot read the transfer report → 403', 'stay',
  format($$SELECT rpc_get_nonprofit_monthly_transfer('%s', CURRENT_DATE)$$, t_u('A')), 'insufficient_privilege', 403);
SELECT t_assert('J-196: nonprofit tables are closed to clients',
  NOT has_table_privilege('authenticated', 'nonprofit', 'SELECT') AND NOT has_table_privilege('authenticated', 'nonprofit_donation_month', 'SELECT'));

SELECT 'ALL J LEAVER TESTS PASSED' AS result;
