-- =============================================================================
-- CHR-ETRS v1.7.0 · modules/60_j_everstore_suppliers.sql — EverStore external suppliers J-211 … J-213 (Karin 16.11)
--   * external offers enter ONLY through db/config/everstore_supplier_offers.json (reviewed PR → fn_sync_supplier_offers,
--     system only; file starts EMPTY). vp_hr adds only internal items of her own company (rpc_everstore_upsert_item).
--   * J-212: on an order the supplier gets an e-mail (outbox) with the name + contact the employee gave and the benefit —
--     no organization, no golden spoons, no wellbeing data. Monthly report per organization and per benefit: order count
--     + amount payable only — no dates, no order codes, no sequence, no names.
--   * J-213: the order-screen text (fn_everstore_supplier_notice_he).
-- =============================================================================

CREATE TABLE IF NOT EXISTS everstore_supplier (
    supplier_key  text PRIMARY KEY CHECK (supplier_key ~ '^[a-z0-9_-]{2,64}$'),
    name          text NOT NULL,
    order_email   text CHECK (order_email IS NULL OR order_email ~ '^[^@\s]+@[^@\s]+$'),
    synced_at     timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE IF NOT EXISTS everstore_supplier_offer (
    item_id       varchar(64) PRIMARY KEY REFERENCES shop_item_catalog(item_id),
    supplier_key  text NOT NULL REFERENCES everstore_supplier(supplier_key)
);
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['everstore_supplier', 'everstore_supplier_offer'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format('REVOKE ALL ON TABLE %I FROM PUBLIC, anon, authenticated', t);
  END LOOP;
END $$;

-- Upsert one external offer into the catalog (provider_kind 'external_supplier', no company). Refuses to touch a
-- platform or organization item with the same id (400 item_id_taken).
CREATE OR REPLACE FUNCTION fn_sync_one_offer(p_supplier text, p_name text, o jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM shop_item_catalog c WHERE c.item_id = o->>'item_id' AND c.provider_kind <> 'external_supplier') THEN
    PERFORM fn_raise_bad_request('item_id_taken');
  END IF;
  INSERT INTO shop_item_catalog (item_id, display_name, name_he, category, provider, tier, price_coins, currency,
                                 cosmetic_only, provider_kind, company_id)
  VALUES (o->>'item_id', o->>'display_name', o->>'name_he', o->>'category', p_name,
          COALESCE(o->>'tier', 'basic')::shop_tier_enum, (o->>'price_golden_spoons')::numeric, 'golden_spoons',
          false, 'external_supplier', NULL)
  ON CONFLICT (item_id) DO UPDATE SET display_name = EXCLUDED.display_name, name_he = EXCLUDED.name_he,
    category = EXCLUDED.category, provider = EXCLUDED.provider, tier = EXCLUDED.tier,
    price_coins = EXCLUDED.price_coins;
  INSERT INTO everstore_supplier_offer (item_id, supplier_key) VALUES (o->>'item_id', p_supplier)
  ON CONFLICT (item_id) DO UPDATE SET supplier_key = EXCLUDED.supplier_key;
END;
$$;
REVOKE ALL ON FUNCTION fn_sync_one_offer(text, text, jsonb) FROM PUBLIC, anon, authenticated;

-- Load db/config/everstore_supplier_offers.json: {"suppliers": [{supplier_key, name, order_email, offers: [{item_id,
-- display_name, name_he, category, price_golden_spoons, tier}]}]}. System only. Nothing is deleted (an offer that left
-- the file stays until a reviewed manual step). Returns the number of offers written.
CREATE OR REPLACE FUNCTION fn_sync_supplier_offers(p_config jsonb)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  s   jsonb;
  o   jsonb;
  v_n int := 0;
BEGIN
  PERFORM fn_j_assert_system();
  FOR s IN SELECT jsonb_array_elements(COALESCE(p_config->'suppliers', '[]'::jsonb)) LOOP
    INSERT INTO everstore_supplier (supplier_key, name, order_email)
    VALUES (s->>'supplier_key', s->>'name', NULLIF(btrim(COALESCE(s->>'order_email', '')), ''))
    ON CONFLICT (supplier_key) DO UPDATE SET name = EXCLUDED.name, order_email = EXCLUDED.order_email,
      synced_at = clock_timestamp();
    FOR o IN SELECT jsonb_array_elements(COALESCE(s->'offers', '[]'::jsonb)) LOOP
      PERFORM fn_sync_one_offer(s->>'supplier_key', s->>'name', o);
      v_n := v_n + 1;
    END LOOP;
  END LOOP;
  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION fn_sync_supplier_offers(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION fn_sync_supplier_offers(jsonb) TO service_role;

-- J-213 (Karin 16.11) order-screen text. Karin wrote 'כמה כפיות'; the golden-spoons rule makes it 'כמה כפיות מוזהבות'
-- (J-226).
CREATE OR REPLACE FUNCTION fn_everstore_supplier_notice_he()
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$ SELECT 'הספק יודע שאת עובדת בארגון שמשלם לו, אבל לא יודע מה מצבך או כמה כפיות מוזהבות יש לך.'::text $$;

-- The order-screen text for the client.
CREATE OR REPLACE FUNCTION rpc_everstore_supplier_notice()
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$ SELECT fn_everstore_supplier_notice_he() $$;
GRANT EXECUTE ON FUNCTION rpc_everstore_supplier_notice() TO authenticated;

-- The supplier e-mail payload of one order: the name + contact the employee gave + the benefit. Nothing else.
CREATE OR REPLACE FUNCTION fn_supplier_order_payload(p_user uuid, p_item varchar)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT jsonb_build_object('employee_name', u.full_name, 'employee_contact', u.email, 'benefit_name_he', c.name_he)
    FROM users u, shop_item_catalog c WHERE u.user_id = p_user AND c.item_id = p_item
$$;
REVOKE ALL ON FUNCTION fn_supplier_order_payload(uuid, varchar) FROM PUBLIC, anon, authenticated;

-- AFTER INSERT on shop_purchase: an order of an external offer queues the supplier e-mail (when the supplier has an
-- order address in config; otherwise nothing is queued).
CREATE OR REPLACE FUNCTION fn_supplier_order_notify()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  s everstore_supplier;
BEGIN
  SELECT x.* INTO s FROM everstore_supplier x JOIN everstore_supplier_offer o ON o.supplier_key = x.supplier_key
   WHERE o.item_id = NEW.item_id;
  IF s.order_email IS NOT NULL THEN
    PERFORM fn_j_outbox_put(NULL, 'supplier_order', s.order_email, 'הזמנה חדשה',
                            fn_supplier_order_payload(NEW.user_id, NEW.item_id), 'supplier_order:' || NEW.purchase_id);
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_supplier_order_notify ON shop_purchase;
CREATE TRIGGER trg_supplier_order_notify AFTER INSERT ON shop_purchase
    FOR EACH ROW EXECUTE FUNCTION fn_supplier_order_notify();

-- J-212 monthly report of one supplier for one month: per organization and per benefit, the order count and the
-- amount payable (golden spoons; the ILS value per golden spoon: לא הוגדר). No dates, codes, sequence or names.
CREATE OR REPLACE FUNCTION fn_supplier_monthly_rows(p_supplier text, p_month date)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('organization', x.org, 'benefit_item_id', x.item_id,
                                               'order_count', x.n, 'amount_payable_golden_spoons', x.amt)
                            ORDER BY x.org, x.item_id), '[]'::jsonb)
    FROM (SELECT co.company_name::text AS org, p.item_id, count(*) AS n, sum(p.price_golden_spoons) AS amt
            FROM shop_purchase p
            JOIN everstore_supplier_offer o ON o.item_id = p.item_id AND o.supplier_key = p_supplier
            JOIN users u ON u.user_id = p.user_id JOIN companies co ON co.company_id = u.company_id
           WHERE date_trunc('month', fn_agent_local_ts(co.company_id, p.purchased_at))::date = date_trunc('month', p_month)::date
           GROUP BY co.company_name, p.item_id) x
$$;
REVOKE ALL ON FUNCTION fn_supplier_monthly_rows(text, date) FROM PUBLIC, anon, authenticated;

-- System job: build a supplier's monthly report and queue it (idempotent per supplier + month). Returns the report.
CREATE OR REPLACE FUNCTION fn_supplier_monthly_report(p_supplier text, p_month date)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_rows jsonb;
  v_to   text := (SELECT s.order_email FROM everstore_supplier s WHERE s.supplier_key = p_supplier);
BEGIN
  PERFORM fn_j_assert_system();
  v_rows := fn_supplier_monthly_rows(p_supplier, p_month);
  IF v_to IS NOT NULL THEN
    PERFORM fn_j_outbox_put(NULL, 'supplier_monthly_report', v_to, 'דוח חודשי',
                            jsonb_build_object('month', to_char(p_month, 'YYYY-MM'), 'rows', v_rows,
                                               'ils_per_golden_spoon', fn_j_not_defined_he()),
                            'supplier_report:' || p_supplier || ':' || to_char(p_month, 'YYYY-MM'));
  END IF;
  RETURN jsonb_build_object('month', to_char(p_month, 'YYYY-MM'), 'rows', v_rows);
END;
$$;
REVOKE ALL ON FUNCTION fn_supplier_monthly_report(text, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION fn_supplier_monthly_report(text, date) TO service_role;
