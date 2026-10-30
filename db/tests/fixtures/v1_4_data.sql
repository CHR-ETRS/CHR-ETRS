-- CHR-ETRS v1.6.10 · tests/fixtures/v1_4_data.sql — small v1.4 data set for the migration tests.
-- v1.6.10: + 2 users near midnight for the tz_edge_review flag (u4: UTC edge, u5: Asia/Jerusalem edge);
--   the first 7 users get a fixed created_at (was now() — could fall near midnight on test day).
-- v1.6.9: + 3 users with an explicit v1.4 created_at for the O-50 start_date trust rule (compared in UTC).
-- Loaded AFTER tests/fixtures/v1_4_schema.sql + v1_4_rpc.sql (real v1.4 structure). No real data.
INSERT INTO companies (company_id, company_name, location) VALUES
  ('10000000-0000-0000-0000-0000000000a1', 'Alpha Ltd', 'Tel Aviv'),
  ('10000000-0000-0000-0000-0000000000b1', 'Beta GmbH', 'Berlin');
INSERT INTO auth.users (id) SELECT ('10000000-0000-0000-0000-00000000000' || i)::uuid FROM generate_series(1, 7) i;
INSERT INTO users (user_id, company_id, manager_id, email, full_name, department, app_role, timezone, country_code, start_date) VALUES
  ('10000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-0000000000a1', NULL, 'hr@alpha', 'HR A', 'HR', 'vp_hr', 'Asia/Jerusalem', 'IL', DATE '2024-01-01'),
  ('10000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-0000000000a1', NULL, 'mgr@alpha', 'Mgr A', 'Ops', 'manager', 'Asia/Jerusalem', 'IL', DATE '2024-02-01'),
  ('10000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-0000000000a1', '10000000-0000-0000-0000-000000000002', 'e1@alpha', 'E1', 'Ops', 'employee', 'Asia/Jerusalem', NULL, DATE '2025-03-01'),
  ('10000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-0000000000a1', '10000000-0000-0000-0000-000000000002', 'e2@alpha', 'E2', 'Ops', 'employee', 'Asia/Jerusalem', NULL, DATE '2025-04-01'),
  ('10000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-0000000000a1', NULL, 'legal@alpha', 'Legal A', 'Legal', 'legal_ethics', 'Asia/Jerusalem', NULL, DATE '2024-05-01'),
  ('10000000-0000-0000-0000-000000000006', '10000000-0000-0000-0000-0000000000b1', NULL, 'b1@beta', 'B1', 'R&D', 'employee', 'Europe/Berlin', 'DE', NULL),
  ('10000000-0000-0000-0000-000000000007', '10000000-0000-0000-0000-0000000000b1', '10000000-0000-0000-0000-000000000006', 'b2@beta', 'B2', 'R&D', 'employee', 'Europe/Berlin', 'DE', DATE '2025-06-01');
-- v1.6.9 (O-50 migration rule): start_date vs the record's creation date (v1.4 users.created_at, UTC date portion)
--   u1: start_date = creation date (2025-09-14)            → untrusted → hire_date NULL, audited start_date_untrusted
--   u2: start_date 2025-09-01, created 2025-09-14          → trusted   → hire_date 2025-09-01
--   u3: start_date 2025-09-15, created 2025-09-14 22:30 UTC (= 09-15 01:30 Asia/Jerusalem) → trusted under the UTC rule
INSERT INTO auth.users (id) VALUES ('10000000-0000-0000-0000-000000000008'), ('10000000-0000-0000-0000-000000000009'), ('10000000-0000-0000-0000-000000000010');
INSERT INTO users (user_id, company_id, manager_id, email, full_name, department, app_role, timezone, country_code, start_date, created_at) VALUES
  ('10000000-0000-0000-0000-000000000008', '10000000-0000-0000-0000-0000000000b1', NULL, 'u1@beta', 'U1', 'R&D', 'employee', 'Europe/Berlin', 'DE', DATE '2025-09-14', TIMESTAMPTZ '2025-09-14 10:00+00'),
  ('10000000-0000-0000-0000-000000000009', '10000000-0000-0000-0000-0000000000b1', NULL, 'u2@beta', 'U2', 'R&D', 'employee', 'Europe/Berlin', 'DE', DATE '2025-09-01', TIMESTAMPTZ '2025-09-14 10:00+00'),
  ('10000000-0000-0000-0000-000000000010', '10000000-0000-0000-0000-0000000000a1', NULL, 'u3@alpha', 'U3', 'Ops', 'employee', 'Asia/Jerusalem', 'IL', DATE '2025-09-15', TIMESTAMPTZ '2025-09-14 22:30+00');
-- spoons history: 3 days × 4 employees
INSERT INTO spoon_budget (user_id, budget_date, current_spoon_count, updated_at)
SELECT u, DATE '2026-10-01' + d, 12 - ((d * 3 + k) % 10), TIMESTAMPTZ '2026-10-01 18:00+03' + d * interval '1 day'
  FROM (VALUES ('10000000-0000-0000-0000-000000000003'::uuid, 1), ('10000000-0000-0000-0000-000000000004'::uuid, 2),
               ('10000000-0000-0000-0000-000000000006'::uuid, 3), ('10000000-0000-0000-0000-000000000007'::uuid, 4)) x(u, k),
       generate_series(0, 2) d;
INSERT INTO avatar_state (user_id, golden_spoons, chr_coins) VALUES
  ('10000000-0000-0000-0000-000000000003', 7, 2), ('10000000-0000-0000-0000-000000000006', 3, 0);
INSERT INTO team_aggregate (org_id, department, member_count, team_spoon_avg) VALUES
  ('10000000-0000-0000-0000-0000000000a1', 'Ops', 5, 7.50);
INSERT INTO employee_value_asset (user_id, company_id, annual_salary) VALUES
  ('10000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-0000000000a1', NULL);
-- v1.6.10 (rule 4, tz preflight): fixed creation time for the first 7 users (before every start date; no midnight edge in any test zone)
UPDATE users SET created_at = TIMESTAMPTZ '2023-06-15 09:00+00'
 WHERE user_id IN (SELECT ('10000000-0000-0000-0000-00000000000' || i)::uuid FROM generate_series(1, 7) i);
-- v1.6.10 tz_edge_review (created within 1 h of local midnight; flag only, both trusted — start 2025-09-01):
--   u4: created 2025-09-20 23:40 UTC (= 09-21 02:40 Asia/Jerusalem) → edge when compared in UTC
--   u5: created 2025-09-21 21:30 UTC (= 09-22 00:30 Asia/Jerusalem) → edge when compared in Asia/Jerusalem
INSERT INTO auth.users (id) VALUES ('10000000-0000-0000-0000-000000000011'), ('10000000-0000-0000-0000-000000000012');
INSERT INTO users (user_id, company_id, manager_id, email, full_name, department, app_role, timezone, country_code, start_date, created_at) VALUES
  ('10000000-0000-0000-0000-000000000011', '10000000-0000-0000-0000-0000000000b1', NULL, 'u4@beta', 'U4', 'R&D', 'employee', 'Europe/Berlin', 'DE', DATE '2025-09-01', TIMESTAMPTZ '2025-09-20 23:40+00'),
  ('10000000-0000-0000-0000-000000000012', '10000000-0000-0000-0000-0000000000a1', NULL, 'u5@alpha', 'U5', 'Ops', 'employee', 'Asia/Jerusalem', 'IL', DATE '2025-09-01', TIMESTAMPTZ '2025-09-21 21:30+00');
