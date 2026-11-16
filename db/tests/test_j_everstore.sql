-- =============================================================================
-- CHR-ETRS v1.7.0 · tests/test_j_everstore.sql — EverStore suppliers J-211 … J-213 (Karin 16.11)
-- =============================================================================
\ir j_helpers.sql

SELECT t_company('A') IS NOT NULL AS a, t_company('B') IS NOT NULL AS b;
DO $$
BEGIN
  PERFORM t_mk('hrA', 'A', 'vp_hr', 'vp', 'Mgmt'); PERFORM t_mk('hrB', 'B', 'vp_hr', 'vp', 'Mgmt');
  PERFORM t_mk('cfoA', 'A', 'cfo', 'vp', 'Mgmt');
  PERFORM t_mk('ea', 'A'); PERFORM t_mk('eb', 'B'); PERFORM t_mk('eb2', 'B');
  INSERT INTO avatar_state (user_id, golden_spoons) VALUES (t_u('ea'), 100), (t_u('eb'), 100), (t_u('eb2'), 100)
  ON CONFLICT (user_id) DO UPDATE SET golden_spoons = EXCLUDED.golden_spoons;
END $$;

-- ---------- J-211 catalog ownership ----------
SELECT t_assert('J-211: the catalog carries company_id + provider_kind (platform / organization / external_supplier)',
  EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'shop_item_catalog' AND column_name = 'company_id')
  AND (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'chk_shop_item_provider_kind') ~ 'external_supplier');
SELECT t_err_as('J-211: vp_hr cannot add an external supplier item (provider ≠ her organization) → 403 supplier_item_config_only', 'hrA',
  $$SELECT rpc_everstore_upsert_item('spa_x', 'Spa', 'ספא', 'health_wellbeing', 20, 'custom', false, 'WellSpa')$$, 'supplier_item_config_only', 403);
SELECT t_err_as('J-211: a cfo cannot add items → 403', 'cfoA',
  $$SELECT rpc_everstore_upsert_item('own_a', 'Own', 'פריט', 'merchandise', 5)$$, 'access_denied', 403);
SELECT (t_json_as('hrA', $$rpc_everstore_upsert_item('own_a', 'Own A', 'פריט של A', 'merchandise', 5)$$))->>'provider_kind' AS own_a;
SELECT t_assert('J-211: an internal item belongs to her company: provider = organization name, provider_kind organization',
  (SELECT provider = 'Company A' AND provider_kind = 'organization' AND company_id = t_u('A') FROM shop_item_catalog WHERE item_id = 'own_a'));
SELECT t_err_as('J-211: vp_hr of company B cannot edit company A''s item → 403', 'hrB',
  $$SELECT rpc_everstore_upsert_item('own_a', 'Hijack', 'חטיפה', 'merchandise', 1)$$, 'access_denied', 403);
SELECT t_assert('J-211: company B employees do not see company A''s internal item; company A employees do',
  t_json_as('eb', $$(SELECT count(*) FROM shop_item_catalog WHERE item_id = 'own_a')$$) = '0'::jsonb
  AND t_json_as('ea', $$(SELECT count(*) FROM shop_item_catalog WHERE item_id = 'own_a')$$) = '1'::jsonb);
SELECT t_err_as('J-211: company B cannot buy company A''s internal item', 'eb',
  $$SELECT rpc_everstore_purchase('own_a', 'k-own-b')$$, 'anti_get_blocked', 403);

-- ---------- external offers: config only ----------
SELECT t_assert('J-211: the supplier config loader is system-only', NOT has_function_privilege('authenticated', 'fn_sync_supplier_offers(jsonb)', 'EXECUTE'));
SELECT t_err_as('J-211: a vp_hr cannot load supplier offers → 42501', 'hrA', $$SELECT fn_sync_supplier_offers('{}')$$, '42501');
SELECT fn_sync_supplier_offers('{"suppliers": [{"supplier_key": "wellspa", "name": "WellSpa", "order_email": "orders@wellspa.test",
  "offers": [{"item_id": "wellspa_massage", "display_name": "Massage", "name_he": "עיסוי", "category": "health_wellbeing",
              "price_golden_spoons": 30, "tier": "premium"}]}]}'::jsonb) AS offers;
SELECT t_err('J-211: an offer id that is an organization item is refused (400 item_id_taken)',
  $$SELECT fn_sync_supplier_offers('{"suppliers": [{"supplier_key": "wellspa", "name": "WellSpa", "offers": [{"item_id": "own_a", "display_name": "x", "name_he": "x", "category": "merchandise", "price_golden_spoons": 1}]}]}'::jsonb)$$,
  'item_id_taken');
SELECT t_assert('J-211: the external offer: provider_kind external_supplier, no company, visible to every company',
  (SELECT provider_kind = 'external_supplier' AND company_id IS NULL FROM shop_item_catalog WHERE item_id = 'wellspa_massage')
  AND t_json_as('eb', $$(SELECT count(*) FROM shop_item_catalog WHERE item_id = 'wellspa_massage')$$) = '1'::jsonb);
