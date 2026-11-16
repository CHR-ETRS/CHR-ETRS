-- =============================================================================
-- CHR-ETRS v1.7.0 · modules/70_j_leaver_nonprofit.sql — the leaver's golden spoons go to a nonprofit J-196 / J-197
-- (Karin 16.11). On day 31 the remaining golden spoons balance is DONATED (rpc_expire_departed_golden_spoons):
--   (1) balance + nonprofit (her choice, else the company default J-197), (2) the donation is recorded,
--   (3) only then the balance is zeroed and the personal data may be shredded (rpc_run_scheduled_crypto_shred waits).
-- v1.7.0 fixes (Karin 16.11, J-241, replaces J-223): no choice and no company default → the balance is zeroed with a
-- record 'לא נתרם — אין עמותה', vp_hr gets a "set a default nonprofit" reminder (outbox) and the shred goes on.
-- v1.7.0 fixes 2 (Karin 16.11 21:04–21:07, J-249 / J-250): exact title + body; no active vp_hr with an e-mail → cfo;
-- none → the CHR-ETRS operator ("בחברה X אין vp_hr פעילה", no employee data).
-- Reminders on the leaving day and one week before day 30 (balance, deadline, nonprofit, change link) → outbox.
-- The company transfers ONE monthly aggregate per nonprofit — no names, no leaving dates.
-- Legal donor for receipts: TODO לא הוגדר (accountant). ILS value of a golden spoon: לא הוגדר.
-- =============================================================================

