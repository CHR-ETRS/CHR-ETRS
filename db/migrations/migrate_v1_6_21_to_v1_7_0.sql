-- =============================================================================
-- CHR-ETRS MVP v1.7.0 · migrations/migrate_v1_6_21_to_v1_7_0.sql — upgrade an existing v1.6.21 database (Karin 16.11)
-- One transaction: schema.sql (idempotent upgrade blocks: app_role + researcher / external_auditor, research threshold
-- 20, golden_spoons_per_cantril = 2 + Cantril re-keyed, reward history recorded_at, ledger 'donated_after_exit', catalog
-- company_id / provider_kind (existing rows → 'platform', J-232), companies.service_ended_at, evidence entered_by) →
-- rpc.sql → modules/all.sql. Nothing is deleted; WORM tables are untouched.
--   dry run : psql -d <db> -v ON_ERROR_STOP=1 -v dry_run=1 -f migrations/migrate_v1_6_21_to_v1_7_0.sql   (rolls back)
--   apply   : psql -d <db> -v ON_ERROR_STOP=1 -f migrations/migrate_v1_6_21_to_v1_7_0.sql
-- Back up first (pg_dump -Fc). Re-running it changes nothing (tests/test_upgrade_v1_7_0.sh).
-- =============================================================================
\set ON_ERROR_STOP 1
\if :{?dry_run}
\else
\set dry_run 0
\endif
BEGIN;
\ir ../schema.sql
\ir ../rpc.sql
\ir ../modules/all.sql
\if :dry_run
ROLLBACK;
\echo 'dry run: rolled back (nothing changed)'
\else
COMMIT;
\echo 'upgrade v1.6.21 → v1.7.0 committed'
\endif