SELECT t_err_as('J-211: vp_hr cannot edit the external offer → 403', 'hrA',
  $$SELECT rpc_everstore_upsert_item('wellspa_massage', 'Cheap', 'זול', 'health_wellbeing', 1)$$, 'access_denied', 403);

-- ---------- J-213 notice ----------
SELECT t_assert('J-213: the order-screen text (Karin''s text, golden-spoons wording J-226)',
  t_json_as('eb', $$rpc_everstore_supplier_notice()$$) #>> '{}' = 'הספק יודע שאת עובדת בארגון שמשלם לו, אבל לא יודע מה מצבך או כמה כפיות מוזהבות יש לך.');

-- ---------- J-212 order e-mail ----------
SELECT jsonb_typeof(t_json_as('eb', $$rpc_everstore_purchase('wellspa_massage', 'k-1')$$)) AS p1,
       jsonb_typeof(t_json_as('eb2', $$rpc_everstore_purchase('wellspa_massage', 'k-2')$$)) AS p2,
       jsonb_typeof(t_json_as('ea', $$rpc_everstore_purchase('wellspa_massage', 'k-3')$$)) AS p3;
SELECT t_assert('J-212: each order of an external offer queues one supplier e-mail to the config address',
  (SELECT count(*) = 3 AND bool_and(recipient_address = 'orders@wellspa.test') FROM j_outbox WHERE kind = 'supplier_order'));
SELECT t_assert('J-212: the e-mail = the employee name + contact she gave + the benefit — no organization, no spoons, no wellbeing data',
  (SELECT bool_and((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(payload) k) = ARRAY['benefit_name_he', 'employee_contact', 'employee_name']
                   AND payload::text !~* '(company|organization|spoon|כפיות|balance|pcq|ihs|tps|score)')
     FROM j_outbox WHERE kind = 'supplier_order'));
SELECT t_assert('J-212: no field of the monthly report appears in the order e-mail (order_count / amount / organization / month)',
  (SELECT bool_and(NOT (payload ?| ARRAY['organization', 'order_count', 'amount_payable_golden_spoons', 'month', 'benefit_item_id', 'rows']))
     FROM j_outbox WHERE kind = 'supplier_order'));
SELECT t_assert('J-212: an internal item queues no supplier e-mail',
  jsonb_typeof(t_json_as('ea', $$rpc_everstore_purchase('own_a', 'k-own')$$)) = 'object'
  AND (SELECT count(*) = 3 FROM j_outbox WHERE kind = 'supplier_order'));

-- ---------- J-212 monthly report ----------
CREATE TEMP TABLE t_rep AS SELECT fn_supplier_monthly_report('wellspa', CURRENT_DATE) AS j;
SELECT t_assert('J-212: monthly report per organization and per benefit: order count + amount only (B: 2 × 30 = 60; A: 1 × 30)',
  (SELECT j->'rows' = jsonb_build_array(
     jsonb_build_object('organization', 'Company A', 'benefit_item_id', 'wellspa_massage', 'order_count', 1, 'amount_payable_golden_spoons', 30.0),
     jsonb_build_object('organization', 'Company B', 'benefit_item_id', 'wellspa_massage', 'order_count', 2, 'amount_payable_golden_spoons', 60.0)) FROM t_rep));
SELECT t_assert('J-212: the report carries no dates, order codes, sequence or names (no user / purchase id, no employee name)',
  (SELECT t_free_of(j, t_all_user_ids() || ARRAY['Person ', '@j.test', 'k-1', 'k-2'])
          AND t_free_of(j, (SELECT array_agg(purchase_id::text) FROM shop_purchase))
          AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(j->'rows') r, jsonb_object_keys(r) k WHERE k ~* '(date|_at|id$|seq|name)' AND k <> 'benefit_item_id')
     FROM t_rep));
SELECT t_assert('J-212: the report is queued once per supplier + month (idempotent), ILS per golden spoon "לא הוגדר"',
  (SELECT count(*) = 1 FROM j_outbox WHERE kind = 'supplier_monthly_report') AND fn_supplier_monthly_report('wellspa', CURRENT_DATE) IS NOT NULL);
SELECT t_assert('J-212: still one report row after a second run; payload ILS rate = לא הוגדר',
  (SELECT count(*) = 1 AND bool_and(payload->>'ils_per_golden_spoon' = 'לא הוגדר') FROM j_outbox WHERE kind = 'supplier_monthly_report'));
SELECT t_err_as('J-212: a client cannot build a supplier report → 42501', 'hrA',
  $$SELECT fn_supplier_monthly_report('wellspa', CURRENT_DATE)$$, '42501');
SELECT t_assert('J-211: supplier tables are closed to clients',
  NOT has_table_privilege('authenticated', 'everstore_supplier', 'SELECT') AND NOT has_table_privilege('authenticated', 'everstore_supplier_offer', 'SELECT'));
SELECT t_assert('EverStore purchases are never deleted by this module (no DELETE on shop_purchase in modules)',
  NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
               WHERE n.nspname = 'public' AND p.prosrc ~* 'delete\s+from\s+(shop_purchase|golden_spoon_ledger|avatar_state)'));

SELECT 'ALL J EVERSTORE TESTS PASSED' AS result;