CREATE TABLE IF NOT EXISTS nonprofit (
    nonprofit_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id         uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    name_he            text NOT NULL CHECK (length(btrim(name_he)) BETWEEN 1 AND 200),
    is_company_default boolean NOT NULL DEFAULT false,
    created_at         timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (company_id, name_he)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_nonprofit_one_default ON nonprofit (company_id) WHERE is_company_default;

CREATE TABLE IF NOT EXISTS leaver_nonprofit_choice (
    user_id      uuid PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
    nonprofit_id uuid NOT NULL REFERENCES nonprofit(nonprofit_id),
    chosen_at    timestamptz NOT NULL DEFAULT clock_timestamp()
);

-- Monthly aggregate per company + nonprofit (no person, no date finer than the month).
CREATE TABLE IF NOT EXISTS nonprofit_donation_month (
    company_id    uuid NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    nonprofit_id  uuid NOT NULL REFERENCES nonprofit(nonprofit_id),
    month         date NOT NULL CHECK (month = date_trunc('month', month)::date),
    golden_spoons numeric(12, 1) NOT NULL DEFAULT 0 CHECK (golden_spoons >= 0),
    PRIMARY KEY (company_id, nonprofit_id, month)
);

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['nonprofit', 'leaver_nonprofit_choice', 'nonprofit_donation_month'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format('REVOKE ALL ON TABLE %I FROM PUBLIC, anon, authenticated', t);
  END LOOP;
END $$;
-- The monthly aggregate only grows (no delete, no decrease).
CREATE OR REPLACE FUNCTION fn_donation_month_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'DELETE' OR NEW.golden_spoons < OLD.golden_spoons THEN
    PERFORM fn_raise_business('ledger_immutable');
  END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;
DROP TRIGGER IF EXISTS trg_donation_month_guard ON nonprofit_donation_month;
CREATE TRIGGER trg_donation_month_guard BEFORE UPDATE OR DELETE ON nonprofit_donation_month
    FOR EACH ROW EXECUTE FUNCTION fn_donation_month_guard();

-- vp_hr adds a nonprofit of her company; p_is_default = the company default (J-197; replaces the previous default).
CREATE OR REPLACE FUNCTION rpc_put_nonprofit(p_name_he text, p_is_default boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_comp uuid := fn_my_company();
  v_id   uuid;
BEGIN
  PERFORM fn_assert_vp_hr(v_comp);
  IF NOT fn_j_text_ok(p_name_he, 1, 200) THEN
    PERFORM fn_raise_bad_request('invalid_nonprofit');
  END IF;
  IF COALESCE(p_is_default, false) THEN
    UPDATE nonprofit SET is_company_default = false WHERE company_id = v_comp AND is_company_default;
  END IF;
  INSERT INTO nonprofit (company_id, name_he, is_company_default)
  VALUES (v_comp, btrim(p_name_he), COALESCE(p_is_default, false))
  ON CONFLICT (company_id, name_he) DO UPDATE SET is_company_default = EXCLUDED.is_company_default
  RETURNING nonprofit_id INTO v_id;
  PERFORM fn_audit_view('nonprofit_put', jsonb_build_object('nonprofit_id', v_id, 'is_default', p_is_default));
  RETURN jsonb_build_object('nonprofit_id', v_id, 'name_he', btrim(p_name_he), 'is_default', COALESCE(p_is_default, false));
END;
$$;

-- The nonprofits of the caller's company (an employee / leaver picks from this list).
CREATE OR REPLACE FUNCTION rpc_list_nonprofits()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('nonprofit_id', n.nonprofit_id, 'name_he', n.name_he,
                                               'is_default', n.is_company_default) ORDER BY n.name_he), '[]'::jsonb)
    FROM nonprofit n WHERE n.company_id = fn_user_company(auth.uid())
$$;

-- The employee (or a leaver inside her 30-day window) chooses the nonprofit of her own company.
CREATE OR REPLACE FUNCTION rpc_choose_my_nonprofit(p_nonprofit_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR NOT (fn_has_employee_profile(v_uid) OR fn_in_exit_redemption_window(v_uid)) THEN
    PERFORM fn_raise_business('access_denied');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM nonprofit n WHERE n.nonprofit_id = p_nonprofit_id
                    AND n.company_id = fn_user_company(v_uid)) THEN
    PERFORM fn_raise_bad_request('invalid_nonprofit');
  END IF;
  INSERT INTO leaver_nonprofit_choice (user_id, nonprofit_id) VALUES (v_uid, p_nonprofit_id)
  ON CONFLICT (user_id) DO UPDATE SET nonprofit_id = EXCLUDED.nonprofit_id, chosen_at = clock_timestamp();
  RETURN jsonb_build_object('nonprofit_id', p_nonprofit_id);
END;
$$;

-- The nonprofit of a leaver: her choice, else the company default; NULL when neither exists.
CREATE OR REPLACE FUNCTION fn_leaver_nonprofit(p_user uuid, p_company uuid)
RETURNS nonprofit
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT n.* FROM nonprofit n
   WHERE n.company_id = p_company
     AND (n.nonprofit_id = (SELECT c.nonprofit_id FROM leaver_nonprofit_choice c WHERE c.user_id = p_user)
          OR (n.is_company_default
              AND NOT EXISTS (SELECT 1 FROM leaver_nonprofit_choice c JOIN nonprofit x ON x.nonprofit_id = c.nonprofit_id
                               WHERE c.user_id = p_user AND x.company_id = p_company)))
   ORDER BY n.is_company_default LIMIT 1
$$;

-- Steps (1) + (2) of J-196 for one leaver (called by rpc_expire_departed_golden_spoons, which zeroes the balance only
-- when this returns true): resolve the nonprofit, record the donation in golden_spoons_ledger ('donated_after_exit')
-- and add it to the month's aggregate. No nonprofit → false (fn_j196_settle_departed then zeroes, J-241).
CREATE OR REPLACE FUNCTION fn_j196_donate_departed(p_user uuid, p_company uuid, p_amount numeric, p_deadline date,
                                                   p_now timestamptz)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  n     nonprofit := fn_leaver_nonprofit(p_user, p_company);
  v_row uuid;
BEGIN
  IF n.nonprofit_id IS NULL OR p_amount IS NULL OR p_amount <= 0 THEN
    RETURN false;
  END IF;
  INSERT INTO golden_spoons_ledger (user_id, company_id, event_type, amount, exit_deadline)
  VALUES (p_user, p_company, 'donated_after_exit', p_amount, p_deadline)
  ON CONFLICT (user_id, event_type, exit_deadline) DO NOTHING
  RETURNING entry_id INTO v_row;
  IF v_row IS NOT NULL THEN
    INSERT INTO nonprofit_donation_month (company_id, nonprofit_id, month, golden_spoons)
    VALUES (p_company, n.nonprofit_id, date_trunc('month', fn_agent_local_ts(p_company, p_now))::date, p_amount)
    ON CONFLICT (company_id, nonprofit_id, month)
      DO UPDATE SET golden_spoons = nonprofit_donation_month.golden_spoons + EXCLUDED.golden_spoons;
  END IF;
  RETURN true;
END;
$$;

-- J-241: the record text when a leaver's balance is zeroed because there is no nonprofit (Karin's wording).
CREATE OR REPLACE FUNCTION fn_j196_no_nonprofit_note_he()
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$ SELECT 'לא נתרם — אין עמותה'::text $$;

-- J-249 (Karin 16.11): the reminder title, exactly.
CREATE OR REPLACE FUNCTION fn_j196_default_reminder_title_he()
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$ SELECT 'יש להגדיר עמותת ברירת מחדל'::text $$;

-- J-249 (Karin 16.11): the reminder body, exactly.
CREATE OR REPLACE FUNCTION fn_j196_default_reminder_body_he()
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$ SELECT 'בלי עמותת ברירת מחדל, הכפיות המוזהבות של עובדים שעוזבים ולא בחרו עמותה מתאפסות ולא נתרמות.'::text $$;

-- J-249: the reminder payload — title, body, link ('לא הוגדר'); no leaver, no amount, no id.
CREATE OR REPLACE FUNCTION fn_j196_default_reminder_payload()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$ SELECT jsonb_build_object('title_he', fn_j196_default_reminder_title_he(),
                                'body_he', fn_j196_default_reminder_body_he(), 'link', fn_j_not_defined_he()) $$;

-- J-250: who gets the reminder — 'vp_hr' (an active vp_hr with an e-mail), else 'cfo' (an active cfo with an e-mail),
-- else 'operator' (the CHR-ETRS operator).
CREATE OR REPLACE FUNCTION fn_j196_reminder_level(p_company uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT CASE WHEN EXISTS (SELECT 1 FROM fn_j_company_role_addresses(p_company, 'vp_hr')) THEN 'vp_hr'
              WHEN EXISTS (SELECT 1 FROM fn_j_company_role_addresses(p_company, 'cfo')) THEN 'cfo'
              ELSE 'operator' END
$$;

-- J-241 / J-250: queue the "set a default nonprofit" reminder (existing outbox) to every active vp_hr of the company
-- with an e-mail; none → every active cfo with an e-mail; none → the CHR-ETRS operator gets only
-- "בחברה X אין vp_hr פעילה" (fn_j_notify_operator_no_vp_hr). One per recipient per company day.
-- Returns the number queued now.
CREATE OR REPLACE FUNCTION fn_j196_remind_default_nonprofit(p_company uuid, p_now timestamptz)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_level text := fn_j196_reminder_level(p_company);
  a       text;
  v_n     int := 0;
BEGIN
  IF v_level = 'operator' THEN
    RETURN fn_j_notify_operator_no_vp_hr(p_company, p_now);
  END IF;
  FOR a IN SELECT fn_j_company_role_addresses(p_company, v_level) LOOP
    IF fn_j_outbox_put(p_company, 'default_nonprofit_reminder', a, fn_j196_default_reminder_title_he(),
                       fn_j196_default_reminder_payload(),
                       'default_nonprofit:' || p_company || ':' || v_level || ':' || a || ':'
                         || fn_j_company_today(p_company, p_now)) THEN
      v_n := v_n + 1;
    END IF;
  END LOOP;
  RETURN v_n;
END;
$$;
-- J-250: the earlier vp_hr-only form is replaced by fn_j196_remind_default_nonprofit.
DROP FUNCTION IF EXISTS fn_j196_remind_vp_hr_default(uuid, timestamptz);

-- J-241: no nonprofit for this leaver → record the zeroing in golden_spoons_ledger ('zeroed_no_nonprofit',
-- note 'לא נתרם — אין עמותה'; nothing goes to the monthly donation aggregate) and remind (J-250 chain). Returns true.
CREATE OR REPLACE FUNCTION fn_j196_zero_no_nonprofit(p_user uuid, p_company uuid, p_amount numeric, p_deadline date,
                                                     p_now timestamptz)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  INSERT INTO golden_spoons_ledger (user_id, company_id, event_type, amount, exit_deadline, note_he)
  VALUES (p_user, p_company, 'zeroed_no_nonprofit', p_amount, p_deadline, fn_j196_no_nonprofit_note_he())
  ON CONFLICT (user_id, event_type, exit_deadline) DO NOTHING;
  PERFORM fn_j196_remind_default_nonprofit(p_company, p_now);
  RETURN true;
END;
$$;

-- Day 31 for one leaver (called by rpc_expire_departed_golden_spoons, which zeroes the balance when this returns
-- true): donate to her nonprofit (J-196 / J-197); without any nonprofit, record the zeroing and remind vp_hr (J-241).
CREATE OR REPLACE FUNCTION fn_j196_settle_departed(p_user uuid, p_company uuid, p_amount numeric, p_deadline date,
                                                   p_now timestamptz)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RETURN false;
  END IF;
  RETURN fn_j196_donate_departed(p_user, p_company, p_amount, p_deadline, p_now)
      OR fn_j196_zero_no_nonprofit(p_user, p_company, p_amount, p_deadline, p_now);
END;
$$;

-- The reminder payload: balance, deadline, nonprofit name, change link (the app route: לא הוגדר).
CREATE OR REPLACE FUNCTION fn_leaver_reminder_payload(p_user uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT jsonb_build_object('golden_spoons_balance', a.golden_spoons,
                            'deadline', fn_exit_redemption_deadline(u.user_id),
                            'nonprofit_he', COALESCE((fn_leaver_nonprofit(u.user_id, u.company_id)).name_he,
                                                     fn_j_not_defined_he()),
                            'change_link', fn_j_not_defined_he())
    FROM users u JOIN avatar_state a ON a.user_id = u.user_id WHERE u.user_id = p_user
$$;

-- System job (daily): queue the leaver reminders — on the leaving day and one week before day 30 — for every leaver
-- with a golden spoons balance > 0 (idempotent per leaver + reminder). Returns the number queued now.
CREATE OR REPLACE FUNCTION rpc_queue_leaver_reminders(p_now timestamptz DEFAULT NULL)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_now timestamptz := COALESCE(p_now, clock_timestamp());
  r     record;
  v_n   int := 0;
BEGIN
  PERFORM fn_j_assert_system();
  FOR r IN
    SELECT u.user_id, u.company_id, u.email,
           CASE WHEN fn_j_company_today(u.company_id, v_now) = fn_agent_local_ts(u.company_id, u.employment_ended_at)::date
                THEN 'leaving_day'
                WHEN fn_j_company_today(u.company_id, v_now) = fn_exit_redemption_deadline(u.user_id) - 7
                THEN 'week_before_day_30' END AS which
      FROM users u JOIN avatar_state a ON a.user_id = u.user_id
     WHERE u.employment_ended_at IS NOT NULL AND a.golden_spoons > 0
  LOOP
    IF r.which IS NOT NULL AND fn_j_outbox_put(r.company_id, 'leaver_donation_reminder', r.email,
                                               'יתרת הכפיות המוזהבות שלך', fn_leaver_reminder_payload(r.user_id),
                                               'leaver_reminder:' || r.user_id || ':' || r.which) THEN
      v_n := v_n + 1;
    END IF;
  END LOOP;
  RETURN v_n;
END;
$$;

-- vp_hr / cfo: the month's transfer per nonprofit (aggregate only — no names, no leaving dates, no counts).
CREATE OR REPLACE FUNCTION rpc_get_nonprofit_monthly_transfer(p_company_id uuid, p_month date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  PERFORM fn_assert_finance_viewer(p_company_id);
  RETURN jsonb_build_object('month', to_char(p_month, 'YYYY-MM'), 'legal_donor', 'TODO לא הוגדר',
    'ils_per_golden_spoon', fn_j_not_defined_he(),
    'rows', COALESCE((SELECT jsonb_agg(jsonb_build_object('nonprofit_he', n.name_he, 'golden_spoons', m.golden_spoons)
                                       ORDER BY n.name_he)
                        FROM nonprofit_donation_month m JOIN nonprofit n ON n.nonprofit_id = m.nonprofit_id
                       WHERE m.company_id = p_company_id AND m.month = date_trunc('month', p_month)::date), '[]'::jsonb));
END;
$$;

REVOKE ALL ON FUNCTION rpc_put_nonprofit(text, boolean), rpc_list_nonprofits(), rpc_choose_my_nonprofit(uuid),
  rpc_get_nonprofit_monthly_transfer(uuid, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_put_nonprofit(text, boolean), rpc_list_nonprofits(), rpc_choose_my_nonprofit(uuid),
  rpc_get_nonprofit_monthly_transfer(uuid, date) TO authenticated;
REVOKE ALL ON FUNCTION rpc_queue_leaver_reminders(timestamptz), fn_j196_donate_departed(uuid, uuid, numeric, date, timestamptz),
  fn_leaver_nonprofit(uuid, uuid), fn_leaver_reminder_payload(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION fn_j196_remind_default_nonprofit(uuid, timestamptz), fn_j196_reminder_level(uuid),
  fn_j196_default_reminder_payload(),
  fn_j196_zero_no_nonprofit(uuid, uuid, numeric, date, timestamptz),
  fn_j196_settle_departed(uuid, uuid, numeric, date, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION rpc_queue_leaver_reminders(timestamptz) TO service_role;
